/**
 * @file rac_core.h
 * @brief RunAnywhere Commons - Core Initialization and Module Management
 *
 * This header provides the core API for initializing and shutting down
 * the commons library, as well as module registration and discovery.
 */

#ifndef RAC_CORE_H
#define RAC_CORE_H

#include "rac_error.h"
#include "rac_types.h"
#include "rac_model_types.h"
#include "rac_environment.h"

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
// MODULE INFORMATION
// =============================================================================

/**
 * Information about a registered module (backend).
 */
typedef struct rac_module_info {
    const char* id;          /**< Unique module identifier */
    const char* name;        /**< Human-readable name */
    const char* version;     /**< Module version string */
    const char* description; /**< Module description */

    /** Capabilities provided by this module */
    const rac_capability_t* capabilities;
    size_t num_capabilities;
} rac_module_info_t;

// =============================================================================
// MODULE REGISTRATION API
// =============================================================================

/**
 * Registers a module with the registry.
 *
 * Modules (backends) call this to register themselves with the commons layer.
 * This allows the SDK to discover available backends at runtime.
 *
 * @param info Module information (copied internally)
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_module_register(const rac_module_info_t* info);

/**
 * Unregisters a module from the registry.
 *
 * @param module_id The unique ID of the module to unregister
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_module_unregister(const char* module_id);

/**
 * Gets the list of registered modules.
 *
 * @param out_modules Pointer to receive the module list (do not free)
 * @param out_count Pointer to receive the number of modules
 * @return RAC_SUCCESS on success, or an error code on failure
 *
 * @note The returned list is valid until the next module registration/unregistration.
 */
RAC_API rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count);

/**
 * Gets modules that provide a specific capability.
 *
 * @param capability The capability to search for
 * @param out_modules Pointer to receive the module list (do not free)
 * @param out_count Pointer to receive the number of modules
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_modules_for_capability(rac_capability_t capability,
                                                const rac_module_info_t** out_modules,
                                                size_t* out_count);

/**
 * Gets information about a specific module.
 *
 * @param module_id The unique ID of the module
 * @param out_info Pointer to receive the module info (do not free)
 * @return RAC_SUCCESS on success, or RAC_ERROR_MODULE_NOT_FOUND if not found
 */
RAC_API rac_result_t rac_module_get_info(const char* module_id, const rac_module_info_t** out_info);

// =============================================================================
// v3.0.0 (C1): legacy service-registry surface REMOVED. Swift code that
// previously called rac_service_{register_provider,unregister_provider,
// create,list_providers} must use the unified plugin registry via the
// CRACommons headers rac_plugin_entry.h / rac_primitive.h / rac_route.h
// (added in v3 Phase B10). See CppBridge+Services.swift for the canonical
// migration.
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
 * Useful when loading models by path instead of model_id.
 *
 * @param local_path Local path to search for
 * @param out_model Output: Model info (owned, must be freed with rac_model_info_free)
 * @return RAC_SUCCESS on success, RAC_ERROR_NOT_FOUND if not registered
 */
RAC_API rac_result_t rac_get_model_by_path(const char* local_path, struct rac_model_info** out_model);

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
 * @param out_entries Output: array of matching entries (caller must free with rac_lora_entry_array_free)
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
