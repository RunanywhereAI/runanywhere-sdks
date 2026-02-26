/**
 * @file rac_llm_llamacpp.h
 * @brief RunAnywhere Core - LlamaCPP Backend RAC API
 *
 * Direct RAC API export from runanywhere-core's LlamaCPP backend.
 * This header defines the public C API for LLM inference using llama.cpp.
 *
 * Mirrors Swift's LlamaCPPService implementation pattern.
 */

#ifndef RAC_LLM_LLAMACPP_H
#define RAC_LLM_LLAMACPP_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_LLAMACPP_BUILDING)
#if defined(_WIN32)
#define RAC_LLAMACPP_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_LLAMACPP_API __attribute__((visibility("default")))
#else
#define RAC_LLAMACPP_API
#endif
#else
#define RAC_LLAMACPP_API
#endif

// =============================================================================
// CONFIGURATION - Mirrors Swift's LlamaCPPGenerationConfig
// =============================================================================

/**
 * LlamaCPP-specific configuration.
 *
 * Mirrors Swift's LlamaCPPGenerationConfig.
 */
typedef struct rac_llm_llamacpp_config {
    /** Context size (0 = auto-detect from model) */
    int32_t context_size;

    /** Number of threads (0 = auto-detect) */
    int32_t num_threads;

    /** Number of layers to offload to GPU (Metal on iOS/macOS) */
    int32_t gpu_layers;

    /** Batch size for prompt processing */
    int32_t batch_size;
} rac_llm_llamacpp_config_t;

/**
 * Default LlamaCPP configuration.
 */
static const rac_llm_llamacpp_config_t RAC_LLM_LLAMACPP_CONFIG_DEFAULT = {
    .context_size = 0,  // Auto-detect
    .num_threads = 0,   // Auto-detect
    .gpu_layers = -1,   // All layers on GPU
    .batch_size = 512};

// =============================================================================
// LLAMACPP-SPECIFIC API
// =============================================================================

/**
 * Creates a LlamaCPP LLM service.
 *
 * Mirrors Swift's LlamaCPPService.initialize(modelPath:)
 *
 * @param model_path Path to the GGUF model file
 * @param config LlamaCPP-specific configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_create(const char* model_path,
                                                      const rac_llm_llamacpp_config_t* config,
                                                      rac_handle_t* out_handle);

/**
 * Loads a GGUF model into an existing service.
 *
 * Mirrors Swift's LlamaCPPService.loadModel(path:config:)
 *
 * @param handle Service handle
 * @param model_path Path to the GGUF model file
 * @param config LlamaCPP configuration (can be NULL)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_load_model(rac_handle_t handle,
                                                          const char* model_path,
                                                          const rac_llm_llamacpp_config_t* config);

/**
 * Unloads the current model.
 *
 * Mirrors Swift's LlamaCPPService.unloadModel()
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_unload_model(rac_handle_t handle);

/**
 * Checks if a model is loaded.
 *
 * Mirrors Swift's LlamaCPPService.isModelLoaded
 *
 * @param handle Service handle
 * @return RAC_TRUE if model is loaded, RAC_FALSE otherwise
 */
RAC_LLAMACPP_API rac_bool_t rac_llm_llamacpp_is_model_loaded(rac_handle_t handle);

/**
 * Generates text completion.
 *
 * Mirrors Swift's LlamaCPPService.generate(prompt:config:)
 *
 * @param handle Service handle
 * @param prompt Input prompt text
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result (caller must free text with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_generate(rac_handle_t handle, const char* prompt,
                                                        const rac_llm_options_t* options,
                                                        rac_llm_result_t* out_result);

/**
 * Streaming text generation callback.
 *
 * Mirrors Swift's streaming callback pattern.
 *
 * @param token Generated token string
 * @param is_final Whether this is the final token
 * @param user_data User-provided context
 * @return RAC_TRUE to continue, RAC_FALSE to stop
 */
typedef rac_bool_t (*rac_llm_llamacpp_stream_callback_fn)(const char* token, rac_bool_t is_final,
                                                          void* user_data);

