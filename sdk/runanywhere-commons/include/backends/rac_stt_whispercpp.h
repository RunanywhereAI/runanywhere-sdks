/**
 * @file rac_stt_whispercpp.h
 * @brief RunAnywhere Core - WhisperCPP Backend for STT
 *
 * RAC API for WhisperCPP-based speech-to-text.
 * Provides high-quality transcription using whisper.cpp.
 *
 * NOTE: WhisperCPP and LlamaCPP both use GGML, which can cause symbol
 * conflicts if linked together. Use ONNX Whisper for STT when also
 * using LlamaCPP for LLM, or build with symbol prefixing.
 */

#ifndef RAC_STT_WHISPERCPP_H
#define RAC_STT_WHISPERCPP_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_WHISPERCPP_BUILDING)
#if defined(_WIN32)
#define RAC_WHISPERCPP_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_WHISPERCPP_API __attribute__((visibility("default")))
#else
#define RAC_WHISPERCPP_API
#endif
#else
#define RAC_WHISPERCPP_API
#endif

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * WhisperCPP-specific configuration.
 */
typedef struct rac_stt_whispercpp_config {
    /** Number of threads (0 = auto) */
    int32_t num_threads;

    /** Enable GPU acceleration (Metal on Apple) */
    rac_bool_t use_gpu;

    /** Enable CoreML acceleration (Apple only) */
    rac_bool_t use_coreml;

    /** Language code for transcription (NULL = auto-detect) */
    const char* language;

    /** Translate to English (when source is non-English) */
    rac_bool_t translate;
} rac_stt_whispercpp_config_t;

/**
 * Default WhisperCPP configuration.
 */
static const rac_stt_whispercpp_config_t RAC_STT_WHISPERCPP_CONFIG_DEFAULT = {
    .num_threads = 0,
    .use_gpu = RAC_TRUE,
    .use_coreml = RAC_TRUE,
    .language = NULL,
    .translate = RAC_FALSE};

// =============================================================================
// WHISPERCPP STT API
// =============================================================================

/**
 * Creates a WhisperCPP STT service.
 *
 * @param model_path Path to the Whisper GGML model file (.bin)
 * @param config WhisperCPP-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_WHISPERCPP_API rac_result_t rac_stt_whispercpp_create(const char* model_path,
                                                          const rac_stt_whispercpp_config_t* config,
                                                          rac_handle_t* out_handle);

/**
 * Transcribes audio data.
 *
 * @param handle Service handle
 * @param audio_samples Float32 PCM samples (16kHz mono)
 * @param num_samples Number of samples
 * @param options STT options (can be NULL for defaults)
 * @param out_result Output: Transcription result
 * @return RAC_SUCCESS or error code
 */
RAC_WHISPERCPP_API rac_result_t rac_stt_whispercpp_transcribe(rac_handle_t handle,
                                                              const float* audio_samples,
                                                              size_t num_samples,
                                                              const rac_stt_options_t* options,
                                                              rac_stt_result_t* out_result);

/**
 * Gets detected language after transcription.
 *
 * @param handle Service handle
 * @param out_language Output: Language code (caller must free)
 * @return RAC_SUCCESS or error code
 */
RAC_WHISPERCPP_API rac_result_t rac_stt_whispercpp_get_language(rac_handle_t handle,
                                                                char** out_language);

/**
 * Checks if model is loaded and ready.
 *
 * @param handle Service handle
 * @return RAC_TRUE if ready
 */
RAC_WHISPERCPP_API rac_bool_t rac_stt_whispercpp_is_ready(rac_handle_t handle);

/**
 * Destroys a WhisperCPP STT service.
 *
 * @param handle Service handle to destroy
 */
RAC_WHISPERCPP_API void rac_stt_whispercpp_destroy(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the WhisperCPP backend with the commons module and service registries.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_WHISPERCPP_API rac_result_t rac_backend_whispercpp_register(void);

/**
 * Unregisters the WhisperCPP backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_WHISPERCPP_API rac_result_t rac_backend_whispercpp_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_WHISPERCPP_H */

