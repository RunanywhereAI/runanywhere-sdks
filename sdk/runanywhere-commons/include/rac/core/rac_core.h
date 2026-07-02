/**
 * @file rac_core.h
 * @brief RunAnywhere Commons - Core Initialization and Module Management
 *
 * This header provides the core API for initializing and shutting down
 * the commons library, as well as module registration and discovery.
 */

#ifndef RAC_CORE_H
#define RAC_CORE_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/infrastructure/network/rac_environment.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

/** Platform adapter (see rac_platform_adapter.h) */
typedef struct rac_platform_adapter rac_platform_adapter_t;

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * Configuration for initializing the commons library.
 */
typedef struct rac_config {
    /** Platform adapter providing file, logging, and other platform callbacks */
    const rac_platform_adapter_t* platform_adapter;

    /** Log level for internal logging */
    rac_log_level_t log_level;

    /** Application-specific tag for logging */
    const char* log_tag;

    /** Reserved for future use (set to NULL) */
    void* reserved;
} rac_config_t;

// =============================================================================
// INITIALIZATION API
// =============================================================================

/**
 * Initializes the commons library.
 *
 * This must be called before any other RAC functions. The platform adapter
 * is required and provides callbacks for platform-specific operations.
 *
 * @param config Configuration options (platform_adapter is required)
 * @return RAC_SUCCESS on success, or an error code on failure
 *
 * @note HTTP requests return RAC_ERROR_NOT_SUPPORTED - networking should be
 *       handled by the SDK layer (Swift/Kotlin), not the C++ layer.
 */
RAC_API rac_result_t rac_init(const rac_config_t* config);

/**
 * Shuts down the commons library.
 *
 * This releases all resources and unregisters all modules. Any active
 * handles become invalid after this call.
 */
RAC_API void rac_shutdown(void);

/**
 * Checks if the commons library is initialized.
 *
 * @return RAC_TRUE if initialized, RAC_FALSE otherwise
 */
RAC_API rac_bool_t rac_is_initialized(void);

/**
 * Gets the version of the commons library.
 *
 * @return Version information structure
 */
RAC_API rac_version_t rac_get_version(void);

/**
 * Gets the canonical SDK version string.
 *
 * Returns the value of `sdk/runanywhere-commons/VERSION`, injected at build
 * time via the RAC_VERSION_STRING compile define. This is the single source of
 * truth every platform SDK delegates to for its public `version` constant
 * instead of hand-maintaining a copy that can drift.
 *
 * @return Static, NUL-terminated version string (e.g. "0.19.13"); never NULL,
 *         valid for the lifetime of the process. Do not free.
 */
RAC_API const char* rac_sdk_get_version(void);

/**
 * Sets the preferred number of CPU threads for on-device inference backends
 * (e.g. the ONNX Runtime thread pool used by Sherpa STT/TTS). Platform SDKs
 * call this once after init to size inference to the device — on Web, pass
 * `navigator.hardwareConcurrency`.
 *
 * @param num_threads Desired thread count. `<= 0` means "auto" (the backend
 *        picks `std::thread::hardware_concurrency()`). Backends clamp the value
 *        to what their build supports (e.g. the WASM pthread pool size).
 */
RAC_API void rac_set_inference_threads(int32_t num_threads);

/**
 * Returns the inference thread preference set via `rac_set_inference_threads`,
 * or 0 when unset (meaning "auto"). Inference backends call this when building
 * their session/model config.
 */
RAC_API int32_t rac_get_inference_threads(void);

/**
 * Configures logging based on the environment.
 *
 * This configures C++ local logging (stderr) based on the environment:
 * - Development: stderr ON, min level DEBUG
 * - Staging: stderr ON, min level INFO
 * - Production: stderr OFF, min level WARNING (logs only go to Swift bridge)
 *
 * Call this during SDK initialization after setting the platform adapter.
 *
 * @param environment The current SDK environment
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_configure_logging(rac_environment_t environment);

// =============================================================================
// NOTE: The legacy service-registry surface (rac_service_request_t,
// rac_service_provider_t, rac_service_can_handle_fn, rac_service_create_fn,
// rac_service_register_provider, rac_service_unregister_provider,
// rac_service_create, rac_service_list_providers, RAC_DEPRECATED_LEGACY_SVC)
// was REMOVED in v3.0.0 (RAC_PLUGIN_API_VERSION 3u).
//
// New code uses the unified plugin registry from rac/plugin/rac_plugin_entry.h
// (rac_plugin_register / rac_plugin_list / rac_plugin_find). Backend selection
// is simple priority order — the highest-priority registered plugin that serves
// the requested primitive wins; there is no hardware/format/accelerator scoring.
// =============================================================================

// =============================================================================
// GLOBAL MODEL REGISTRY API
// =============================================================================

/**
 * Gets the global model registry instance.
 * The registry is created automatically on first access.
 *
 * @return Handle to the global model registry
 */
RAC_API struct rac_model_registry* rac_get_model_registry(void);

/**
 * Registers a model with the global registry.
 * Convenience function that calls rac_model_registry_save on the global registry.
 *
 * @param model Model info to register
 * @return RAC_SUCCESS on success, or error code
 */
RAC_API rac_result_t rac_register_model(const struct rac_model_info* model);

/**
 * Gets model info from the global registry.
 * Convenience function that calls rac_model_registry_get on the global registry.
 *
 * @param model_id Model identifier
 * @param out_model Output: Model info (owned, must be freed with rac_model_info_free)
 * @return RAC_SUCCESS on success, RAC_ERROR_NOT_FOUND if not registered
 */
RAC_API rac_result_t rac_get_model(const char* model_id, struct rac_model_info** out_model);

/**
 * Gets model info from the global registry by local path.
 * Convenience function that calls rac_model_registry_get_by_path on the global registry.
 * Useful when loading models by path instead of model_id.
 *
 * @param local_path Local path to search for
 * @param out_model Output: Model info (owned, must be freed with rac_model_info_free)
 * @return RAC_SUCCESS on success, RAC_ERROR_NOT_FOUND if not registered
 */
RAC_API rac_result_t rac_get_model_by_path(const char* local_path,
                                           struct rac_model_info** out_model);

// =============================================================================
// GLOBAL LORA REGISTRY API
// =============================================================================

/**
 * @brief Get the global LoRA adapter registry singleton
 *
 * The registry is lazily created on first access and lives for the process lifetime.
 *
 * @return Handle to the global registry (never NULL after first successful call)
 */
RAC_API struct rac_lora_registry* rac_get_lora_registry(void);

/**
 * @brief Register a LoRA adapter in the global registry
 * @param entry Adapter entry to register (deep-copied internally)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_register_lora(const struct rac_lora_entry* entry);

/**
 * @brief Query the global registry for adapters compatible with a model
 * @param model_id Model ID to match
 * @param out_entries Output: array of matching entries (caller must free with
 * rac_lora_entry_array_free)
 * @param out_count Output: number of matching entries
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_get_lora_for_model(const char* model_id,
                                            struct rac_lora_entry*** out_entries,
                                            size_t* out_count);

#ifdef __cplusplus
}
#endif

#endif /* RAC_CORE_H */
