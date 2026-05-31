/**
 * @file rac_llm_openrouter.h
 * @brief RunAnywhere OpenRouter backend — cloud LLM via OpenRouter.ai.
 *
 * Implements rac_llm_service_ops_t against OpenRouter's OpenAI-compatible
 * chat-completions endpoint. Used by the hybrid router as the online
 * candidate when the offline (e.g. llama.cpp) candidate is unavailable,
 * filtered out, or has cascaded.
 *
 * HTTP transport is routed through commons' rac_http_client_* ABI; the
 * actual network execution belongs to the platform-registered transport
 * adapter (OkHttp on Android, URLSession on Apple, ...).
 */

#ifndef RAC_LLM_OPENROUTER_H
#define RAC_LLM_OPENROUTER_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Ops vtable for the OpenRouter backend.
 *
 * Exposed for callers that want to construct rac_llm_service_t themselves
 * or register the backend with a plugin registry. Most callers should use
 * rac_llm_openrouter_create() instead.
 */
extern const rac_llm_service_ops_t g_openrouter_llm_ops;

/**
 * @brief Create a fully-wrapped OpenRouter LLM service.
 *
 * Convenience factory: allocates impl + rac_llm_service_t and wires the
 * vtable. The returned service is owned by the caller and must be released
 * via rac_llm_openrouter_destroy(). Suitable for direct registration with
 * rac_llm_hybrid_router_set_online_service().
 *
 * @param api_key      OpenRouter API key ("sk-or-..."). Required.
 * @param model        OpenRouter model id (e.g. "openai/gpt-4o-mini"). Required.
 * @param out_service  Receives the heap-allocated service handle.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_llm_openrouter_create(const char*         api_key,
                                               const char*         model,
                                               rac_llm_service_t** out_service);

/**
 * @brief Same as rac_llm_openrouter_create() but accepts the full config JSON
 *        directly. Useful when extra knobs (base_url, timeout_ms, http_referer,
 *        x_title) need overriding.
 *
 * Config JSON schema:
 *   {
 *     "api_key":      "sk-or-...",                            // required
 *     "model":        "openai/gpt-4o-mini",                   // required
 *     "base_url":     "https://openrouter.ai/api/v1",         // optional
 *     "timeout_ms":   30000,                                  // optional
 *     "http_referer": "https://runanywhere.ai",               // optional
 *     "x_title":      "RunAnywhere SDK"                       // optional
 *   }
 */
RAC_API rac_result_t rac_llm_openrouter_create_from_json(const char*         config_json,
                                                         rac_llm_service_t** out_service);

/**
 * @brief Destroy an OpenRouter service previously returned by either
 *        rac_llm_openrouter_create*() call. NULL-safe.
 */
RAC_API void rac_llm_openrouter_destroy(rac_llm_service_t* service);

#ifdef __cplusplus
}
#endif

#endif  // RAC_LLM_OPENROUTER_H