/**
 * Generates text with streaming callback.
 *
 * Mirrors Swift's LlamaCPPService.generateStream(prompt:config:)
 *
 * @param handle Service handle
 * @param prompt Input prompt text
 * @param options Generation options
 * @param callback Callback for each token
 * @param user_data User context passed to callback
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_generate_stream(
    rac_handle_t handle, const char* prompt, const rac_llm_options_t* options,
    rac_llm_llamacpp_stream_callback_fn callback, void* user_data);

/**
 * Cancels ongoing generation.
 *
 * Mirrors Swift's LlamaCPPService.cancel()
 *
 * @param handle Service handle
 */
RAC_LLAMACPP_API void rac_llm_llamacpp_cancel(rac_handle_t handle);

/**
 * Gets model information as JSON.
 *
 * @param handle Service handle
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_get_model_info(rac_handle_t handle, char** out_json);

/**
 * Destroys a LlamaCPP LLM service.
 *
 * @param handle Service handle to destroy
 */
RAC_LLAMACPP_API void rac_llm_llamacpp_destroy(rac_handle_t handle);

// =============================================================================
// LORA ADAPTER API
// =============================================================================

/**
 * Load a LoRA adapter from a GGUF file and apply it.
 *
 * The adapter is loaded against the current model and applied to the context.
 * Context is recreated internally to accommodate the new adapter.
 * KV cache is cleared automatically.
 *
 * @param handle Service handle (from rac_llm_llamacpp_create)
 * @param adapter_path Path to the LoRA adapter GGUF file
 * @param scale Adapter scale factor (0.0-1.0, default 1.0)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_load_lora(rac_handle_t handle,
                                                          const char* adapter_path,
                                                          float scale);

/**
 * Remove a specific LoRA adapter by path.
 * KV cache is cleared automatically.
 *
 * @param handle Service handle
 * @param adapter_path Path used when loading the adapter
 * @return RAC_SUCCESS or RAC_ERROR_NOT_FOUND
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_remove_lora(rac_handle_t handle,
                                                            const char* adapter_path);

/**
 * Remove all LoRA adapters from the context.
 * KV cache is cleared automatically.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_clear_lora(rac_handle_t handle);

/**
 * Get info about loaded LoRA adapters as JSON.
 *
 * Returns JSON array: [{"path":"...", "scale":1.0, "applied":true}, ...]
 *
 * @param handle Service handle
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_get_lora_info(rac_handle_t handle,
                                                              char** out_json);

// =============================================================================
// ADAPTIVE CONTEXT API (for RAG pipelines)
// =============================================================================

/**
 * Inject a system prompt into the KV cache at position 0.
 * Clears existing KV cache first, then decodes the prompt tokens.
 *
 * @param handle Service handle (from rac_llm_llamacpp_create)
 * @param prompt System prompt text
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_inject_system_prompt(rac_handle_t handle,
                                                                     const char* prompt);

/**
 * Append text to the KV cache after current content.
 * Does not clear existing KV cache — adds at current position.
 *
 * @param handle Service handle
 * @param text Text to append
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_append_context(rac_handle_t handle,
                                                               const char* text);

/**
 * Probe confidence that accumulated context answers a query.
 * Non-destructive to KV cache — probe tokens are cleaned up.
 *
 * @param handle Service handle
 * @param context Context passage (can be empty if context is in KV cache)
 * @param query The user question
 * @param out_confidence Output: confidence in [0.0, 1.0]
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_probe_confidence(rac_handle_t handle,
                                                                 const char* context,
                                                                 const char* query,
                                                                 float* out_confidence);

/**
 * Generate response from accumulated KV cache state.
 * Unlike rac_llm_llamacpp_generate(), does NOT clear the KV cache first.
 *
 * @param handle Service handle
 * @param query Query/suffix to append before generation
 * @param options Generation options (can be NULL for defaults)
 * @param out_result Output: Generation result
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_generate_from_context(
    rac_handle_t handle, const char* query, const rac_llm_options_t* options,
    rac_llm_result_t* out_result);

/**
 * Clear all KV cache state.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_llm_llamacpp_clear_context(rac_handle_t handle);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the LlamaCPP backend with the commons module and service registries.
 *
 * Should be called once during SDK initialization.
 * This registers:
 * - Module: "llamacpp" with TEXT_GENERATION capability
 * - Service provider: LlamaCPP LLM provider
 *
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_backend_llamacpp_register(void);

/**
 * Unregisters the LlamaCPP backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_LLAMACPP_API rac_result_t rac_backend_llamacpp_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_LLAMACPP_H */
