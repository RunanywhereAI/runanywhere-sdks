/**
 * @file rac_runtime_provider_registry.h
 * @brief Shared provider-registry helper for L1 runtime adapters.
 *
 * RT-CPU-03: promotes the provider-registration pattern, introduced by
 * `rac_cpu_runtime_register_provider`, into a runtime-agnostic helper that the
 * CPU adapter — and any future L1 adapter — can use without copying mutex /
 * vector / lookup boilerplate.
 *
 * Design:
 *   A provider's C-level struct type (e.g. `rac_cpu_runtime_provider_t`) is
 *   shaped around its native session, so adapters cannot literally share a
 *   single registry struct. Every provider type does, however, expose the same
 *   six fields the registry cares about — `name`, `primitive`, `formats`,
 *   `formats_count`, `create_session`, `destroy_session` — so the registry is
 *   implemented as a small header-only template keyed on the provider type:
 *
 *     rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> cpu_reg;
 *
 *   Each runtime keeps its typed provider surface; only the duplicated
 *   bookkeeping moves into the shared helper. There is no ABI change.
 *
 * Scope:
 *   - CPU uses this helper today.
 *   - Any future L1 adapter that grows a typed provider surface (matching the
 *     six fields above) wires in by instantiating the template on its own
 *     provider type.
 */

#ifndef RAC_RUNTIME_PROVIDER_REGISTRY_H
#define RAC_RUNTIME_PROVIDER_REGISTRY_H

#include <algorithm>
#include <cstring>
#include <mutex>
#include <new>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace rac {
namespace runtime {

/**
 * @brief Validates a primitive against the declared enum range.
 *
 * Used as a light sanity check at register time; actual dispatch is still gated
 * by the find-by-desc lookup so unsupported primitives fall through to
 * `RAC_ERROR_NOT_IMPLEMENTED`.
 */
inline bool rac_runtime_primitive_in_range(rac_primitive_t primitive) {
    return primitive > RAC_PRIMITIVE_UNSPECIFIED && primitive < RAC_PRIMITIVE_COUNT;
}

/**
 * @brief Header-only provider registry keyed by provider name.
 *
 * Thread-safe: every mutation / lookup takes an internal mutex. The registry
 * does NOT copy string or format-array storage — callers must keep the pointers
 * alive for the lifetime of the registration, matching the rest of the plugin
 * metadata ABI.
 *
 * Template requirements on `ProviderT` (`rac_cpu_runtime_provider_t`
 * satisfies these):
 *   - POD copyable
 *   - `const char* name` field
 *   - `rac_primitive_t primitive` field
 *   - `const uint32_t* formats` + `size_t formats_count` fields
 *   - `*create_session`, `*run_session`, `*destroy_session` function pointers
 */
template <typename ProviderT>
class ProviderRegistry {
   public:
    ProviderRegistry() = default;
    ProviderRegistry(const ProviderRegistry&) = delete;
    ProviderRegistry& operator=(const ProviderRegistry&) = delete;

    /**
     * @brief Add or replace a provider, keyed by `provider->name`.
     *
     * Required fields (`name`, `create_session`, `run_session`,
     * `destroy_session`) are validated before mutation. The `primitive` field
     * is range-checked against `RAC_PRIMITIVE_COUNT`.
     */
    rac_result_t register_provider(const ProviderT* provider) {
        if (provider == nullptr || provider->name == nullptr ||
            provider->create_session == nullptr || provider->run_session == nullptr ||
            provider->destroy_session == nullptr) {
            return RAC_ERROR_INVALID_PARAMETER;
        }
        if (!rac_runtime_primitive_in_range(provider->primitive)) {
            return RAC_ERROR_NOT_SUPPORTED;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        auto it = std::find_if(entries_.begin(), entries_.end(), [&](const auto& entry) {
            return entry.name != nullptr && std::strcmp(entry.name, provider->name) == 0;
        });
        try {
            if (it != entries_.end()) {
                *it = *provider;
            } else {
                entries_.push_back(*provider);
            }
        } catch (const std::bad_alloc&) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        return RAC_SUCCESS;
    }

    /** Unregister a provider by name. NULL or unknown name is a no-op. */
    void unregister_provider(const char* name) {
        if (name == nullptr)
            return;
        std::lock_guard<std::mutex> lock(mutex_);
        entries_.erase(std::remove_if(entries_.begin(), entries_.end(),
                                      [&](const auto& entry) {
                                          return entry.name != nullptr &&
                                                 std::strcmp(entry.name, name) == 0;
                                      }),
                       entries_.end());
    }

    /**
     * @brief Look up the first provider whose `(primitive, model_format)`
     * matches `desc`.
     *
     * `model_format == 0` in the descriptor, or a provider with `formats_count
     * == 0`, is treated as format-agnostic. Returns a by-value snapshot so the
     * caller does not need to hold the registry mutex during dispatch.
     */
    bool find_by_desc(const rac_runtime_session_desc_t* desc, ProviderT* out_provider) const {
        if (desc == nullptr || out_provider == nullptr)
            return false;
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& provider : entries_) {
            if (provider.primitive == desc->primitive &&
                provider_supports_format(provider, desc->model_format)) {
                *out_provider = provider;
                return true;
            }
        }
        return false;
    }

    /**
     * @brief Invoke `fn(provider)` on every registered entry while holding the
     * registry mutex. Used by capability snapshotting to deduplicate primitives
     * without exposing the internal list. `fn` MUST NOT call back into this
     * registry.
     */
    template <typename Fn>
    void for_each(Fn&& fn) const {
        std::lock_guard<std::mutex> lock(mutex_);
        for (const auto& provider : entries_) {
            fn(provider);
        }
    }

   private:
    static bool provider_supports_format(const ProviderT& provider, uint32_t model_format) {
        if (provider.formats == nullptr || provider.formats_count == 0 || model_format == 0) {
            return true;
        }
        for (size_t i = 0; i < provider.formats_count; ++i) {
            if (provider.formats[i] == model_format)
                return true;
        }
        return false;
    }

    mutable std::mutex mutex_;
    std::vector<ProviderT> entries_;
};

}  // namespace runtime
}  // namespace rac

#endif /* RAC_RUNTIME_PROVIDER_REGISTRY_H */
