/**
 * @file rac_backend_sherpa_register.cpp
 * @brief RunAnywhere Core - Sherpa Backend RAC Registration
 *
 * Registers the Sherpa backend's unified plugin vtable with the plugin
 * registry. Provides vtable implementations for STT, TTS, and VAD services.
 */

#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "rac_vad_sherpa.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "rac/audio/rac_audio_convert.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char* LOG_CAT = "Sherpa";

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0] via the shared
 * commons helper (`rac_audio_pcm16_to_float32`). Sherpa-ONNX expects Float32.
 */
static std::vector<float> convert_int16_to_float32(const void* int16_data, size_t byte_count) {
    const int16_t* samples = static_cast<const int16_t*>(int16_data);
    size_t num_samples = byte_count / sizeof(int16_t);

    std::vector<float> float_samples(num_samples);
    rac::audio::rac_audio_pcm16_to_float32(samples, num_samples, float_samples.data());
    return float_samples;
}

// Parsed view into a WAV/RIFF buffer: a pointer to the PCM `data` chunk plus
// the format fields needed to feed sherpa correctly.
struct WavPcm {
    const uint8_t* pcm = nullptr;
    size_t pcm_bytes = 0;
    uint32_t sample_rate = 0;
    uint16_t channels = 0;
    uint16_t bits = 0;
};

// Minimal WAV reader. Walks RIFF chunks (does not assume a fixed 44-byte
// header) to locate `fmt ` + `data`. Fills `out` and returns true only for
// uncompressed PCM (fmt tag 1). All RAC Android targets are little-endian, as
// is the WAV byte order, so the integer fields are read directly. Returns
// false on truncation, a missing chunk, or any non-PCM encoding.
static bool parse_wav_pcm(const uint8_t* data, size_t size, WavPcm& out) {
    if (size < 44 || std::memcmp(data, "RIFF", 4) != 0 || std::memcmp(data + 8, "WAVE", 4) != 0) {
        return false;
    }
    uint16_t fmt_tag = 0;
    bool have_fmt = false;
    bool have_data = false;
    size_t off = 12;  // first sub-chunk after "RIFF"<size>"WAVE"
    while (off + 8 <= size) {
        uint32_t chunk_size = 0;
        std::memcpy(&chunk_size, data + off + 4, 4);
        const size_t body = off + 8;
        if (std::memcmp(data + off, "fmt ", 4) == 0 && body + 16 <= size) {
            std::memcpy(&fmt_tag, data + body + 0, 2);
            std::memcpy(&out.channels, data + body + 2, 2);
            std::memcpy(&out.sample_rate, data + body + 4, 4);
            std::memcpy(&out.bits, data + body + 14, 2);
            have_fmt = true;
        } else if (std::memcmp(data + off, "data", 4) == 0) {
            const size_t avail = size - body;
            out.pcm = data + body;
            out.pcm_bytes = (chunk_size <= avail) ? chunk_size : avail;
            have_data = true;
        }
        if (have_fmt && have_data) {
            break;
        }
        off = body + chunk_size + (chunk_size & 1u);  // chunks are word-aligned
    }
    return have_fmt && have_data && fmt_tag == 1 /* WAVE_FORMAT_PCM */;
}

// Convert a WAV PCM16 data chunk to mono Float32 in [-1, 1], averaging channels
// when the source is multi-channel (sherpa's offline recognizer is mono).
static std::vector<float> wav_pcm16_to_mono_float(const WavPcm& wav) {
    const int16_t* s = reinterpret_cast<const int16_t*>(wav.pcm);
    const size_t total = wav.pcm_bytes / sizeof(int16_t);
    const uint16_t ch = wav.channels < 1 ? 1 : wav.channels;
    if (ch == 1) {
        std::vector<float> out(total);
        rac::audio::rac_audio_pcm16_to_float32(s, total, out.data());
        return out;
    }
    const size_t frames = total / ch;
    std::vector<float> out(frames);
    for (size_t i = 0; i < frames; ++i) {
        int32_t acc = 0;
        for (uint16_t c = 0; c < ch; ++c) {
            acc += s[i * ch + c];
        }
        out[i] = static_cast<float>(acc) / (static_cast<float>(ch) * 32768.0f);
    }
    return out;
}

