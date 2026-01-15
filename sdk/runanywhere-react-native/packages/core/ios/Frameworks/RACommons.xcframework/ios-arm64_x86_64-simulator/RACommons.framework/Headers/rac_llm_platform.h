/**
 * @file rac_llm_platform.h
 * @brief RunAnywhere Commons - Platform LLM Backend (Apple Foundation Models)
 *
 * C API for platform-native LLM services. On Apple platforms, this uses
 * Foundation Models (Apple Intelligence). The actual implementation is in
 * Swift, with C++ providing the registration and callback infrastructure.
 *
 * This backend follows the same pattern as LlamaCPP and ONNX backends,
 * but delegates to Swift via function pointer callbacks since Foundation
 * Models is a Swift-only framework.
 */

#ifndef RAC_LLM_PLATFORM_H
#define RAC_LLM_PLATFORM_H

#include <RACommons/rac_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TYPES
// =============================================================================

/** Opaque handle to platform LLM service */
typedef struct rac_llm_platform* rac_llm_platform_handle_t;

/**
 * Platform LLM configuration.
 * Passed during initialization.
 */
typedef struct rac_llm_platform_config {
    /** Reserved for future use */
    void* reserved;
} rac_llm_platform_config_t;

/**
 * Generation options for platform LLM.
 */
typedef struct rac_llm_platform_options {
    /** Temperature for sampling (0.0 = deterministic, 1.0 = creative) */
    float temperature;
    /** Maximum tokens to generate */
    int32_t max_tokens;
    /** Reserved for future options */
    void* reserved;
} rac_llm_platform_options_t;

// =============================================================================
// SWIFT CALLBACK TYPES
// =============================================================================

/**
 * Callback to check if platform LLM can handle a model ID.
 * Implemented in Swift.
 *
 * @param model_id Model identifier to check (can be NULL)
 * @param user_data User-provided context
 * @return RAC_TRUE if this backend can handle the model
 */
typedef rac_bool_t (*rac_platform_llm_can_handle_fn)(const char* model_id, void* user_data);

/**
 * Callback to create platform LLM service.
 * Implemented in Swift.
 *
 * @param model_path Path to model (ignored for built-in)
 * @param config Configuration options
 * @param user_data User-provided context
 * @return Handle to created service (Swift object pointer), or NULL on failure
 */
typedef rac_handle_t (*rac_platform_llm_create_fn)(const char* model_path,
                                                   const rac_llm_platform_config_t* config,
                                                   void* user_data);

/**
 * Callback to generate text.
 * Implemented in Swift.
 *
 * @param handle Service handle from create
 * @param prompt Input prompt
 * @param options Generation options
 * @param out_response Output: Generated text (caller must free)
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
typedef rac_result_t (*rac_platform_llm_generate_fn)(rac_handle_t handle, const char* prompt,
                                                     const rac_llm_platform_options_t* options,
                                                     char** out_response, void* user_data);

/**
 * Callback to destroy platform LLM service.
 * Implemented in Swift.
 *
 * @param handle Service handle to destroy
 * @param user_data User-provided context
 */
typedef void (*rac_platform_llm_destroy_fn)(rac_handle_t handle, void* user_data);

/**
 * Swift callbacks for platform LLM operations.
 */
typedef struct rac_platform_llm_callbacks {
    rac_platform_llm_can_handle_fn can_handle;
    rac_platform_llm_create_fn create;
    rac_platform_llm_generate_fn generate;
    rac_platform_llm_destroy_fn destroy;
    void* user_data;
} rac_platform_llm_callbacks_t;

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

/**
 * Sets the Swift callbacks for platform LLM operations.
 * Must be called before using platform LLM services.
 *
 * @param callbacks Callback functions (copied internally)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_platform_llm_set_callbacks(const rac_platform_llm_callbacks_t* callbacks);

/**
 * Gets the current Swift callbacks.
 *
 * @return Pointer to callbacks, or NULL if not set
 */
RAC_API const rac_platform_llm_callbacks_t* rac_platform_llm_get_callbacks(void);

/**
 * Checks if Swift callbacks are registered.
 *
 * @return RAC_TRUE if callbacks are available
 */
RAC_API rac_bool_t rac_platform_llm_is_available(void);

// =============================================================================
// SERVICE API
// =============================================================================

/**
 * Creates a platform LLM service.
 *
 * @param model_path Path to model (ignored for built-in, can be NULL)
 * @param config Configuration options (can be NULL for defaults)
 * @param out_handle Output: Service handle
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_llm_platform_create(const char* model_path,
                                             const rac_llm_platform_config_t* config,
                                             rac_llm_platform_handle_t* out_handle);

/**
 * Destroys a platform LLM service.
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_llm_platform_destroy(rac_llm_platform_handle_t handle);

/**
 * Generates text using platform LLM.
 *
 * @param handle Service handle
 * @param prompt Input prompt
 * @param options Generation options (can be NULL for defaults)
 * @param out_response Output: Generated text (caller must free with free())
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_llm_platform_generate(rac_llm_platform_handle_t handle, const char* prompt,
                                               const rac_llm_platform_options_t* options,
                                               char** out_response);

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the Platform backend with the module and service registries.
 *
 * This registers:
 * - Module: "platform" with TEXT_GENERATION and TTS capabilities
 * - LLM Provider: "AppleFoundationModels" (priority 50)
 * - TTS Provider: "SystemTTS" (priority 10)
 * - Built-in model entries for Foundation Models and System TTS
 *
 * @return RAC_SUCCESS on success, or an error code
 */
RAC_API rac_result_t rac_backend_platform_register(void);

/**
 * Unregisters the Platform backend.
 *
 * @return RAC_SUCCESS on success, or an error code
 */
RAC_API rac_result_t rac_backend_platform_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_PLATFORM_H */
