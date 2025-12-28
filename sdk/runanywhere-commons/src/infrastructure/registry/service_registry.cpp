/**
 * @file service_registry.cpp
 * @brief RunAnywhere Commons - Service Registry Implementation
 *
 * C++ port of Swift's ServiceRegistry.swift
 * Provides:
 * - Service provider registration with priority
 * - canHandle-style service creation (matches Swift pattern)
 * - Priority-based provider selection
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

// Provider entry - mirrors Swift's ServiceRegistration
struct ProviderEntry {
    std::string name;
    rac_capability_t capability;
    int32_t priority;
    rac_service_can_handle_fn can_handle;
    rac_service_create_fn create;
    void* user_data;
};

std::mutex g_registry_mutex;

// Providers grouped by capability
std::unordered_map<rac_capability_t, std::vector<ProviderEntry>> g_providers;

}  // namespace

// =============================================================================
// SERVICE REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_service_register_provider(const rac_service_provider_t* provider) {
    if (provider == nullptr || provider->name == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    if (provider->can_handle == nullptr || provider->create == nullptr) {
        rac_error_set_details("can_handle and create functions are required");
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    ProviderEntry entry;
    entry.name = provider->name;
    entry.capability = provider->capability;
    entry.priority = provider->priority;
    entry.can_handle = provider->can_handle;
    entry.create = provider->create;
    entry.user_data = provider->user_data;

    g_providers[provider->capability].push_back(std::move(entry));

    // Sort by priority (higher first) - matches Swift's sorted(by: { $0.priority > $1.priority })
    auto& providers = g_providers[provider->capability];
    std::sort(
        providers.begin(), providers.end(),
        [](const ProviderEntry& a, const ProviderEntry& b) { return a.priority > b.priority; });

    rac_log(RAC_LOG_INFO, "ServiceRegistry",
            ("Registered provider: " + entry.name + " for capability " +
             std::to_string(static_cast<int>(provider->capability)))
                .c_str());

    return RAC_SUCCESS;
}

rac_result_t rac_service_unregister_provider(const char* name, rac_capability_t capability) {
    if (name == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    auto it = g_providers.find(capability);
    if (it == g_providers.end()) {
        return RAC_ERROR_PROVIDER_NOT_FOUND;
    }

    auto& providers = it->second;
    auto remove_it =
        std::remove_if(providers.begin(), providers.end(),
                       [name](const ProviderEntry& entry) { return entry.name == name; });

    if (remove_it == providers.end()) {
        return RAC_ERROR_PROVIDER_NOT_FOUND;
    }

    providers.erase(remove_it, providers.end());

    if (providers.empty()) {
        g_providers.erase(it);
    }

    return RAC_SUCCESS;
}

rac_result_t rac_service_create(rac_capability_t capability, const rac_service_request_t* request,
                                rac_handle_t* out_handle) {
    if (request == nullptr || out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    auto it = g_providers.find(capability);
    if (it == g_providers.end() || it->second.empty()) {
        rac_error_set_details("No providers registered for capability");
        return RAC_ERROR_NO_CAPABLE_PROVIDER;
    }

    // Find first provider that can handle the request (already sorted by priority)
    // This matches Swift's pattern: registrations.sorted(by:).first(where: canHandle)
    for (const auto& provider : it->second) {
        if (provider.can_handle(request, provider.user_data)) {
            rac_handle_t handle = provider.create(request, provider.user_data);
            if (handle != nullptr) {
                *out_handle = handle;
                rac_log(RAC_LOG_DEBUG, "ServiceRegistry",
                        ("Service created by provider: " + provider.name).c_str());
                return RAC_SUCCESS;
            }
        }
    }

    rac_error_set_details("No provider could handle the request");
    return RAC_ERROR_NO_CAPABLE_PROVIDER;
}

rac_result_t rac_service_list_providers(rac_capability_t capability, const char*** out_names,
                                        size_t* out_count) {
    if (out_names == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::lock_guard<std::mutex> lock(g_registry_mutex);

    // Static storage for names (valid until next call)
    static std::vector<const char*> s_name_ptrs;
    static std::vector<std::string> s_names;

    s_names.clear();
    s_name_ptrs.clear();

    auto it = g_providers.find(capability);
    if (it != g_providers.end()) {
        for (const auto& provider : it->second) {
            s_names.push_back(provider.name);
        }
    }

    s_name_ptrs.reserve(s_names.size());
    for (const auto& name : s_names) {
        s_name_ptrs.push_back(name.c_str());
    }

    *out_names = s_name_ptrs.data();
    *out_count = s_name_ptrs.size();

    return RAC_SUCCESS;
}

}  // extern "C"

// =============================================================================
// INTERNAL RESET (for testing)
// =============================================================================

namespace rac_internal {

void reset_service_registry() {
    std::lock_guard<std::mutex> lock(g_registry_mutex);
    g_providers.clear();
}

}  // namespace rac_internal