// Initialize (no-op for Sherpa - model loaded during create)
static rac_result_t sherpa_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// Transcribe - feeds Float32 mono samples to Sherpa-ONNX.
//
// Honors options->audio_format (the hybrid router shares one payload across the
// offline + cloud backends, so this side may receive a WAV container rather than
// raw PCM): WAV is parsed inline to its PCM data chunk + real sample rate, and
// raw PCM is consumed directly. Compressed containers (MP3/OPUS/AAC/FLAC) need a
// codec sherpa doesn't have — those are rejected so the router fails over to the
// cloud instead of transcribing garbage.
static rac_result_t sherpa_stt_vtable_transcribe(void* impl, const void* audio_data,
                                                 size_t audio_size,
                                                 const rac_stt_options_t* options,
                                                 rac_stt_result_t* out_result) {
    if (!audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const uint8_t* bytes = static_cast<const uint8_t*>(audio_data);
    const rac_audio_format_enum_t fmt = options ? options->audio_format : RAC_AUDIO_FORMAT_PCM;
    const bool looks_wav =
        fmt == RAC_AUDIO_FORMAT_WAV || (audio_size >= 12 && std::memcmp(bytes, "RIFF", 4) == 0 &&
                                        std::memcmp(bytes + 8, "WAVE", 4) == 0);

    if (looks_wav) {
        WavPcm wav{};
        if (!parse_wav_pcm(bytes, audio_size, wav) || wav.bits != 16) {
            RAC_LOG_ERROR(LOG_CAT, "sherpa STT: unsupported WAV (parse failed or not 16-bit PCM)");
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        // Tiny-clip guard on the decoded PCM (~0.05s at 16kHz 16-bit). NaN (not
        // 0.0f) tells the hybrid router "no confidence signal" so it does not
        // wrongly cascade on a too-short clip.
        if (wav.pcm_bytes < 1600) {
            out_result->text = nullptr;
            out_result->confidence = std::numeric_limits<float>::quiet_NaN();
            return RAC_SUCCESS;
        }
        std::vector<float> float_samples = wav_pcm16_to_mono_float(wav);
        rac_stt_options_t opt{};
        if (options) {
            opt = *options;
        }
        opt.sample_rate = static_cast<int32_t>(wav.sample_rate);
        opt.audio_format = RAC_AUDIO_FORMAT_PCM;
        return rac_stt_sherpa_transcribe(impl, float_samples.data(), float_samples.size(), &opt,
                                         out_result);
    }

    if (fmt != RAC_AUDIO_FORMAT_PCM) {
        RAC_LOG_ERROR(LOG_CAT, "sherpa STT cannot decode audio_format=%d (PCM/WAV only)",
                      static_cast<int>(fmt));
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Raw Int16 PCM. Minimum ~0.05s at 16kHz 16-bit to avoid a Sherpa crash on
    // empty/tiny input; NaN confidence = "no signal" for the router.
    if (audio_size < 1600) {
        out_result->text = nullptr;
        out_result->confidence = std::numeric_limits<float>::quiet_NaN();
        return RAC_SUCCESS;
    }
    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);
    return rac_stt_sherpa_transcribe(impl, float_samples.data(), float_samples.size(), options,
                                     out_result);
}

// Stream transcription - uses Sherpa streaming API
static rac_result_t sherpa_stt_vtable_transcribe_stream(void* impl, const void* audio_data,
                                                        size_t audio_size,
                                                        const rac_stt_options_t* options,
                                                        rac_stt_stream_callback_t callback,
                                                        void* user_data) {
    rac_handle_t stream = nullptr;
    rac_result_t result = rac_stt_sherpa_create_stream(impl, &stream);
    if (result != RAC_SUCCESS) {
        return result;
    }

    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);

    // Forward the caller's sample rate from options so
    // 48k/44.1k captures are not silently re-interpreted as 16k inside the
    // backend feature frontend.
    const int sample_rate = (options && options->sample_rate > 0) ? options->sample_rate : 16000;

    // Offline Whisper recognizers do not emit incremental callbacks from a
    // single decode. Produce cumulative partials from a bounded number of
    // prefixes, then run the canonical full utterance below for the final
    // result. Spacing longer inputs evenly keeps the number of complete
    // re-decodes constant instead of growing quadratically with duration.
    constexpr size_t kMaxSyntheticPartialDecodes = 4;
    const size_t minimum_partial_stride = static_cast<size_t>(sample_rate) * 3;
    const size_t partial_interval_count = kMaxSyntheticPartialDecodes + 1;
    const size_t evenly_spaced_stride =
        float_samples.size() / partial_interval_count +
        (float_samples.size() % partial_interval_count != 0 ? 1 : 0);
    const size_t partial_stride = std::max(minimum_partial_stride, evenly_spaced_stride);
    std::string last_partial;
    for (size_t partial_index = 1; partial_index <= kMaxSyntheticPartialDecodes;
         ++partial_index) {
        const size_t prefix = partial_stride * partial_index;
        if (prefix >= float_samples.size()) {
            break;
        }
        rac_handle_t partial_stream = nullptr;
        if (rac_stt_sherpa_create_stream(impl, &partial_stream) != RAC_SUCCESS) {
            break;
        }
        const rac_result_t feed_result = rac_stt_sherpa_feed_audio(
            impl, partial_stream, float_samples.data(), prefix, sample_rate);
        if (feed_result != RAC_SUCCESS) {
            rac_stt_sherpa_destroy_stream(impl, partial_stream);
            break;
        }
        rac_stt_sherpa_input_finished(impl, partial_stream);
        char* partial_text = nullptr;
        const rac_result_t decode_result =
            rac_stt_sherpa_decode_stream(impl, partial_stream, &partial_text);
        if (decode_result == RAC_SUCCESS && callback && partial_text && partial_text[0] != '\0') {
            const std::string current_partial(partial_text);
            if (current_partial != last_partial) {
                callback(partial_text, RAC_FALSE, user_data);
                last_partial = current_partial;
            }
        }
        if (partial_text) {
            free(partial_text);
        }
        rac_stt_sherpa_destroy_stream(impl, partial_stream);
    }

    result = rac_stt_sherpa_feed_audio(impl, stream, float_samples.data(), float_samples.size(),
                                       sample_rate);
    if (result != RAC_SUCCESS) {
        rac_stt_sherpa_destroy_stream(impl, stream);
        return result;
    }

    rac_stt_sherpa_input_finished(impl, stream);

    char* text = nullptr;
    result = rac_stt_sherpa_decode_stream(impl, stream, &text);
    if (result == RAC_SUCCESS && callback && text) {
        callback(text, RAC_TRUE, user_data);
    }

    rac_stt_sherpa_destroy_stream(impl, stream);
    if (text)
        free(text);

    return result;
}

// Get info
static rac_result_t sherpa_stt_vtable_get_info(void* impl, rac_stt_info_t* out_info) {
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = rac_stt_sherpa_supports_streaming(impl);
    out_info->current_model = nullptr;

    return RAC_SUCCESS;
}

// Cleanup
static rac_result_t sherpa_stt_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void sherpa_stt_vtable_destroy(void* impl) {
    if (impl) {
        rac_stt_sherpa_destroy(impl);
    }
}

// Sherpa STT `create` adapter called by commons rac_stt_create()
// through rac_plugin_find. Replaces the legacy rac_service_provider_t factory.
// Scaffold generated by RAC_DEFINE_CREATE_ADAPTER. The expansion
// forwards to rac_stt_sherpa_create(model_id, nullptr, &handle).
RAC_DEFINE_CREATE_ADAPTER(stt, sherpa)

static rac_result_t sherpa_stt_vtable_get_languages(void* impl, char** out_json) {
    return rac_stt_sherpa_get_languages(impl, out_json);
}

static rac_result_t sherpa_stt_vtable_detect_language(void* impl, const void* audio_data,
                                                      size_t audio_size,
                                                      const rac_stt_options_t* options,
                                                      char** out_language) {
    return rac_stt_sherpa_detect_language(impl, audio_data, audio_size, options, out_language);
}

}  // namespace

