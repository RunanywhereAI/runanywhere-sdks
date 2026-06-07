/**
 * @file rac_core.cpp
 * @brief RunAnywhere Commons - Core Initialization
 *
 * Migrated from Swift SDK initialization patterns.
 */

#include "rac/core/rac_core.h"

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#if !defined(RAC_PLATFORM_ANDROID)
#include "rac/features/diffusion/rac_diffusion_model_registry.h"
#endif

// =============================================================================
// STATIC STATE
// =============================================================================

static std::atomic<bool> s_initialized{false};
static std::mutex s_init_mutex;
// Atomic so concurrent rac_get_platform_adapter() / rac_log() / convenience
// helpers do not race with rac_init / rac_shutdown / rac_set_platform_adapter.
// Readers snapshot the pointer into a local before dereferencing any field,
// so a concurrent shutdown that stores nullptr cannot produce a torn or
// use-after-free read on the adapter struct itself (which is owned by the
// platform SDK and must outlive any in-flight call by contract).
static std::atomic<const rac_platform_adapter_t*> s_platform_adapter{nullptr};
static std::atomic<rac_log_level_t> s_log_level{RAC_LOG_INFO};
static std::mutex s_log_tag_mutex;
static std::string s_log_tag = "RAC";

// Global model registry
static rac_model_registry_handle_t s_model_registry = nullptr;
static std::mutex s_model_registry_mutex;

// Global LoRA registry
static rac_lora_registry_handle_t s_lora_registry = nullptr;
static std::mutex s_lora_registry_mutex;

// Version info — single source of truth is sdk/runanywhere-commons/VERSION,
// injected at configure time as the RAC_VERSION_STRING compile define by
// CMakeLists.txt. The "0.0.0" literal is a compile-time fallback that only
// applies to a stray TU compiled without the define; real builds always carry
// the canonical VERSION so rac_get_version() never reports a placeholder.
#ifndef RAC_VERSION_STRING
#define RAC_VERSION_STRING "0.0.0"
#endif
static const char* s_version_string = RAC_VERSION_STRING;

// Parse "major.minor.patch[-suffix]" from the canonical version string once so
// the numeric fields stay in lockstep with the string instead of being a
// hand-maintained second copy that can drift (the prior 1.0.0/string mismatch).
static rac_version_t make_version(void) {
    rac_version_t v = {.major = 0, .minor = 0, .patch = 0, .string = s_version_string};
    unsigned int major = 0, minor = 0, patch = 0;
    if (std::sscanf(s_version_string, "%u.%u.%u", &major, &minor, &patch) == 3) {
        v.major = static_cast<uint16_t>(major);
        v.minor = static_cast<uint16_t>(minor);
        v.patch = static_cast<uint16_t>(patch);
    }
    return v;
}
static const rac_version_t s_version = make_version();

// =============================================================================
// INTERNAL LOGGING HELPER
// =============================================================================

