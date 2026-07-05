/**
 * @file rac_stt_cloud.h
 * @brief RunAnywhere generic cloud STT backend — HTTP speech-to-text providers.
 *
 * cloud_stt is ONE engine fronting multiple HTTP STT providers behind a shared
 * multipart/JSON core. The provider is selected at create() via the config
 * JSON's "provider" field (default "sarvam"); each provider supplies only its
 * endpoint path, auth header, request body shape, and response keys.
 *
 * Sarvam (the first provider) wire shape (POST {base_url}/speech-to-text):
 *   header: api-subscription-key: <key>
 *   body:   multipart/form-data { file, model, language_code }
 *   resp:   {"request_id": ..., "transcript": ..., "language_code": ...}
 */

#ifndef RAC_STT_CLOUD_H
#define RAC_STT_CLOUD_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Ops vtable for the generic cloud STT backend.
 *
 * Exposed for callers that want to construct rac_stt_service_t themselves
 * or register the backend with a plugin registry. Most callers should use
 * rac_stt_cloud_create() / rac_stt_cloud_create_from_json() instead.
 */
extern const rac_stt_service_ops_t g_cloud_stt_ops;

/**
 * @brief Create a fully-wrapped cloud STT service using the default provider.
 *
 * Convenience factory: allocates impl + rac_stt_service_t and wires the vtable.
 * With no provider specified the engine defaults to "sarvam", so this preserves
 * the original single-provider create() contract. The returned service is owned
 * by the caller and must be released via rac_stt_cloud_destroy().
 *
 * @param api_key      Provider API key. Required.
 * @param model        Provider model id (e.g. "saarika:v2.5"). Required.
 * @param out_service  Receives the heap-allocated service handle.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_stt_cloud_create(const char*         api_key,
                                          const char*         model,
                                          rac_stt_service_t** out_service);

/**
 * @brief Same as rac_stt_cloud_create() but accepts the full config JSON
 *        directly. Selects the provider and overrides connection knobs.
 *
 * Config JSON schema:
 *   {
 *     "provider":      "sarvam",                        // optional, default "sarvam"
 *     "api_key":       "...",                           // required
 *     "model":         "saarika:v2.5",                  // required
 *     "language_code": "en-IN",                         // optional, default "unknown" (auto-detect)
 *     "base_url":      "https://api.sarvam.ai",         // optional (provider default)
 *     "path":          "/speech-to-text",               // optional (provider default)
 *     "timeout_ms":    30000                            // optional
 *   }
 *
 * An unknown "provider" returns RAC_ERROR_INVALID_CONFIGURATION.
 */
RAC_API rac_result_t rac_stt_cloud_create_from_json(const char*         config_json,
                                                    rac_stt_service_t** out_service);

/**
 * @brief Destroy a cloud STT service previously returned by either
 *        rac_stt_cloud_create*() call. NULL-safe.
 */
RAC_API void rac_stt_cloud_destroy(rac_stt_service_t* service);

#ifdef __cplusplus
}
#endif

#endif  // RAC_STT_CLOUD_H
