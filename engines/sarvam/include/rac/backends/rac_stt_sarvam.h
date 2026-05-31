/**
 * @file rac_stt_sarvam.h
 * @brief RunAnywhere Sarvam STT backend — cloud speech-to-text via api.sarvam.ai.
 *
 * Sarvam exposes the Saarika multilingual STT family behind a multipart upload
 * endpoint. The caller passes file-encoded audio bytes (wav/mp3/flac/m4a/opus)
 * and a language_code; the backend returns a transcript and the detected
 * language.
 *
 * Wire shape (POST {base_url}/speech-to-text):
 *   header: api-subscription-key: <key>
 *   body:   multipart/form-data { file, model, language_code }
 *   resp:   {"request_id": ..., "transcript": ..., "language_code": ...}
 */

#ifndef RAC_STT_SARVAM_H
#define RAC_STT_SARVAM_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Ops vtable for the Sarvam STT backend.
 *
 * Exposed for callers that want to construct rac_stt_service_t themselves
 * or register the backend with a plugin registry. Most callers should use
 * rac_stt_sarvam_create() instead.
 */
extern const rac_stt_service_ops_t g_sarvam_stt_ops;

/**
 * @brief Create a fully-wrapped Sarvam STT service.
 *
 * Convenience factory: allocates impl + rac_stt_service_t and wires the
 * vtable. The returned service is owned by the caller and must be released
 * via rac_stt_sarvam_destroy().
 *
 * @param api_key      Sarvam API subscription key. Required.
 * @param model        Saarika model id (e.g. "saarika:v2.5"). Required.
 * @param out_service  Receives the heap-allocated service handle.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_stt_sarvam_create(const char*         api_key,
                                           const char*         model,
                                           rac_stt_service_t** out_service);

/**
 * @brief Same as rac_stt_sarvam_create() but accepts the full config JSON
 *        directly. Useful when extra knobs (language_code, base_url,
 *        timeout_ms) need overriding.
 *
 * Config JSON schema:
 *   {
 *     "api_key":       "...",                          // required
 *     "model":         "saarika:v2.5",                 // required
 *     "language_code": "en-IN",                        // optional, default "unknown" (auto-detect)
 *     "base_url":      "https://api.sarvam.ai",        // optional
 *     "timeout_ms":    30000                           // optional
 *   }
 */
RAC_API rac_result_t rac_stt_sarvam_create_from_json(const char*         config_json,
                                                     rac_stt_service_t** out_service);

/**
 * @brief Destroy a Sarvam STT service previously returned by either
 *        rac_stt_sarvam_create*() call. NULL-safe.
 */
RAC_API void rac_stt_sarvam_destroy(rac_stt_service_t* service);

#ifdef __cplusplus
}
#endif

#endif  // RAC_STT_SARVAM_H