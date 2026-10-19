/**
 * @file rac_tool_provider_registry.cpp
 * @brief Tool-provider registry implementation, keyed by tool name.
 *
 * Deliberately independent of the engine and runtime registries, for the same
 * reason those two are independent of each other: a tool vtable change must not
 * invalidate engine plugins, so the ABI versions evolve separately.
 *
 * Providers are borrowed, never owned. `rac_tool_provider.h` requires the
 * struct to outlive registration, as engine vtables do, so this stores the
 * pointer and copies only the name it keys on.
 */

#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_tool_provider.h"

namespace {

constexpr const char* kTag = "ToolProviders";

struct Entry {
    std::string name;
    const rac_tool_provider_t* provider;
};

std::mutex& registry_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<Entry>& entries() {
    static std::vector<Entry> storage;
    return storage;
}

}  // namespace

extern "C" {

rac_result_t rac_tool_provider_register(const rac_tool_provider_t* provider) {
    if (provider == nullptr || provider->name == nullptr || provider->name[0] == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (provider->execute == nullptr || provider->parameters_json == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (provider->abi_version != RAC_TOOL_PROVIDER_ABI_VERSION) {
        // Dispatching into a provider built against another layout reads the
        // function pointers at the wrong offsets, so refuse rather than crash.
        RAC_LOG_ERROR(kTag, "tool provider '%s' has ABI version %u, expected %u",
                      provider->name, provider->abi_version, RAC_TOOL_PROVIDER_ABI_VERSION);
        return RAC_ERROR_ABI_VERSION_MISMATCH;
    }

    const std::lock_guard<std::mutex> guard(registry_mutex());
    auto& storage = entries();

    // Replace by name rather than reject. A binding overriding a commons tool
    // is a supported case, and making it unregister first would leave a window
    // with no tool of that name at all.
    for (auto& entry : storage) {
        if (entry.name == provider->name) {
            RAC_LOG_INFO(kTag, "replacing tool provider '%s'", provider->name);
            entry.provider = provider;
            return RAC_SUCCESS;
        }
    }

    storage.push_back(Entry{provider->name, provider});
    RAC_LOG_INFO(kTag, "registered tool provider '%s'", provider->name);
    return RAC_SUCCESS;
}

rac_result_t rac_tool_provider_unregister(const char* name) {
    if (name == nullptr || name[0] == '\0') {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::lock_guard<std::mutex> guard(registry_mutex());
    auto& storage = entries();
    for (auto it = storage.begin(); it != storage.end(); ++it) {
        if (it->name == name) {
            storage.erase(it);
            RAC_LOG_INFO(kTag, "unregistered tool provider '%s'", name);
            return RAC_SUCCESS;
        }
    }
    return RAC_ERROR_NOT_FOUND;
}

const rac_tool_provider_t* rac_tool_provider_find(const char* name) {
    if (name == nullptr || name[0] == '\0') {
        return nullptr;
    }

    const std::lock_guard<std::mutex> guard(registry_mutex());
    for (const auto& entry : entries()) {
        if (entry.name == name) {
            return entry.provider;
        }
    }
    return nullptr;
}

size_t rac_tool_provider_count(void) {
    const std::lock_guard<std::mutex> guard(registry_mutex());
    return entries().size();
}

const rac_tool_provider_t* rac_tool_provider_at(size_t index) {
    const std::lock_guard<std::mutex> guard(registry_mutex());
    const auto& storage = entries();
    if (index >= storage.size()) {
        return nullptr;
    }
    return storage[index].provider;
}

}  // extern "C"