static void internal_log(rac_log_level_t level, const char* message) {
    if (level < s_log_level.load(std::memory_order_acquire)) {
        return;
    }

    const rac_platform_adapter_t* adapter = s_platform_adapter.load(std::memory_order_acquire);
    if (adapter != nullptr && adapter->log != nullptr) {
        std::string tag;
        {
            std::lock_guard<std::mutex> lock(s_log_tag_mutex);
            tag = s_log_tag;
        }
        adapter->log(level, tag.c_str(), message, adapter->user_data);
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
    s_platform_adapter.store(adapter, std::memory_order_release);
    return RAC_SUCCESS;
}

const rac_platform_adapter_t* rac_get_platform_adapter(void) {
    return s_platform_adapter.load(std::memory_order_acquire);
}

void rac_log(rac_log_level_t level, const char* category, const char* message) {
    const rac_platform_adapter_t* adapter = s_platform_adapter.load(std::memory_order_acquire);
    if (adapter != nullptr && adapter->log != nullptr) {
        adapter->log(level, category, message, adapter->user_data);
    }
}

// =============================================================================
// INITIALIZATION API
// =============================================================================

rac_result_t rac_init(const rac_config_t* config) {
    std::lock_guard<std::mutex> lock(s_init_mutex);
    rac::events::publish_initialization_started();

    if (s_initialized.load()) {
        rac::events::publish_initialization_failed(RAC_ERROR_ALREADY_INITIALIZED,
                                                   "Commons already initialized");
        return RAC_ERROR_ALREADY_INITIALIZED;
    }

    if (config == nullptr) {
        rac::events::publish_initialization_failed(RAC_ERROR_NULL_POINTER, "Config is required");
        return RAC_ERROR_NULL_POINTER;
    }

    const rac_platform_adapter_t* adapter = config->platform_adapter;
    if (adapter == nullptr) {
        rac_error_set_details("Platform adapter is required for initialization");
        rac::events::publish_initialization_failed(RAC_ERROR_ADAPTER_NOT_SET,
                                                   "Platform adapter is required");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    // ABI guard: reject a populator built against a different struct layout.
    if (adapter->abi_version != RAC_PLATFORM_ADAPTER_ABI_VERSION) {
        char msg[160];
        std::snprintf(msg, sizeof(msg),
                      "Platform adapter ABI version mismatch: got %u, expected %u",
                      adapter->abi_version, RAC_PLATFORM_ADAPTER_ABI_VERSION);
        rac_error_set_details(msg);
        rac::events::publish_initialization_failed(RAC_ERROR_ABI_VERSION_MISMATCH, msg);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }
    if (adapter->struct_size != sizeof(rac_platform_adapter_t)) {
        char msg[160];
        std::snprintf(msg, sizeof(msg),
                      "Platform adapter struct_size mismatch: got %u, expected %zu",
                      adapter->struct_size, sizeof(rac_platform_adapter_t));
        rac_error_set_details(msg);
        rac::events::publish_initialization_failed(RAC_ERROR_ABI_VERSION_MISMATCH, msg);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    // Mandatory slots — fail-fast so a misconfigured adapter is caught here
    // rather than silently degrading deep in a worker thread.
    struct {
        const char* name;
        const void* fn;
    } mandatory[] = {
        {"file_exists", reinterpret_cast<const void*>(adapter->file_exists)},
        {"file_read", reinterpret_cast<const void*>(adapter->file_read)},
        {"file_write", reinterpret_cast<const void*>(adapter->file_write)},
        {"file_delete", reinterpret_cast<const void*>(adapter->file_delete)},
        {"secure_get", reinterpret_cast<const void*>(adapter->secure_get)},
        {"secure_set", reinterpret_cast<const void*>(adapter->secure_set)},
        {"secure_delete", reinterpret_cast<const void*>(adapter->secure_delete)},
        {"log", reinterpret_cast<const void*>(adapter->log)},
        {"now_ms", reinterpret_cast<const void*>(adapter->now_ms)},
    };
    for (const auto& slot : mandatory) {
        if (slot.fn == nullptr) {
            char msg[160];
            std::snprintf(msg, sizeof(msg), "Platform adapter missing mandatory slot: %s",
                          slot.name);
            rac_error_set_details(msg);
            rac::events::publish_initialization_failed(RAC_ERROR_ADAPTER_NOT_SET, msg);
            return RAC_ERROR_ADAPTER_NOT_SET;
        }
    }

    // Store configuration. Release-stores so concurrent acquire-loads from
    // worker threads (download orchestrator, voice agent, etc.) see a
    // fully published adapter struct before they observe the new pointer.
    {
        std::lock_guard<std::mutex> tag_lock(s_log_tag_mutex);
        if (config->log_tag != nullptr) {
            s_log_tag = config->log_tag;
        }
    }
    s_log_level.store(config->log_level, std::memory_order_release);
    s_platform_adapter.store(config->platform_adapter, std::memory_order_release);

    s_initialized.store(true);

    // Optional discovery / capability slots — warn but proceed (graceful
    // degradation: registry rescan / is_downloaded / vendor-id / memory / HTTP
    // simply no-op or fall back when NULL). Run AFTER the adapter store above so
    // RAC_LOG_WARNING has a live `log` slot to route through.
    if (adapter->file_list_directory == nullptr) {
        RAC_LOG_WARNING("RAC.Core",
                        "Platform adapter slot file_list_directory is NULL; model registry "
                        "local rescan will be skipped");
    }
    if (adapter->is_non_empty_directory == nullptr) {
        RAC_LOG_WARNING("RAC.Core",
                        "Platform adapter slot is_non_empty_directory is NULL; directory "
                        "artifact is_downloaded falls back to file_list_directory");
    }
    if (adapter->get_vendor_id == nullptr) {
        RAC_LOG_WARNING("RAC.Core",
                        "Platform adapter slot get_vendor_id is NULL; device id will be "
                        "synthesized + persisted via secure_set");
    }
    if (adapter->get_memory_info == nullptr) {
        RAC_LOG_WARNING("RAC.Core", "Platform adapter slot get_memory_info is NULL");
    }
    if (adapter->http_download == nullptr) {
        RAC_LOG_WARNING("RAC.Core", "Platform adapter slot http_download is NULL");
    }

#if !defined(RAC_PLATFORM_ANDROID)
    // Initialize diffusion model registry (iOS/Apple only; extensible model definitions)
    rac_diffusion_model_registry_init();
#endif

    internal_log(RAC_LOG_INFO, "RunAnywhere Commons initialized");
    rac::events::publish_initialization_completed();

    return RAC_SUCCESS;
}

void rac_shutdown(void) {
    std::lock_guard<std::mutex> lock(s_init_mutex);

    if (!s_initialized.load()) {
        return;
    }

    internal_log(RAC_LOG_INFO, "RunAnywhere Commons shutting down");
    rac::events::publish_shutdown();

#if !defined(RAC_PLATFORM_ANDROID)
    // Cleanup diffusion model registry (iOS/Apple only)
    rac_diffusion_model_registry_cleanup();
#endif

    // Clear state. Release-store so a concurrent acquire-load on a worker
    // thread observes nullptr (and bails) before this function returns and
    // the platform SDK proceeds to free the adapter struct.
    s_platform_adapter.store(nullptr, std::memory_order_release);
    s_log_level.store(RAC_LOG_INFO, std::memory_order_release);
    {
        std::lock_guard<std::mutex> tag_lock(s_log_tag_mutex);
        s_log_tag = "RAC";
    }
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

const char* rac_sdk_get_version(void) {
    return s_version_string;
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
    if (url == nullptr || destination_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    const rac_platform_adapter_t* adapter = s_platform_adapter.load(std::memory_order_acquire);
    if (adapter == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    if (adapter->http_download == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return adapter->http_download(url, destination_path, progress_callback, complete_callback,
                                  callback_user_data, out_task_id, adapter->user_data);
}

rac_result_t rac_http_download_cancel(const char* task_id) {
    if (task_id == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    const rac_platform_adapter_t* adapter = s_platform_adapter.load(std::memory_order_acquire);
    if (adapter == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    if (adapter->http_download_cancel == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return adapter->http_download_cancel(task_id, adapter->user_data);
}

// =============================================================================
// ARCHIVE EXTRACTION CONVENIENCE FUNCTION
// =============================================================================

#include "rac/infrastructure/extraction/rac_extraction.h"

rac_result_t rac_extract_archive(const char* archive_path, const char* destination_dir,
                                 rac_extract_progress_callback_fn progress_callback,
                                 void* callback_user_data) {
    if (archive_path == nullptr || destination_dir == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Bridge the old callback signature to the new one
    struct bridge_ctx {
        rac_extract_progress_callback_fn callback;
        void* user_data;
    };
    bridge_ctx ctx = {.callback = progress_callback, .user_data = callback_user_data};

    rac_extraction_progress_fn bridged_callback = nullptr;
    void* bridged_user_data = nullptr;
    if (progress_callback) {
        bridged_callback = [](int32_t files_extracted, int32_t total_files,
                              int64_t /* bytes_extracted */, void* ud) {
            auto* c = static_cast<bridge_ctx*>(ud);
            if (c->callback) {
                c->callback(files_extracted, total_files, c->user_data);
            }
        };
        bridged_user_data = &ctx;
    }

    // Use native libarchive extraction
    return rac_extract_archive_native(archive_path, destination_dir, nullptr /* default options */,
                                      bridged_callback, bridged_user_data,
                                      nullptr /* no result output */);
}

// =============================================================================
// GLOBAL MODEL REGISTRY
// =============================================================================

// Persistence contract: the global model registry is IN-MEMORY ONLY. It is
// not written to disk by commons and does not survive a process restart.
// Every SDK is responsible for re-seeding the registry on every cold start
// via one of:
//   (a) re-calling rac_register_model() for any locally-defined catalog
//       entries that are not produced by remote model-assignment fetch
//       (Web example app's registerModelCatalog() is the canonical example);
//   (b) calling the remote model-assignment fetch (Swift / Kotlin / Flutter
//       / RN — repopulates via the backend API);
//   (c) discoverDownloadedModels() to relink already-downloaded folders to
//       registered entries (self-heal — Swift RunAnywhere.swift:308-313).
// Entries that exist only via (a) without (b) or (c) DISAPPEAR after restart
// and must be re-registered.
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

rac_result_t rac_get_model_by_path(const char* local_path, rac_model_info_t** out_model) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return rac_model_registry_get_by_path(registry, local_path, out_model);
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

// =============================================================================
// GLOBAL LORA REGISTRY
// =============================================================================

rac_lora_registry_handle_t rac_get_lora_registry(void) {
    std::lock_guard<std::mutex> lock(s_lora_registry_mutex);
    if (s_lora_registry == nullptr) {
        rac_result_t result = rac_lora_registry_create(&s_lora_registry);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("RAC.Core", "Failed to create global LoRA registry");
            return nullptr;
        }
        RAC_LOG_INFO("RAC.Core", "Global LoRA registry created");
    }
    return s_lora_registry;
}

rac_result_t rac_register_lora(const rac_lora_entry_t* entry) {
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (registry == nullptr)
        return RAC_ERROR_NOT_INITIALIZED;
    return rac_lora_registry_register(registry, entry);
}

rac_result_t rac_get_lora_for_model(const char* model_id, rac_lora_entry_t*** out_entries,
                                    size_t* out_count) {
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (registry == nullptr)
        return RAC_ERROR_NOT_INITIALIZED;
    return rac_lora_registry_get_for_model(registry, model_id, out_entries, out_count);
}

}  // extern "C"
