/**
 * @file service_registry.cpp
 * @brief RunAnywhere Commons - Service Registry Implementation
 *
 * C++ port of Swift's ServiceRegistry.swift
 * Provides:
 * - Service provider registration with priority
 * - canHandle-style service creation (matches Swift pattern)
 * - Priority-based provider selection
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

#ifdef __ANDROID__
#include <android/log.h>
#define SR_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "ServiceRegistry", __VA_ARGS__)
#define SR_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "ServiceRegistry", __VA_ARGS__)
#else
#define SR_LOGI(...) printf("[ServiceRegistry] " __VA_ARGS__); printf("\n")
#define SR_LOGE(...) fprintf(stderr, "[ServiceRegistry ERROR] " __VA_ARGS__); fprintf(stderr, "\n")
#endif

// Category for logging
static const char* LOG_CAT = "ServiceRegistry";

// =============================================================================
// INTERNAL STORAGE - Using function-local statics for safe initialization
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

/**
 * Service registry state using function-local static to ensure proper initialization.
 * This avoids the "static initialization order fiasco" when Swift calls
 * into C++ code before global statics are initialized.
 */
struct ServiceRegistryState {
    std::mutex mutex;
    // Providers grouped by capability
    std::unordered_map<rac_capability_t, std::vector<ProviderEntry>> providers;
};

/**
 * Get the service registry state singleton using Meyers' singleton pattern.
 * Function-local static guarantees thread-safe initialization on first use.
 * NOTE: No logging here - this is called during static initialization
 */
ServiceRegistryState& get_state() {
    static ServiceRegistryState state;
    return state;
}

}  // namespace

// =============================================================================
// SERVICE REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_service_register_provider(const rac_service_provider_t* provider) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_service_register_provider() - ENTRY");

    if (provider == nullptr || provider->name == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "NULL pointer error");
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Registering provider: %s", provider->name);

    if (provider->can_handle == nullptr || provider->create == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "can_handle or create is NULL for provider: %s", provider->name);
        rac_error_set_details("can_handle and create functions are required");
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    ProviderEntry entry;
    entry.name = provider->name;
    entry.capability = provider->capability;
    entry.priority = provider->priority;
    entry.can_handle = provider->can_handle;
    entry.create = provider->create;
    entry.user_data = provider->user_data;

    state.providers[provider->capability].push_back(std::move(entry));

    // Sort by priority (higher first) - matches Swift's sorted(by: { $0.priority > $1.priority })
    auto& providers = state.providers[provider->capability];
    std::sort(
        providers.begin(), providers.end(),
        [](const ProviderEntry& a, const ProviderEntry& b) { return a.priority > b.priority; });

    RAC_LOG_INFO(LOG_CAT, "Registered provider: %s for capability %d", provider->name,
                 static_cast<int>(provider->capability));
    return RAC_SUCCESS;
}

rac_result_t rac_service_unregister_provider(const char* name, rac_capability_t capability) {
    RAC_LOG_DEBUG(LOG_CAT, "rac_service_unregister_provider() - name=%s", name ? name : "NULL");

    if (name == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    auto it = state.providers.find(capability);
    if (it == state.providers.end()) {
        RAC_LOG_WARNING(LOG_CAT, "Provider not found for capability %d",
                        static_cast<int>(capability));
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
        state.providers.erase(it);
    }

    RAC_LOG_INFO(LOG_CAT, "Provider unregistered: %s", name);
    return RAC_SUCCESS;
}

rac_result_t rac_service_create(rac_capability_t capability, const rac_service_request_t* request,
                                rac_handle_t* out_handle) {
    RAC_LOG_INFO(LOG_CAT, "rac_service_create called for capability=%d, identifier=%s",
                 static_cast<int>(capability),
                 request ? (request->identifier ? request->identifier : "(null)")
                         : "(null request)");

    if (request == nullptr || out_handle == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "rac_service_create: null pointer");
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    auto it = state.providers.find(capability);
    if (it == state.providers.end() || it->second.empty()) {
        SR_LOGE("No providers registered for capability %d", static_cast<int>(capability));
        RAC_LOG_ERROR(LOG_CAT, "rac_service_create: No providers registered for capability %d",
                      static_cast<int>(capability));
        rac_error_set_details("No providers registered for capability");
        return RAC_ERROR_NO_CAPABLE_PROVIDER;
    }

    SR_LOGI("Found %zu providers for capability %d", it->second.size(), static_cast<int>(capability));
    RAC_LOG_INFO(LOG_CAT, "rac_service_create: Found %zu providers for capability %d",
                 it->second.size(), static_cast<int>(capability));

    // Find first provider that can handle the request (already sorted by priority)
    // This matches Swift's pattern: registrations.sorted(by:).first(where: canHandle)
    for (const auto& provider : it->second) {
        SR_LOGI("Checking provider '%s' (priority=%d)", provider.name.c_str(), provider.priority);
        RAC_LOG_INFO(LOG_CAT, "rac_service_create: Checking provider '%s' (priority=%d)",
                     provider.name.c_str(), provider.priority);

        bool can_handle = provider.can_handle(request, provider.user_data);
        SR_LOGI("Provider '%s' can_handle=%s", provider.name.c_str(), can_handle ? "TRUE" : "FALSE");
        RAC_LOG_INFO(LOG_CAT, "rac_service_create: Provider '%s' can_handle=%s",
                     provider.name.c_str(), can_handle ? "TRUE" : "FALSE");

        if (can_handle) {
            RAC_LOG_INFO(LOG_CAT, "rac_service_create: Calling create for provider '%s'",
                         provider.name.c_str());
            rac_handle_t handle = provider.create(request, provider.user_data);
            if (handle != nullptr) {
                *out_handle = handle;
                RAC_LOG_INFO(LOG_CAT,
                             "rac_service_create: Service created by provider '%s', handle=%p",
                             provider.name.c_str(), handle);
                return RAC_SUCCESS;
            } else {
                RAC_LOG_ERROR(LOG_CAT, "rac_service_create: Provider '%s' create returned nullptr",
                              provider.name.c_str());
            }
        }
    }

    RAC_LOG_ERROR(LOG_CAT, "rac_service_create: No provider could handle the request");
    rac_error_set_details("No provider could handle the request");
    return RAC_ERROR_NO_CAPABLE_PROVIDER;
}

rac_result_t rac_service_list_providers(rac_capability_t capability, const char*** out_names,
                                        size_t* out_count) {
    if (out_names == nullptr || out_count == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    // Static storage for names (valid until next call)
    static std::vector<const char*> s_name_ptrs;
    static std::vector<std::string> s_names;

    s_names.clear();
    s_name_ptrs.clear();

    auto it = state.providers.find(capability);
    if (it != state.providers.end()) {
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
    RAC_LOG_DEBUG(LOG_CAT, "reset_service_registry()");
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    state.providers.clear();
}

}  // namespace rac_internal
