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
// SERVICE PROVIDER API - Mirrors Swift's ServiceRegistry
// =============================================================================

/**
 * Service request for creating services.
 * Passed to canHandle and create functions.
 *
 * Mirrors Swift's approach where canHandle receives a model/voice ID.
 */
typedef struct rac_service_request {
    /** Model or voice ID to check/create for (can be NULL for default) */
    const char* identifier;

    /** Configuration JSON string (can be NULL) */
    const char* config_json;

    /** The capability being requested */
    rac_capability_t capability;
} rac_service_request_t;

/**
 * canHandle function type.
 * Mirrors Swift's `canHandle: @Sendable (String?) -> Bool`
 *
 * @param request The service request
 * @param user_data Provider-specific context
 * @return RAC_TRUE if this provider can handle the request
 */
typedef rac_bool_t (*rac_service_can_handle_fn)(const rac_service_request_t* request,
                                                void* user_data);

/**
 * Service factory function type.
 * Mirrors Swift's factory closure.
 *
 * @param request The service request
 * @param user_data Provider-specific context
 * @return Handle to created service, or NULL on failure
 */
typedef rac_handle_t (*rac_service_create_fn)(const rac_service_request_t* request,
                                              void* user_data);

/**
 * Service provider registration.
 * Mirrors Swift's ServiceRegistration struct.
 */
typedef struct rac_service_provider {
    /** Provider name (e.g., "LlamaCPPService") */
    const char* name;

    /** Capability this provider offers */
    rac_capability_t capability;

    /** Priority (higher = preferred, default 100) */
    int32_t priority;

    /** Function to check if provider can handle request */
    rac_service_can_handle_fn can_handle;

    /** Function to create service instance */
    rac_service_create_fn create;

    /** User data passed to callbacks */
    void* user_data;
} rac_service_provider_t;

/**
 * Registers a service provider.
 *
 * Mirrors Swift's ServiceRegistry.registerSTT/LLM/TTS/VAD methods.
 * Providers are sorted by priority (higher first).
 *
 * @param provider Provider information (copied internally)
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_service_register_provider(const rac_service_provider_t* provider);

/**
 * Unregisters a service provider.
 *
 * @param name The name of the provider to unregister
 * @param capability The capability the provider was registered for
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_service_unregister_provider(const char* name, rac_capability_t capability);

/**
 * Creates a service for a specific capability.
 *
 * Mirrors Swift's createSTT/LLM/TTS/VAD methods.
 * Finds first provider that canHandle the request (sorted by priority).
 *
 * @param capability The capability needed
 * @param request The service request (can have identifier and config)
 * @param out_handle Pointer to receive the service handle
 * @return RAC_SUCCESS on success, or an error code on failure
 */
RAC_API rac_result_t rac_service_create(rac_capability_t capability,
                                        const rac_service_request_t* request,
                                        rac_handle_t* out_handle);

/**
 * Lists registered providers for a capability.
 *
 * @param capability The capability to list providers for
 * @param out_names Pointer to receive array of provider names
 * @param out_count Pointer to receive count
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_service_list_providers(rac_capability_t capability,
                                                const char*** out_names, size_t* out_count);

#ifdef __cplusplus
}
#endif

#endif /* RAC_CORE_H */
