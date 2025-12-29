/**
 * @file module_registry.cpp
 * @brief RunAnywhere Commons - Module Registry Implementation
 *
 * C++ port of Swift's ModuleRegistry.swift
 * Provides:
 * - Module registration with capabilities
 * - Module discovery and introspection
 * - Prevention of duplicate registration
 *
 * Uses function-local statics to avoid static initialization order issues
 * when called from Swift.
 */

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"

// Category for logging
static const char* LOG_CAT = "ModuleRegistry";

// =============================================================================
// INTERNAL STORAGE - Using function-local statics for safe initialization
// =============================================================================

namespace {

// Deep-copy module info to avoid dangling pointers
struct ModuleEntry {
    std::string id;
    std::string name;
    std::string version;
    std::string description;
    std::vector<rac_capability_t> capabilities;

    // For C API return
    rac_module_info_t to_c_info() const {
        rac_module_info_t info = {};
        info.id = id.c_str();
        info.name = name.c_str();
        info.version = version.c_str();
        info.description = description.c_str();
        info.capabilities = capabilities.data();
        info.num_capabilities = capabilities.size();
        return info;
    }
};

/**
 * Module registry state using function-local static to ensure proper initialization.
 * This avoids the "static initialization order fiasco" when Swift calls
 * into C++ code before global statics are initialized.
 */
struct ModuleRegistryState {
    std::mutex mutex;
    std::unordered_map<std::string, ModuleEntry> modules;
    std::vector<rac_module_info_t> module_list_cache;
    std::vector<rac_module_info_t> capability_query_cache;
    bool cache_dirty = true;
};

/**
 * Get the module registry state singleton using Meyers' singleton pattern.
 * Function-local static guarantees thread-safe initialization on first use.
 * NOTE: No logging here - this is called during static initialization
 */
ModuleRegistryState& get_state() {
    static ModuleRegistryState state;
    return state;
}

void rebuild_cache(ModuleRegistryState& state) {
    if (!state.cache_dirty) {
        return;
    }

    state.module_list_cache.clear();
    state.module_list_cache.reserve(state.modules.size());

    for (const auto& pair : state.modules) {
        state.module_list_cache.push_back(pair.second.to_c_info());
    }

    state.cache_dirty = false;
}

}  // namespace

// =============================================================================
// MODULE REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_module_register(const rac_module_info_t* info) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_module_register() - ENTRY");

    if (info == nullptr || info->id == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_module_register() - NULL pointer error");
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Registering module: %s", info->id);

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    std::string module_id = info->id;

    // Check for duplicate registration (matches Swift's behavior)
    if (state.modules.find(module_id) != state.modules.end()) {
        RAC_LOG_WARNING(LOG_CAT, "Module already registered, skipping: %s", module_id.c_str());
        rac_error_set_details("Module already registered, skipping");
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Create deep copy
    ModuleEntry entry;
    entry.id = info->id;
    entry.name = info->name ? info->name : info->id;
    entry.version = info->version ? info->version : "";
    entry.description = info->description ? info->description : "";

    if (info->capabilities != nullptr && info->num_capabilities > 0) {
        entry.capabilities.assign(info->capabilities, info->capabilities + info->num_capabilities);
    }

    state.modules[module_id] = std::move(entry);
    state.cache_dirty = true;

    RAC_LOG_INFO(LOG_CAT, "Module registered: %s", module_id.c_str());
    return RAC_SUCCESS;
}

rac_result_t rac_module_unregister(const char* module_id) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_module_unregister() - id=%s", module_id ? module_id : "NULL");

    if (module_id == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    auto it = state.modules.find(module_id);
    if (it == state.modules.end()) {
        RAC_LOG_WARNING(LOG_CAT, "Module not found: %s", module_id);
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    state.modules.erase(it);
    state.cache_dirty = true;

    RAC_LOG_INFO(LOG_CAT, "Module unregistered: %s", module_id);
    return RAC_SUCCESS;
}

rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count) {
    if (out_modules == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    rebuild_cache(state);

    *out_modules = state.module_list_cache.data();
    *out_count = state.module_list_cache.size();

    return RAC_SUCCESS;
}

rac_result_t rac_modules_for_capability(rac_capability_t capability,
                                        const rac_module_info_t** out_modules, size_t* out_count) {
    if (out_modules == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    // Rebuild capability query cache
    state.capability_query_cache.clear();

    for (const auto& pair : state.modules) {
        const auto& entry = pair.second;
        for (auto cap : entry.capabilities) {
            if (cap == capability) {
                state.capability_query_cache.push_back(entry.to_c_info());
                break;
            }
        }
    }

    *out_modules = state.capability_query_cache.data();
    *out_count = state.capability_query_cache.size();

    return RAC_SUCCESS;
}

rac_result_t rac_module_get_info(const char* module_id, const rac_module_info_t** out_info) {
    if (module_id == nullptr || out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    rebuild_cache(state);

    // Find in cache
    for (const auto& info : state.module_list_cache) {
        if (strcmp(info.id, module_id) == 0) {
            *out_info = &info;
            return RAC_SUCCESS;
        }
    }

    return RAC_ERROR_MODULE_NOT_FOUND;
}

}  // extern "C"

// =============================================================================
// INTERNAL RESET (for testing)
// =============================================================================

namespace rac_internal {

void reset_module_registry() {
    RAC_LOG_DEBUG(LOG_CAT, "reset_module_registry()");
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    state.modules.clear();
    state.module_list_cache.clear();
    state.capability_query_cache.clear();
    state.cache_dirty = true;
}

}  // namespace rac_internal
