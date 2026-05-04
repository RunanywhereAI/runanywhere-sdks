/**
 * @file rac_speaker_diarization.h
 * @brief Speaker Diarization C ABI stubs (§8).
 *
 * The full diarization model is not yet integrated.  These stubs allow all
 * SDK frontends to call the functions without crashing; they return
 * RAC_ERROR_FEATURE_NOT_AVAILABLE so callers can surface a clear "not ready"
 * message rather than an UnsatisfiedLinkError / undefined-symbol crash.
 *
 * When the model is integrated, replace the stub implementations in
 * rac_speaker_diarization.cpp with the real ones.
 */

#ifndef RAC_SPEAKER_DIARIZATION_H
#define RAC_SPEAKER_DIARIZATION_H

#include <stddef.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle for a diarization session.
 */
typedef struct rac_speaker_diarization* rac_speaker_diarization_t;

/**
 * @brief Initialise a speaker diarization session.
 *
 * @param model_path   Path to the diarization model files.
 * @param out_handle   Output: session handle on success.
 * @return RAC_SUCCESS or RAC_ERROR_FEATURE_NOT_AVAILABLE (stub).
 */
RAC_API rac_result_t rac_speaker_diarization_init(const char* model_path,
                                                  rac_speaker_diarization_t** out_handle);

/**
 * @brief Process a chunk of audio samples.
 *
 * @param handle     Session handle from rac_speaker_diarization_init.
 * @param samples    PCM float samples.
 * @param count      Number of samples.
 * @param out_json   Output: JSON string with speaker segments (caller frees with rac_free).
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_speaker_diarization_process(rac_speaker_diarization_t* handle,
                                                     const float* samples, size_t count,
                                                     char** out_json);

/**
 * @brief Destroy a diarization session and free all resources.
 *
 * @param handle   Session handle (may be NULL — no-op).
 */
RAC_API void rac_speaker_diarization_destroy(rac_speaker_diarization_t* handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_SPEAKER_DIARIZATION_H */
