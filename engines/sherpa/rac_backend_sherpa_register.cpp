/**
 * @file rac_backend_sherpa_register.cpp
 * @brief RunAnywhere Core - Sherpa Backend RAC Registration
 *
 * Registers the Sherpa backend with the module and service registries.
 * Provides vtable implementations for STT, TTS, and VAD services.
 */

#include "rac_stt_sherpa.h"
#include "rac_tts_sherpa.h"
#include "rac_vad_sherpa.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/audio/rac_audio_convert.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char *LOG_CAT = "Sherpa";

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0] via the shared
 * commons helper (`rac_audio_pcm16_to_float32`). Sherpa-ONNX expects Float32.
 */
static std::vector<float> convert_int16_to_float32(const void *int16_data,
                                                   size_t byte_count) {
  const int16_t *samples = static_cast<const int16_t *>(int16_data);
  size_t num_samples = byte_count / sizeof(int16_t);

  std::vector<float> float_samples(num_samples);
  rac::audio::rac_audio_pcm16_to_float32(samples, num_samples,
                                         float_samples.data());
  return float_samples;
}

// Initialize (no-op for Sherpa - model loaded during create)
static rac_result_t sherpa_stt_vtable_initialize(void *impl,
                                                 const char *model_path) {
  (void)impl;
  (void)model_path;
  return RAC_SUCCESS;
}

// Transcribe - converts Int16 PCM to Float32 for Sherpa-ONNX
static rac_result_t sherpa_stt_vtable_transcribe(
    void *impl, const void *audio_data, size_t audio_size,
    const rac_stt_options_t *options, rac_stt_result_t *out_result) {
  if (!audio_data || audio_size == 0 || !out_result) {
    return RAC_ERROR_INVALID_ARGUMENT;
  }
  // Minimum ~0.05s at 16kHz 16-bit to avoid Sherpa crash on empty/tiny input
  if (audio_size < 1600) {
    out_result->text = nullptr;
    out_result->confidence = 0.0f;
    return RAC_SUCCESS;
  }
  std::vector<float> float_samples =
      convert_int16_to_float32(audio_data, audio_size);
  return rac_stt_sherpa_transcribe(impl, float_samples.data(),
                                   float_samples.size(), options, out_result);
}

// Stream transcription - uses Sherpa streaming API
static rac_result_t sherpa_stt_vtable_transcribe_stream(
    void *impl, const void *audio_data, size_t audio_size,
    const rac_stt_options_t *options, rac_stt_stream_callback_t callback,
    void *user_data) {
  rac_handle_t stream = nullptr;
  rac_result_t result = rac_stt_sherpa_create_stream(impl, &stream);
  if (result != RAC_SUCCESS) {
    return result;
  }

  std::vector<float> float_samples =
      convert_int16_to_float32(audio_data, audio_size);

  // engines-sherpa-003: forward the caller's sample rate from options so
  // 48k/44.1k captures are not silently re-interpreted as 16k inside the
  // backend feature frontend.
  const int sample_rate =
      (options && options->sample_rate > 0) ? options->sample_rate : 16000;
  result = rac_stt_sherpa_feed_audio(impl, stream, float_samples.data(),
                                     float_samples.size(), sample_rate);
  if (result != RAC_SUCCESS) {
    rac_stt_sherpa_destroy_stream(impl, stream);
    return result;
  }

  rac_stt_sherpa_input_finished(impl, stream);

  char *text = nullptr;
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
static rac_result_t sherpa_stt_vtable_get_info(void *impl,
                                               rac_stt_info_t *out_info) {
  if (!out_info)
    return RAC_ERROR_NULL_POINTER;

  out_info->is_ready = RAC_TRUE;
  out_info->supports_streaming = rac_stt_sherpa_supports_streaming(impl);
  out_info->current_model = nullptr;

  return RAC_SUCCESS;
}

// Cleanup
static rac_result_t sherpa_stt_vtable_cleanup(void *impl) {
  (void)impl;
  return RAC_SUCCESS;
}

// Destroy
static void sherpa_stt_vtable_destroy(void *impl) {
  if (impl) {
    rac_stt_sherpa_destroy(impl);
  }
}

// v3 Phase B3: Sherpa STT `create` adapter called by commons rac_stt_create()
// through rac_plugin_route. Replaces the legacy rac_service_provider_t factory.
// DUP-03: scaffold generated by RAC_DEFINE_CREATE_ADAPTER. The expansion
// forwards to rac_stt_sherpa_create(model_id, nullptr, &handle).
RAC_DEFINE_CREATE_ADAPTER(stt, sherpa)

static rac_result_t sherpa_stt_vtable_get_languages(void *impl,
                                                    char **out_json) {
  return rac_stt_sherpa_get_languages(impl, out_json);
}

static rac_result_t sherpa_stt_vtable_detect_language(
    void *impl, const void *audio_data, size_t audio_size,
    const rac_stt_options_t *options, char **out_language) {
  return rac_stt_sherpa_detect_language(impl, audio_data, audio_size, options,
                                        out_language);
}

} // namespace

