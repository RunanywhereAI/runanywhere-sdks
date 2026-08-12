/**
 * @file rac_cloud_stt_provider.h
 * @brief Cross-SDK named host-callback table for developer-defined cloud STT
 *        providers.
 *
 * The `cloud` STT engine selects a provider at create() time via
 * config_json["provider"]. Built-in providers (e.g. "sarvam") are static C++
 * adapters compiled into the engine. THIS table is the escape hatch for the
 * other case: a provider the HOST defines at runtime. The binding (Kotlin,
 * Swift, …) registers a named transcribe callback here; when the engine sees a
 * provider name with no static adapter but a registered callback, it delegates
 * the ENTIRE request — build, HTTP, and response parse — to the host. That
 * lets a developer support any cloud STT vendor (api key, URL, request/response
 * shape) without a new native adapter or a recompile.
 *
 * This mirrors rac_hybrid_custom_filter's discipline exactly: an active table
 * lives behind a std::atomic; register/unregister publish a fresh immutable
 * snapshot and retire the previous one with a one-generation reprieve for
 * in-flight readers. The callback may be invoked concurrently from request
 * threads, so implementations must be reentrant.
 *
 * Lifecycle: the callback is invoked while the binding's user_data is alive.
 * Bindings MUST unregister (by name) before freeing the user_data backing the
 * callback — there is no native-side reference counting, and freeing it while a
 * call is in flight is undefined behavior.
 */

#ifndef RAC_CLOUD_STT_PROVIDER_H
#define RAC_CLOUD_STT_PROVIDER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Maximum length (including the NUL terminator) of a provider name.
 */
#define RAC_CLOUD_STT_PROVIDER_NAME_MAX 64

/**
 * @brief Host-supplied transcribe callback.
 *
 * Performs the complete cloud request for one utterance host-side: builds and
 * sends the HTTP request (e.g. via the platform's OkHttp transport) and decodes
 * the provider's response. The host owns the wire format end to end. Must be
 * thread-safe / reentrant — the engine may invoke it concurrently.
 *
 * @param config_json     The registered cloud entry as a JSON string (keys:
 *                        provider, api_key, model, base_url, language_code,
 *                        timeout_ms). Never NULL.
 * @param audio           Audio bytes for this utterance. May be NULL only when
 *                        @p audio_len is 0.
 * @param audio_len       Length of @p audio in bytes.
 * @param audio_format    rac_audio_format_enum_t value describing @p audio.
 * @param out_result_json On RAC_SUCCESS, receives a heap-allocated,
 *                        NUL-terminated result-JSON string OWNED BY THE CALLER
 *                        (free via rac_cloud_stt_result_free). Shape:
 *                          {"text": "...", "language_code": "...",
 *                           "confidence": <number|omitted>,
 *                           "error_code": 0, "error_message": ""}
 * @param user_data       Opaque binding-owned pointer supplied at registration.
 * @return RAC_SUCCESS when @p out_result_json was written; an error code
 *         otherwise (the engine treats a non-success as a transcribe failure).
 */
typedef rac_result_t (*rac_cloud_stt_transcribe_fn_t)(const char* config_json, const uint8_t* audio,
                                                      size_t audio_len, int32_t audio_format,
                                                      char** out_result_json, void* user_data);

/**
 * @brief Register (or replace) a named cloud STT provider callback.
 *
 * Re-registering an existing @p name atomically replaces that entry's callback
 * + user_data. Registration copies @p name into table-owned storage.
 *
 * @param name       NUL-terminated identifier (< RAC_CLOUD_STT_PROVIDER_NAME_MAX
 *                   including the terminator). Must be non-NULL and non-empty.
 * @param transcribe Callback to invoke. Must be non-NULL.
 * @param user_data  Opaque pointer passed back to @p transcribe. MAY be NULL.
 * @return RAC_SUCCESS;
 *         RAC_ERROR_INVALID_PARAMETER if @p name is NULL/empty/too long or
 *         @p transcribe is NULL;
 *         RAC_ERROR_OUT_OF_MEMORY if the new snapshot cannot be allocated.
 */
RAC_API rac_result_t rac_cloud_register_stt_provider(const char* name,
                                                     rac_cloud_stt_transcribe_fn_t transcribe,
                                                     void* user_data);

/**
 * @brief Remove a named cloud STT provider callback.
 *
 * No-op (still RAC_SUCCESS) when @p name is not registered.
 */
RAC_API rac_result_t rac_cloud_unregister_stt_provider(const char* name);

/**
 * @brief Whether a provider callback is registered under @p name.
 *
 * The engine consults this when a config_json["provider"] has no static adapter
 * to decide between the host-callback path and an "unknown provider" failure.
 */
RAC_API rac_bool_t rac_cloud_has_stt_provider(const char* name);

/**
 * @brief Resolve and invoke the registered callback for @p name.
 *
 * On RAC_SUCCESS, @p out_result_json is a heap string the caller frees with
 * rac_cloud_stt_result_free. Returns RAC_ERROR_NOT_FOUND when @p name is not
 * registered (the engine reports an unknown-provider configuration error).
 */
RAC_API rac_result_t rac_cloud_invoke_stt_provider(const char* name, const char* config_json,
                                                   const uint8_t* audio, size_t audio_len,
                                                   int32_t audio_format, char** out_result_json);

/**
 * @brief Free a result string produced by rac_cloud_invoke_stt_provider.
 *
 * Safe to call with NULL.
 */
RAC_API void rac_cloud_stt_result_free(char* result_json);

#ifdef __cplusplus
}
#endif

#endif  // RAC_CLOUD_STT_PROVIDER_H
