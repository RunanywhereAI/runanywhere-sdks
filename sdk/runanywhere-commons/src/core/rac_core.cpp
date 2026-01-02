/**
 * @file rac_core.cpp
 * @brief RunAnywhere Commons - Core Initialization
 *
 * Migrated from Swift SDK initialization patterns.
 */

#include "rac/core/rac_core.h"

#include <atomic>
#include <mutex>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

// =============================================================================
// STATIC STATE
// =============================================================================

static std::atomic<bool> s_initialized{false};
static std::mutex s_init_mutex;
static const rac_platform_adapter_t* s_platform_adapter = nullptr;
static rac_log_level_t s_log_level = RAC_LOG_INFO;
static std::string s_log_tag = "RAC";

// Global model registry
static rac_model_registry_handle_t s_model_registry = nullptr;
static std::mutex s_model_registry_mutex;

// Version info
static const char* s_version_string = "1.0.0";
static const rac_version_t s_version = {
    .major = 1, .minor = 0, .patch = 0, .string = s_version_string};

// =============================================================================
// INTERNAL LOGGING HELPER
// =============================================================================

static void internal_log(rac_log_level_t level, const char* message) {
    if (level < s_log_level) {
        return;
    }

    if (s_platform_adapter != nullptr && s_platform_adapter->log != nullptr) {
        s_platform_adapter->log(level, s_log_tag.c_str(), message, s_platform_adapter->user_data);
    }
}

// =============================================================================
// PLATFORM ADAPTER
// =============================================================================

extern "C" {

rac_result_t rac_set_platform_adapter(const rac_platform_adapter_t* adapter) {
    if (adapter == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    s_platform_adapter = adapter;
    return RAC_SUCCESS;
}

const rac_platform_adapter_t* rac_get_platform_adapter(void) {
    return s_platform_adapter;
}

void rac_log(rac_log_level_t level, const char* category, const char* message) {
    if (s_platform_adapter != nullptr && s_platform_adapter->log != nullptr) {
        s_platform_adapter->log(level, category, message, s_platform_adapter->user_data);
    }
}

// =============================================================================
// INITIALIZATION API
// =============================================================================

rac_result_t rac_init(const rac_config_t* config) {
    std::lock_guard<std::mutex> lock(s_init_mutex);

    if (s_initialized.load()) {
        return RAC_ERROR_ALREADY_INITIALIZED;
    }

    if (config == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (config->platform_adapter == nullptr) {
        rac_error_set_details("Platform adapter is required for initialization");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    // Store configuration
    s_platform_adapter = config->platform_adapter;
    s_log_level = config->log_level;
    if (config->log_tag != nullptr) {
        s_log_tag = config->log_tag;
    }

    s_initialized.store(true);

    internal_log(RAC_LOG_INFO, "RunAnywhere Commons initialized");

    return RAC_SUCCESS;
}

void rac_shutdown(void) {
    std::lock_guard<std::mutex> lock(s_init_mutex);

    if (!s_initialized.load()) {
        return;
    }

    internal_log(RAC_LOG_INFO, "RunAnywhere Commons shutting down");

    // Clear state
    s_platform_adapter = nullptr;
    s_log_level = RAC_LOG_INFO;
    s_log_tag = "RAC";
    s_initialized.store(false);
}

rac_bool_t rac_is_initialized(void) {
    // Force link device manager symbols by referencing the function
    // This ensures the device manager object file is included in the archive
    (void)&rac_device_manager_is_registered;

    return s_initialized.load() ? RAC_TRUE : RAC_FALSE;
}

rac_version_t rac_get_version(void) {
    return s_version;
}

rac_result_t rac_configure_logging(rac_environment_t environment) {
    switch (environment) {
        case RAC_ENV_DEVELOPMENT:
            // Debug mode: print to C++ stderr + send to Swift
            rac_logger_set_stderr_always(RAC_TRUE);
            rac_logger_set_min_level(RAC_LOG_DEBUG);
            RAC_LOG_INFO("RAC.Core", "Logging configured for development: stderr ON, level=DEBUG");
            break;

        case RAC_ENV_STAGING:
            // Staging: print to C++ stderr + send to Swift
            rac_logger_set_stderr_always(RAC_TRUE);
            rac_logger_set_min_level(RAC_LOG_INFO);
            RAC_LOG_INFO("RAC.Core", "Logging configured for staging: stderr ON, level=INFO");
            break;

        case RAC_ENV_PRODUCTION:
        default:
            // Production: NO C++ stderr, only send to Swift bridge
            // Swift handles local console and Sentry routing
            rac_logger_set_stderr_always(RAC_FALSE);
            rac_logger_set_min_level(RAC_LOG_WARNING);
            // Note: This log will only go to Swift, not stderr
            RAC_LOG_INFO("RAC.Core",
                         "Logging configured for production: stderr OFF, level=WARNING");
            break;
    }

    return RAC_SUCCESS;
}

// =============================================================================
// HTTP DOWNLOAD CONVENIENCE FUNCTIONS
// =============================================================================

rac_result_t rac_http_download(const char* url, const char* destination_path,
                               rac_http_progress_callback_fn progress_callback,
                               rac_http_complete_callback_fn complete_callback,
                               void* callback_user_data, char** out_task_id) {
    if (s_platform_adapter == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    if (s_platform_adapter->http_download == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return s_platform_adapter->http_download(url, destination_path, progress_callback,
                                             complete_callback, callback_user_data, out_task_id,
                                             s_platform_adapter->user_data);
}

rac_result_t rac_http_download_cancel(const char* task_id) {
    if (s_platform_adapter == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    if (s_platform_adapter->http_download_cancel == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return s_platform_adapter->http_download_cancel(task_id, s_platform_adapter->user_data);
}

// =============================================================================
// ARCHIVE EXTRACTION CONVENIENCE FUNCTION
// =============================================================================

rac_result_t rac_extract_archive(const char* archive_path, const char* destination_dir,
                                 rac_extract_progress_callback_fn progress_callback,
                                 void* callback_user_data) {
    if (s_platform_adapter == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    if (s_platform_adapter->extract_archive == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return s_platform_adapter->extract_archive(archive_path, destination_dir, progress_callback,
                                               callback_user_data, s_platform_adapter->user_data);
}

// =============================================================================
// GLOBAL MODEL REGISTRY
// =============================================================================

rac_model_registry_handle_t rac_get_model_registry(void) {
    std::lock_guard<std::mutex> lock(s_model_registry_mutex);

    if (s_model_registry == nullptr) {
        rac_result_t result = rac_model_registry_create(&s_model_registry);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("RAC.Core", "Failed to create global model registry");
            return nullptr;
        }
        RAC_LOG_INFO("RAC.Core", "Global model registry created");
    }

    return s_model_registry;
}

rac_result_t rac_register_model(const rac_model_info_t* model) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return rac_model_registry_save(registry, model);
}

rac_result_t rac_get_model(const char* model_id, rac_model_info_t** out_model) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return rac_model_registry_get(registry, model_id, out_model);
}

rac_bool_t rac_framework_is_platform_service(rac_inference_framework_t framework) {
    // Platform services are Swift-native implementations
    // that use service registry callbacks rather than C++ backends
    switch (framework) {
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return RAC_TRUE;
        default:
            return RAC_FALSE;
    }
}

}  // extern "C"