// Keep external C linkage so rac_plugin_entry_sherpa.cpp can wire this ops
// table in both static and shared builds.
//
// Persistent per-session stream slots are intentionally
// NULL: the underlying Sherpa-ONNX integration here is backed by the
// *offline* recognizer (engines/sherpa/sherpa_backend.cpp::SherpaSTT —
// SherpaOnnxCreateOfflineStream + SherpaOnnxDecodeOfflineStream every
// feed, no endpoint detection, no final emission). Wiring those slots
// caused commons to take the persistent path
// (rac_stt_stream.cpp:319-410), which then produced repeated offline
// re-decodes as partials and never emitted a final/endpoint event,
// violating the STT stream contract. Leaving the slots NULL forces
// commons back onto the legacy transcribe_stream behavior — paying the
// per-chunk decode cost but preserving correctness — until an online
// recognizer implementation lands here.
extern "C" const rac_stt_service_ops_t g_sherpa_stt_ops = {
    .initialize = sherpa_stt_vtable_initialize,
    .transcribe = sherpa_stt_vtable_transcribe,
    .transcribe_stream = sherpa_stt_vtable_transcribe_stream,
    .get_info = sherpa_stt_vtable_get_info,
    .cleanup = sherpa_stt_vtable_cleanup,
    .destroy = sherpa_stt_vtable_destroy,
    .create = sherpa_stt_create_impl,
    .get_languages = sherpa_stt_vtable_get_languages,
    .detect_language = sherpa_stt_vtable_detect_language,
    .stream_create = nullptr,
    .stream_feed_audio_chunk = nullptr,
    .stream_destroy = nullptr,
};

