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

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

// =============================================================================
// STT VTABLE IMPLEMENTATION
// =============================================================================

namespace {

const char* LOG_CAT = "Sherpa";

/**
 * Convert Int16 PCM audio to Float32 normalized to [-1.0, 1.0].
 * SDKs may send Int16 audio but Sherpa-ONNX expects Float32.
 */
static std::vector<float> convert_int16_to_float32(const void* int16_data, size_t byte_count) {
    const int16_t* samples = static_cast<const int16_t*>(int16_data);
    size_t num_samples = byte_count / sizeof(int16_t);

    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = static_cast<float>(samples[i]) / 32768.0f;
    }

    return float_samples;
}

// Initialize (no-op for Sherpa - model loaded during create)
static rac_result_t sherpa_stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

// Transcribe - converts Int16 PCM to Float32 for Sherpa-ONNX
static rac_result_t sherpa_stt_vtable_transcribe(void* impl, const void* audio_data,
                                               size_t audio_size, const rac_stt_options_t* options,
                                               rac_stt_result_t* out_result) {
    if (!audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    // Minimum ~0.05s at 16kHz 16-bit to avoid Sherpa crash on empty/tiny input
    if (audio_size < 1600) {
        out_result->text = nullptr;
        out_result->confidence = 0.0f;
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
    (void)options;

    rac_handle_t stream = nullptr;
    rac_result_t result = rac_stt_sherpa_create_stream(impl, &stream);
    if (result != RAC_SUCCESS) {
        return result;
    }

    std::vector<float> float_samples = convert_int16_to_float32(audio_data, audio_size);

    result = rac_stt_sherpa_feed_audio(impl, stream, float_samples.data(), float_samples.size());
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

// v3 Phase B3: Sherpa STT `create` adapter called by commons rac_stt_create()
// through rac_plugin_route. Replaces the legacy rac_service_provider_t factory.
static rac_result_t sherpa_stt_create_impl(const char* model_id,
                                         const char* /*config_json*/,
                                         void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "sherpa_stt_create_impl: model=%s",
                 model_id ? model_id : "(default)");
    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_stt_sherpa_create(model_id, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) return rc;
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

static rac_result_t sherpa_stt_vtable_get_languages(void* impl, char** out_json) {
    return rac_stt_sherpa_get_languages(impl, out_json);
}

static rac_result_t sherpa_stt_vtable_detect_language(void* impl, const void* audio_data,
                                                    size_t audio_size,
                                                    const rac_stt_options_t* options,
                                                    char** out_language) {
    return rac_stt_sherpa_detect_language(impl, audio_data, audio_size, options, out_language);
}

}  // namespace (close anon — ops struct must have external linkage)

// Keep external C linkage so rac_plugin_entry_sherpa.cpp can wire this ops table
// in both static and shared builds.
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
    rac_tts_sherpa_stop(impl);
    return RAC_SUCCESS;
}

static rac_result_t sherpa_tts_vtable_get_info(void* impl, rac_tts_info_t* out_info) {
    (void)impl;
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;

    return RAC_SUCCESS;
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

// v3 Phase B3: Sherpa TTS `create` adapter.
static rac_result_t sherpa_tts_create_impl(const char* model_id,
                                         const char* /*config_json*/,
                                         void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "sherpa_tts_create_impl: model=%s",
                 model_id ? model_id : "(default)");
    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_tts_sherpa_create(model_id, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS) return rc;
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

static rac_result_t sherpa_tts_vtable_get_languages(void* impl, char** out_json) {
    return rac_tts_sherpa_get_languages(impl, out_json);
}

}  // namespace (close anon — see B3 note above)

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

// v3 Phase B3: Sherpa VAD `initialize` — Silero-style VAD models require
// per-instance model loading. When the backend's rac_vad_sherpa_create
// already accepts model_path (it does), initialize here is a no-op
// success. Kept explicitly to honor the new ABI.
static rac_result_t sherpa_vad_vtable_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}

// v3 Phase B3: Sherpa VAD `create` adapter.
static rac_result_t sherpa_vad_create_impl(const char* model_id,
                                         const char* /*config_json*/,
                                         void** out_impl) {
    if (!out_impl) return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    RAC_LOG_INFO(LOG_CAT, "sherpa_vad_create_impl: model=%s",
                 model_id ? model_id : "(default)");
    rac_handle_t backend_handle = nullptr;
    rac_result_t rc = rac_vad_sherpa_create(model_id, nullptr, &backend_handle);
    if (rc != RAC_SUCCESS || !backend_handle) {
        RAC_LOG_ERROR(LOG_CAT, "rac_vad_sherpa_create failed: %d", rc);
        return (rc == RAC_SUCCESS) ? RAC_ERROR_UNKNOWN : rc;
    }
    *out_impl = backend_handle;
    return RAC_SUCCESS;
}

}  // namespace (close anon — see B3 note above)

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

