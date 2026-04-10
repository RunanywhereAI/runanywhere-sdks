/**
 * @file rac_stt_sarvam.h
 * @brief Sarvam AI Backend - Cloud STT API
 *
 * Provides speech-to-text via Sarvam AI's Saarika model.
 * Uses the platform HTTP executor for network requests.
 */

#ifndef RAC_STT_SARVAM_H
#define RAC_STT_SARVAM_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(RAC_SARVAM_BUILDING)
#if defined(_WIN32)
#define RAC_SARVAM_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_SARVAM_API __attribute__((visibility("default")))
#else
#define RAC_SARVAM_API
#endif
#else
#define RAC_SARVAM_API
#endif

/**
 * Sarvam STT model variants.
 */
typedef enum rac_stt_sarvam_model {
    RAC_STT_SARVAM_MODEL_SAARIKA_V2 = 0,
    RAC_STT_SARVAM_MODEL_SAARIKA_V1 = 1,
} rac_stt_sarvam_model_t;

/**
 * Sarvam STT configuration.
 */
typedef struct rac_stt_sarvam_config {
    rac_stt_sarvam_model_t model;
    const char* language_code;
    rac_bool_t with_timestamps;
    rac_bool_t with_diarization;
    int32_t timeout_ms;
} rac_stt_sarvam_config_t;

static const rac_stt_sarvam_config_t RAC_STT_SARVAM_CONFIG_DEFAULT = {
    .model = RAC_STT_SARVAM_MODEL_SAARIKA_V2,
    .language_code = "en-IN",
    .with_timestamps = RAC_FALSE,
    .with_diarization = RAC_FALSE,
    .timeout_ms = 30000,
};

/**
 * Set the API key for Sarvam AI. Must be called before creating a service.
 */
RAC_SARVAM_API rac_result_t rac_stt_sarvam_set_api_key(const char* api_key);

/**
 * Get the currently configured API key. Returns NULL if not set.
 */
RAC_SARVAM_API const char* rac_stt_sarvam_get_api_key(void);

/**
 * Create a Sarvam STT service instance.
 */
RAC_SARVAM_API rac_result_t rac_stt_sarvam_create(const rac_stt_sarvam_config_t* config,
                                                   rac_handle_t* out_handle);

/**
 * Transcribe audio using Sarvam API.
 * Audio must be PCM Int16, 16kHz, mono. Converted to WAV internally.
 */
RAC_SARVAM_API rac_result_t rac_stt_sarvam_transcribe(rac_handle_t handle,
                                                       const void* audio_data, size_t audio_size,
                                                       const rac_stt_options_t* options,
                                                       rac_stt_result_t* out_result);

/**
 * Destroy a Sarvam STT service instance.
 */
RAC_SARVAM_API void rac_stt_sarvam_destroy(rac_handle_t handle);

/**
 * Register the Sarvam backend with the service registry.
 */
RAC_SARVAM_API rac_result_t rac_backend_sarvam_register(void);

/**
 * Unregister the Sarvam backend.
 */
RAC_SARVAM_API rac_result_t rac_backend_sarvam_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_SARVAM_H */