namespace {  // reopen for the next batch of static helpers

// =============================================================================
// TTS VTABLE IMPLEMENTATION
// =============================================================================

static rac_result_t sherpa_tts_vtable_initialize(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

static rac_result_t sherpa_tts_vtable_synthesize(void* impl, const char* text,
                                                 const rac_tts_options_t* options,
                                                 rac_tts_result_t* out_result) {
    return rac_tts_sherpa_synthesize(impl, text, options, out_result);
}

static rac_result_t sherpa_tts_vtable_synthesize_stream(void* impl, const char* text,
                                                        const rac_tts_options_t* options,
                                                        rac_tts_stream_callback_t callback,
                                                        void* user_data) {
    rac_tts_result_t result = {};
    rac_result_t status = rac_tts_sherpa_synthesize(impl, text, options, &result);
    if (status == RAC_SUCCESS && callback) {
        callback(result.audio_data, result.audio_size, user_data);
    }
    rac_tts_result_free(&result);
    return status;
}

static rac_result_t sherpa_tts_vtable_stop(void* impl) {
    // Set the in-flight cancel flag so any synthesize() that
    // is currently blocked inside SherpaOnnxOfflineTtsGenerate will drop its
    // post-generation result (sherpa_backend.cpp:1423 honors cancel_requested_
    // after the blocking generator returns). The Sherpa-ONNX C TTS API has no
    // preemption hook for VITS/Piper, so ongoing compute cannot be truly
    // killed, but the stop *request* at the ABI level succeeds — the audio
    // chunk/completion is suppressed via the cancel flag. Returning
    // RAC_ERROR_NOT_SUPPORTED here made rac_tts_stop_lifecycle_proto report
    // TTSServiceState.is_ready=false on every stop, leaving Kotlin / Flutter /
    // RN / Swift lifecycle state stuck after a normal cancel. RAC_SUCCESS is
    // the correct semantic for "stop accepted; in-flight result will be
    // dropped". Backends that need to advertise preemption-not-supported as a
    // capability should do so via vtable capability_check, not by failing every
    // stop call.
    rac_tts_sherpa_stop(impl);
    return RAC_SUCCESS;
}

static rac_result_t sherpa_tts_vtable_get_info(void* impl, rac_tts_info_t* out_info) {
    // Forward to the per-handle helper so the lifecycle voice-list ABI
    // (rac_nonllm_lifecycle_proto_abi.cpp / tts_component.cpp) sees the
    // speakers Sherpa enumerated during load_model rather than the previous
    // empty fallback that masked every multi-speaker Piper model.
    return rac_tts_sherpa_get_info(impl, out_info);
}

static rac_result_t sherpa_tts_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

static void sherpa_tts_vtable_destroy(void* impl) {
    if (impl) {
        rac_tts_sherpa_destroy(impl);
    }
}

// Sherpa TTS `create` adapter — scaffold via macro.
RAC_DEFINE_CREATE_ADAPTER(tts, sherpa)

static rac_result_t sherpa_tts_vtable_get_languages(void* impl, char** out_json) {
    return rac_tts_sherpa_get_languages(impl, out_json);
}

}  // namespace

extern "C" const rac_tts_service_ops_t g_sherpa_tts_ops = {
    .initialize = sherpa_tts_vtable_initialize,
    .synthesize = sherpa_tts_vtable_synthesize,
    .synthesize_stream = sherpa_tts_vtable_synthesize_stream,
    .stop = sherpa_tts_vtable_stop,
    .get_info = sherpa_tts_vtable_get_info,
    .cleanup = sherpa_tts_vtable_cleanup,
    .destroy = sherpa_tts_vtable_destroy,
    .create = sherpa_tts_create_impl,
    .get_languages = sherpa_tts_vtable_get_languages,
};

namespace {

// =============================================================================
// VAD VTABLE OPERATIONS
// =============================================================================

static rac_result_t sherpa_vad_vtable_process(void* impl, const float* samples, size_t num_samples,
                                              rac_bool_t* out_is_speech) {
    return rac_vad_sherpa_process(static_cast<rac_handle_t>(impl), samples, num_samples,
                                  out_is_speech);
}

static rac_result_t sherpa_vad_vtable_start(void* impl) {
    return rac_vad_sherpa_start(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_stop(void* impl) {
    return rac_vad_sherpa_stop(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_reset(void* impl) {
    return rac_vad_sherpa_reset(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_set_threshold(void* impl, float threshold) {
    return rac_vad_sherpa_set_threshold(static_cast<rac_handle_t>(impl), threshold);
}

static rac_bool_t sherpa_vad_vtable_is_speech_active(void* impl) {
    return rac_vad_sherpa_is_speech_active(static_cast<rac_handle_t>(impl));
}

static void sherpa_vad_vtable_destroy(void* impl) {
    if (impl) {
        rac_vad_sherpa_destroy(static_cast<rac_handle_t>(impl));
    }
}

// Sherpa VAD `initialize` — Silero-style VAD models require
// per-instance model loading. When the backend's rac_vad_sherpa_create
// already accepts model_path (it does), initialize here is a no-op
// success. Kept explicitly to honor the new ABI.
static rac_result_t sherpa_vad_vtable_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}

// Sherpa VAD `create` adapter — scaffold via macro.
// Note: the previous hand-written version included an extra RAC_LOG_ERROR +
// rc==SUCCESS/handle==nullptr recovery branch. Dropped: rac_vad_sherpa_create
// never returns RAC_SUCCESS with a null out_handle (it asserts internally),
// and the error log already fires inside rac_vad_sherpa_create's failure
// paths via rac_error_set_details.
RAC_DEFINE_CREATE_ADAPTER(vad, sherpa)

}  // namespace

extern "C" const rac_vad_service_ops_t g_sherpa_vad_ops = {
    .process = sherpa_vad_vtable_process,
    .start = sherpa_vad_vtable_start,
    .stop = sherpa_vad_vtable_stop,
    .reset = sherpa_vad_vtable_reset,
    .set_threshold = sherpa_vad_vtable_set_threshold,
    .is_speech_active = sherpa_vad_vtable_is_speech_active,
    .destroy = sherpa_vad_vtable_destroy,
    .initialize = sherpa_vad_vtable_initialize,
    .create = sherpa_vad_create_impl,
};

// =============================================================================
// REGISTRATION API
// =============================================================================
//
// Standardized registration. Mirrors the llamacpp + onnx
// pattern — one explicit `rac_backend_<name>_register()` entry point that
// registers the unified plugin vtable with the plugin registry via
// rac_plugin_register(). Replaces the deleted ELF `__attribute__((constructor))` auto-
// register block that previously lived at the bottom of
// rac_plugin_entry_sherpa.cpp. iOS / WASM hosts still exercise the static
// path via RAC_STATIC_PLUGIN_REGISTER(sherpa) (see
// rac_static_register_sherpa.cpp); dynamic hosts (Android, Linux, macOS
// dev) call this function explicitly from the SDK bridge.

namespace {

bool g_sherpa_registered = false;

}  // namespace

extern "C" {

rac_result_t rac_backend_sherpa_register(void) {
    if (g_sherpa_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_sherpa();
    if (vt != nullptr) {
        rac_result_t plugin_rc = rac_plugin_register(vt);
        if (plugin_rc != RAC_SUCCESS && plugin_rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            RAC_LOG_WARNING(LOG_CAT, "rac_plugin_register failed: %d", plugin_rc);
        } else {
            RAC_LOG_INFO(LOG_CAT, "rac_plugin_register succeeded for 'sherpa'");
        }
    }

    g_sherpa_registered = true;
    RAC_LOG_INFO(LOG_CAT, "Sherpa backend registered (module + plugin)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_sherpa_unregister(void) {
    if (!g_sherpa_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_plugin_unregister("sherpa");

    g_sherpa_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
