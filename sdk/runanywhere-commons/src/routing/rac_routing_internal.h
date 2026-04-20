/**
 * @file rac_routing_internal.h
 * @brief Router internals shared across capabilities.
 */

#ifndef RAC_ROUTING_INTERNAL_H
#define RAC_ROUTING_INTERNAL_H

#include <algorithm>
#include <cmath>
#include <cstring>
#include <functional>
#include <limits>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/routing/rac_router.h"
#include "rac/routing/rac_routing_types.h"

namespace rac::routing {

template <typename Vtable>
struct Entry {
    rac_backend_descriptor_t descriptor;
    std::vector<rac_routing_condition_t> conditions;  // copied
    void*                                impl;
    const Vtable*                        vtable;
};

template <typename Vtable>
struct Registry {
    std::mutex                mutex;
    std::vector<Entry<Vtable>> entries;
};

// Is a descriptor's framework flagged local-only?
inline bool is_local_only(const Entry<void>* = nullptr) { return false; }

template <typename Vtable>
bool entry_is_local_only(const Entry<Vtable>& e) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        if (e.conditions[i].kind == RAC_COND_LOCAL_ONLY) return true;
    }
    return false;
}

template <typename Vtable>
bool entry_needs_network(const Entry<Vtable>& e) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        if (e.conditions[i].kind == RAC_COND_NETWORK_REQUIRED) return true;
    }
    return false;
}

template <typename Vtable>
float entry_cost(const Entry<Vtable>& e) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        if (e.conditions[i].kind == RAC_COND_COST_MODEL) {
            return e.conditions[i].data.cost_per_minute_cents;
        }
    }
    return 0.0f;
}

template <typename Vtable>
bool eligible(const Entry<Vtable>& e, const rac_routing_context_t& ctx) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        const auto& c = e.conditions[i];
        switch (c.kind) {
            case RAC_COND_NETWORK_REQUIRED:
                if (!ctx.is_online) return false;
                break;
            case RAC_COND_MODEL_AVAILABILITY:
                if (c.data.availability.check &&
                    !c.data.availability.check(c.data.availability.user_data)) {
                    return false;
                }
                break;
            case RAC_COND_CUSTOM:
                if (c.data.custom.check &&
                    !c.data.custom.check(c.data.custom.user_data, &ctx)) {
                    return false;
                }
                break;
            case RAC_COND_LOCAL_ONLY:
            case RAC_COND_QUALITY_TIER:
            case RAC_COND_COST_MODEL:
                break;
        }
    }
    return true;
}

template <typename Vtable>
bool policy_allows(const Entry<Vtable>& e, rac_routing_policy_t policy) {
    const bool local = entry_is_local_only(e);
    switch (policy) {
        case RAC_ROUTING_POLICY_LOCAL_ONLY:  return local;
        case RAC_ROUTING_POLICY_CLOUD_ONLY:  return !local;
        default:                             return true;
    }
}

template <typename Vtable>
int32_t score(const Entry<Vtable>& e, const rac_routing_context_t& ctx) {
    int32_t s = e.descriptor.base_priority;
    const bool local = entry_is_local_only(e);
    switch (ctx.policy) {
        case RAC_ROUTING_POLICY_PREFER_LOCAL:
            if (local) s += 100;
            break;
        case RAC_ROUTING_POLICY_PREFER_ACCURACY:
            if (!local) s += 50;
            break;
        case RAC_ROUTING_POLICY_FRAMEWORK_PREFERRED:
            if (ctx.preferred_framework[0] &&
                std::strcmp(ctx.preferred_framework, e.descriptor.inference_framework) == 0) {
                s += 200;
            }
            break;
        default:
            break;
    }
    return s;
}

template <typename Vtable>
std::vector<Entry<Vtable>> resolve(Registry<Vtable>& reg, const rac_routing_context_t& ctx) {
    std::vector<Entry<Vtable>> snapshot;
    {
        std::lock_guard<std::mutex> lock(reg.mutex);
        snapshot.reserve(reg.entries.size());
        for (const auto& e : reg.entries) {
            // Deep-copy entry with its conditions (already owned).
            snapshot.push_back(e);
        }
    }

    std::vector<Entry<Vtable>> filtered;
    filtered.reserve(snapshot.size());
    for (auto& e : snapshot) {
        // Rewire descriptor.conditions to the snapshot's own vector storage.
        e.descriptor.conditions = e.conditions.data();
        if (!eligible(e, ctx)) continue;
        if (!policy_allows(e, ctx.policy)) continue;
        filtered.push_back(std::move(e));
    }

    std::sort(filtered.begin(), filtered.end(),
              [&](const Entry<Vtable>& a, const Entry<Vtable>& b) {
                  return score(a, ctx) > score(b, ctx);
              });
    return filtered;
}

// Generic cascade. Invoker runs one candidate and reports its confidence.
// Returns RAC_SUCCESS once a candidate returns a trusted result; fills
// out_meta when provided.
template <typename Vtable, typename Invoker>
rac_result_t cascade(Registry<Vtable>&            reg,
                     const rac_routing_context_t& ctx,
                     rac_routed_metadata_t*       out_meta,
                     Invoker                      invoke) {
    auto candidates = resolve(reg, ctx);
    if (candidates.empty()) {
        return RAC_ERROR_SERVICE_NOT_AVAILABLE;
    }

    rac_result_t last_error       = RAC_ERROR_SERVICE_NOT_AVAILABLE;
    float        primary_conf     = std::numeric_limits<float>::quiet_NaN();
    bool         have_primary     = false;
    int32_t      attempts         = 0;

    for (size_t i = 0; i < candidates.size(); ++i) {
        const auto& e    = candidates[i];
        float       conf = std::numeric_limits<float>::quiet_NaN();
        ++attempts;
        rac_result_t rc = invoke(e, &conf);
        if (rc != RAC_SUCCESS) {
            last_error = rc;
            RAC_LOG_WARNING("RAC.ROUTER", "backend '%s' failed with %d, trying next",
                            e.descriptor.module_id, rc);
            continue;
        }

        if (!have_primary) {
            primary_conf = conf;
            have_primary = true;
        }

        const bool local = entry_is_local_only(e);
        const bool low   = !std::isnan(conf) && conf < RAC_ROUTING_CONFIDENCE_THRESHOLD;
        const bool can_cascade = local && low && (i + 1 < candidates.size());

        if (!can_cascade) {
            if (out_meta) {
                std::strncpy(out_meta->chosen_module_id, e.descriptor.module_id,
                             sizeof(out_meta->chosen_module_id) - 1);
                out_meta->chosen_module_id[sizeof(out_meta->chosen_module_id) - 1] = '\0';
                out_meta->was_fallback       = (i > 0);
                out_meta->primary_confidence = primary_conf;
                out_meta->attempt_count      = attempts;
            }
            return RAC_SUCCESS;
        }

        RAC_LOG_INFO("RAC.ROUTER", "confidence %.2f below threshold, cascading from '%s'",
                     conf, e.descriptor.module_id);
        last_error = RAC_ERROR_SERVICE_NOT_AVAILABLE;
    }

    return last_error;
}

}  // namespace rac::routing

#endif  // RAC_ROUTING_INTERNAL_H