// Keep external C linkage so rac_plugin_entry_sherpa.cpp can wire this ops
// table in both static and shared builds.
//
// CPP-14 (Wave 1) persistent per-session stream slots are intentionally
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

namespace { // reopen for the next batch of static helpers

// =============================================================================
// TTS VTABLE IMPLEMENTATION
// =============================================================================

static rac_result_t sherpa_tts_vtable_initialize(void *impl) {
  (void)impl;
  return RAC_SUCCESS;
}

static rac_result_t
sherpa_tts_vtable_synthesize(void *impl, const char *text,
                             const rac_tts_options_t *options,
                             rac_tts_result_t *out_result) {
  return rac_tts_sherpa_synthesize(impl, text, options, out_result);
}

static rac_result_t sherpa_tts_vtable_synthesize_stream(
    void *impl, const char *text, const rac_tts_options_t *options,
    rac_tts_stream_callback_t callback, void *user_data) {
  rac_tts_result_t result = {};
  rac_result_t status = rac_tts_sherpa_synthesize(impl, text, options, &result);
  if (status == RAC_SUCCESS && callback) {
    callback(result.audio_data, result.audio_size, user_data);
  }
  rac_tts_result_free(&result);
  return status;
}

static rac_result_t sherpa_tts_vtable_stop(void *impl) {
  // hotspot-engine-sherpa-004: still mark the in-flight cancel flag so any
  // synthesize() that is currently blocked inside SherpaOnnxOfflineTtsGenerate
  // will drop its post-generation result instead of emitting it. But the
  // Sherpa-ONNX C TTS API exposes no preemption hook for VITS/Piper
  // generation, so we cannot truly stop ongoing compute. Returning
  // RAC_SUCCESS here would mislead the lifecycle stop ABI
  // (rac_tts_stop_lifecycle_proto -> TTSServiceState.is_ready=true) and the
  // Kotlin / Flutter / RN / Swift stream-cancellation paths into believing
  // synthesis was actually stopped while Piper continues to run. Surface the
  // capability gap honestly with RAC_ERROR_NOT_SUPPORTED.
  rac_tts_sherpa_stop(impl);
  return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t sherpa_tts_vtable_get_info(void *impl,
                                               rac_tts_info_t *out_info) {
  // Forward to the per-handle helper so the lifecycle voice-list ABI
  // (rac_nonllm_lifecycle_proto_abi.cpp / tts_component.cpp) sees the
  // speakers Sherpa enumerated during load_model rather than the previous
  // empty fallback that masked every multi-speaker Piper model.
  return rac_tts_sherpa_get_info(impl, out_info);
}

static rac_result_t sherpa_tts_vtable_cleanup(void *impl) {
  (void)impl;
  return RAC_SUCCESS;
}

static void sherpa_tts_vtable_destroy(void *impl) {
  if (impl) {
    rac_tts_sherpa_destroy(impl);
  }
}

// v3 Phase B3: Sherpa TTS `create` adapter — DUP-03 scaffold via macro.
RAC_DEFINE_CREATE_ADAPTER(tts, sherpa)

static rac_result_t sherpa_tts_vtable_get_languages(void *impl,
                                                    char **out_json) {
  return rac_tts_sherpa_get_languages(impl, out_json);
}

} // namespace

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

static rac_result_t sherpa_vad_vtable_process(void *impl, const float *samples,
                                              size_t num_samples,
                                              rac_bool_t *out_is_speech) {
  return rac_vad_sherpa_process(static_cast<rac_handle_t>(impl), samples,
                                num_samples, out_is_speech);
}

static rac_result_t sherpa_vad_vtable_start(void *impl) {
  return rac_vad_sherpa_start(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_stop(void *impl) {
  return rac_vad_sherpa_stop(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_reset(void *impl) {
  return rac_vad_sherpa_reset(static_cast<rac_handle_t>(impl));
}

static rac_result_t sherpa_vad_vtable_set_threshold(void *impl,
                                                    float threshold) {
  return rac_vad_sherpa_set_threshold(static_cast<rac_handle_t>(impl),
                                      threshold);
}

static rac_bool_t sherpa_vad_vtable_is_speech_active(void *impl) {
  return rac_vad_sherpa_is_speech_active(static_cast<rac_handle_t>(impl));
}

static void sherpa_vad_vtable_destroy(void *impl) {
  if (impl) {
    rac_vad_sherpa_destroy(static_cast<rac_handle_t>(impl));
  }
}

// v3 Phase B3: Sherpa VAD `initialize` — Silero-style VAD models require
// per-instance model loading. When the backend's rac_vad_sherpa_create
// already accepts model_path (it does), initialize here is a no-op
// success. Kept explicitly to honor the new ABI.
static rac_result_t sherpa_vad_vtable_initialize(void * /*impl*/,
                                                 const char * /*model_path*/) {
  return RAC_SUCCESS;
}

// v3 Phase B3: Sherpa VAD `create` adapter — DUP-03 scaffold via macro.
// Note: the previous hand-written version included an extra RAC_LOG_ERROR +
// rc==SUCCESS/handle==nullptr recovery branch. Dropped: rac_vad_sherpa_create
// never returns RAC_SUCCESS with a null out_handle (it asserts internally),
// and the error log already fires inside rac_vad_sherpa_create's failure
// paths via rac_error_set_details.
RAC_DEFINE_CREATE_ADAPTER(vad, sherpa)

} // namespace

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
// ENG-SHERPA-03: standardized registration. Mirrors the llamacpp + onnx
// pattern — one explicit `rac_backend_<name>_register()` entry point that
// registers both the module record and the unified plugin vtable with the
// registry. Replaces the deleted ELF `__attribute__((constructor))` auto-
// register block that previously lived at the bottom of
// rac_plugin_entry_sherpa.cpp. iOS / WASM hosts still exercise the static
// path via RAC_STATIC_PLUGIN_REGISTER(sherpa) (see
// rac_static_register_sherpa.cpp); dynamic hosts (Android, Linux, macOS
// dev) call this function explicitly from the SDK bridge.

namespace {

bool g_sherpa_registered = false;

} // namespace

extern "C" {

rac_result_t rac_backend_sherpa_register(void) {
  if (g_sherpa_registered) {
    return RAC_ERROR_MODULE_ALREADY_REGISTERED;
  }

  rac_module_info_t module_info = {};
  module_info.id = "sherpa";
  module_info.name = "Sherpa-ONNX";
  module_info.version = "1.0.0";
  module_info.description = "Sherpa-ONNX backend (STT / TTS / VAD)";
  module_info.capabilities = nullptr;
  module_info.num_capabilities = 0;

  rac_result_t result = rac_module_register(&module_info);
  if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
    return result;
  }

  const rac_engine_vtable_t *vt = rac_plugin_entry_sherpa();
  if (vt != nullptr) {
    rac_result_t plugin_rc = rac_plugin_register(vt);
    if (plugin_rc != RAC_SUCCESS &&
        plugin_rc != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
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
  rac_module_unregister("sherpa");

  g_sherpa_registered = false;
  return RAC_SUCCESS;
}

} // extern "C"
