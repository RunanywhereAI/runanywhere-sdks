/**
 * @file module_registry.cpp
 * @brief RunAnywhere Commons - Module Registry Implementation
 *
 * C++ port of Swift's ModuleRegistry.swift
 * Provides:
 * - Module registration with capabilities
 * - Module discovery and introspection
 * - Prevention of duplicate registration
 */

#include <algorithm>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_platform_adapter.h"

// =============================================================================
// INTERNAL STORAGE
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

std::mutex g_registry_mutex;
std::unordered_map<std::string, ModuleEntry> g_modules;

// Cached list for iteration (rebuilt on changes)
std::vector<rac_module_info_t> g_module_list_cache;
bool g_cache_dirty = true;

// Cached capability query results
std::vector<rac_module_info_t> g_capability_query_cache;

void rebuild_cache() {
    if (!g_cache_dirty) {
        return;
    }

    g_module_list_cache.clear();
    g_module_list_cache.reserve(g_modules.size());

    for (const auto& pair : g_modules) {
        g_module_list_cache.push_back(pair.second.to_c_info());
    }

    g_cache_dirty = false;
}

}  // namespace

// =============================================================================
// MODULE REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_module_register(const rac_module_info_t* info) {
    if (info == nullptr || info->id == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    std::string module_id = info->id;

    // Check for duplicate registration (matches Swift's behavior)
    if (g_modules.find(module_id) != g_modules.end()) {
        // Swift logs warning and skips, we return error for explicit handling
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

    g_modules[module_id] = std::move(entry);
    g_cache_dirty = true;

    rac_log(RAC_LOG_INFO, "ModuleRegistry", ("Module registered: " + module_id).c_str());

    return RAC_SUCCESS;
}

rac_result_t rac_module_unregister(const char* module_id) {
    if (module_id == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    auto it = g_modules.find(module_id);
    if (it == g_modules.end()) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    g_modules.erase(it);
    g_cache_dirty = true;

    rac_log(RAC_LOG_INFO, "ModuleRegistry",
            ("Module unregistered: " + std::string(module_id)).c_str());

    return RAC_SUCCESS;
}

rac_result_t rac_module_list(const rac_module_info_t** out_modules, size_t* out_count) {
    if (out_modules == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);
    rebuild_cache();

    *out_modules = g_module_list_cache.data();
    *out_count = g_module_list_cache.size();

    return RAC_SUCCESS;
}

rac_result_t rac_modules_for_capability(rac_capability_t capability,
                                        const rac_module_info_t** out_modules, size_t* out_count) {
    if (out_modules == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    // Rebuild capability query cache
    g_capability_query_cache.clear();

    for (const auto& pair : g_modules) {
        const auto& entry = pair.second;
        for (auto cap : entry.capabilities) {
            if (cap == capability) {
                g_capability_query_cache.push_back(entry.to_c_info());
                break;
            }
        }
    }

    *out_modules = g_capability_query_cache.data();
    *out_count = g_capability_query_cache.size();

    return RAC_SUCCESS;
}

rac_result_t rac_module_get_info(const char* module_id, const rac_module_info_t** out_info) {
    if (module_id == nullptr || out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);
    rebuild_cache();

    // Find in cache
    for (const auto& info : g_module_list_cache) {
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
    std::lock_guard<std::mutex> lock(g_registry_mutex);
    g_modules.clear();
    g_module_list_cache.clear();
    g_capability_query_cache.clear();
    g_cache_dirty = true;
}

}  // namespace rac_internal
