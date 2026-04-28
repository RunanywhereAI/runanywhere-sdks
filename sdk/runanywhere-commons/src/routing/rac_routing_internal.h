/**
 * @file rac_routing_internal.h
 * @brief Router internals — capability-agnostic.
 *
 * After the modular refactor the registry is no longer parameterized by a
 * service vtable. An entry stores `void* impl` (the capability-typed service
 * handle, e.g. rac_stt_service_t*) and the per-capability `run_*` C API does
 * the cast at the boundary. Eligibility, scoring and the cascade only touch
 * the descriptor + conditions + impl pointer, so they share one set of
 * functions across STT / VAD / LLM / TTS / VLM.
 */

#ifndef RAC_ROUTING_INTERNAL_H
#define RAC_ROUTING_INTERNAL_H

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/routing/rac_routing_types.h"

namespace rac::routing {

struct Entry {
    rac_backend_descriptor_t             descriptor;
    std::vector<rac_routing_condition_t> conditions;  // owned copy
    void*                                impl;        // capability-typed service handle
};

struct Registry {
    std::mutex         mutex;
    std::vector<Entry> entries;
};

// Per-router configuration — held by the public handle, threaded into
// resolve()/cascade() so each instance can have its own policy/threshold.
struct RouterConfig {
    bool                 cascade_enabled    = true;
    float                cascade_threshold  = RAC_ROUTING_CONFIDENCE_THRESHOLD;
    rac_custom_policy_fn custom_policy_fn   = nullptr;
    void*                custom_policy_user = nullptr;
};

inline bool entry_is_local_only(const Entry& e) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        if (e.conditions[i].kind == RAC_COND_LOCAL_ONLY) return true;
    }
    return false;
}

inline bool entry_needs_network(const Entry& e) {
    for (int32_t i = 0; i < e.descriptor.condition_count; ++i) {
        if (e.conditions[i].kind == RAC_COND_NETWORK_REQUIRED) return true;
    }
    return false;
}

inline bool eligible(const Entry& e, const rac_routing_context_t& ctx) {
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

inline bool policy_allows(const Entry& e, rac_routing_policy_t policy) {
    const bool local = entry_is_local_only(e);
    switch (policy) {
        case RAC_ROUTING_POLICY_LOCAL_ONLY: return local;
        case RAC_ROUTING_POLICY_CLOUD_ONLY: return !local;
        default:                            return true;
    }
}

inline int32_t score(const Entry& e, const rac_routing_context_t& ctx,
                     const RouterConfig& cfg) {
    if (ctx.policy == RAC_ROUTING_POLICY_CUSTOM && cfg.custom_policy_fn) {
        return cfg.custom_policy_fn(&e.descriptor, &ctx, cfg.custom_policy_user);
    }
    int32_t    s     = e.descriptor.base_priority;
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

inline std::vector<Entry> resolve(Registry& reg, const rac_routing_context_t& ctx,
                                  const RouterConfig& cfg) {
    std::vector<Entry> snapshot;
    {
        std::lock_guard<std::mutex> lock(reg.mutex);
        snapshot.reserve(reg.entries.size());
        for (const auto& e : reg.entries) snapshot.push_back(e);
    }

    std::vector<Entry> filtered;
    filtered.reserve(snapshot.size());
    for (auto& e : snapshot) {
        e.descriptor.conditions = e.conditions.data();
        if (!eligible(e, ctx)) continue;
        if (!policy_allows(e, ctx.policy)) continue;
        filtered.push_back(std::move(e));
    }

    std::sort(filtered.begin(), filtered.end(),
              [&](const Entry& a, const Entry& b) {
                  return score(a, ctx, cfg) > score(b, ctx, cfg);
              });
    return filtered;
}

// Generic cascade. Capability-specific lambdas: `invoke` runs one candidate;
// `on_keep`/`on_restore`/`on_drop` manage the low-confidence checkpoint slot
// owned by the caller (the result struct shape is per-capability).
template <typename Invoker, typename OnKeep, typename OnRestore, typename OnDrop>
rac_result_t cascade(Registry&                    reg,
                     const rac_routing_context_t& ctx,
                     const RouterConfig&          cfg,
                     rac_routed_metadata_t*       out_meta,
                     Invoker                      invoke,
                     OnKeep                       on_keep,
                     OnRestore                    on_restore,
                     OnDrop                       on_drop) {
    auto candidates = resolve(reg, ctx, cfg);
    if (candidates.empty()) return RAC_ERROR_SERVICE_NOT_AVAILABLE;

    rac_result_t last_error            = RAC_ERROR_SERVICE_NOT_AVAILABLE;
    float        primary_conf          = std::numeric_limits<float>::quiet_NaN();
    bool         have_primary          = false;
    int32_t      attempts              = 0;
    bool         have_checkpoint       = false;
    size_t       checkpoint_index      = 0;
    float        checkpoint_conf       = std::numeric_limits<float>::quiet_NaN();
    rac_result_t cascade_err_code      = RAC_SUCCESS;
    const char*  cascade_err_module_id = nullptr;

    for (size_t i = 0; i < candidates.size(); ++i) {
        const auto& e    = candidates[i];
        float       conf = std::numeric_limits<float>::quiet_NaN();
        ++attempts;
        rac_result_t rc = invoke(e, &conf);
        if (rc != RAC_SUCCESS) {
            last_error = rc;
            // If we've already checkpointed a low-conf local, this failed
            // attempt is the cascade target — capture it for the UI.
            if (have_checkpoint) {
                cascade_err_code      = rc;
                cascade_err_module_id = e.descriptor.module_id;
            }
            RAC_LOG_WARNING("RAC.ROUTER", "backend '%s' failed with %d, trying next",
                            e.descriptor.module_id, rc);
            continue;
        }
        if (!have_primary) {
            primary_conf = conf;
            have_primary = true;
        }
        const bool local = entry_is_local_only(e);
        const bool low   = !std::isnan(conf) && conf < cfg.cascade_threshold;
        const bool can_cascade =
            cfg.cascade_enabled && local && low && (i + 1 < candidates.size());

        if (!can_cascade) {
            if (have_checkpoint) on_drop();
            if (out_meta) {
                std::strncpy(out_meta->chosen_module_id, e.descriptor.module_id,
                             sizeof(out_meta->chosen_module_id) - 1);
                out_meta->chosen_module_id[sizeof(out_meta->chosen_module_id) - 1] = '\0';
                out_meta->was_fallback       = (i > 0);
                out_meta->primary_confidence = primary_conf;
                out_meta->attempt_count      = attempts;
                out_meta->cascade_error_code = cascade_err_code;
                out_meta->cascade_error_module_id[0] = '\0';
                if (cascade_err_module_id) {
                    std::strncpy(out_meta->cascade_error_module_id, cascade_err_module_id,
                                 sizeof(out_meta->cascade_error_module_id) - 1);
                }
            }
            return RAC_SUCCESS;
        }

        if (have_checkpoint) on_drop();
        on_keep();
        have_checkpoint  = true;
        checkpoint_index = i;
        checkpoint_conf  = conf;
        RAC_LOG_INFO("RAC.ROUTER", "confidence %.2f below threshold, cascading from '%s'",
                     conf, e.descriptor.module_id);
        last_error = RAC_ERROR_SERVICE_NOT_AVAILABLE;
    }

    if (have_checkpoint) {
        on_restore();
        const auto& e = candidates[checkpoint_index];
        RAC_LOG_INFO("RAC.ROUTER",
                     "cascade exhausted; returning checkpoint '%s' (conf=%.2f)",
                     e.descriptor.module_id, checkpoint_conf);
        if (out_meta) {
            std::strncpy(out_meta->chosen_module_id, e.descriptor.module_id,
                         sizeof(out_meta->chosen_module_id) - 1);
            out_meta->chosen_module_id[sizeof(out_meta->chosen_module_id) - 1] = '\0';
            out_meta->was_fallback       = (checkpoint_index > 0);
            out_meta->primary_confidence = primary_conf;
            out_meta->attempt_count      = attempts;
            out_meta->cascade_error_code = cascade_err_code;
            out_meta->cascade_error_module_id[0] = '\0';
            if (cascade_err_module_id) {
                std::strncpy(out_meta->cascade_error_module_id, cascade_err_module_id,
                             sizeof(out_meta->cascade_error_module_id) - 1);
            }
        }
        return RAC_SUCCESS;
    }
    return last_error;
}

template <typename Invoker>
rac_result_t cascade(Registry&                    reg,
                     const rac_routing_context_t& ctx,
                     const RouterConfig&          cfg,
                     rac_routed_metadata_t*       out_meta,
                     Invoker                      invoke) {
    auto noop = [] {};
    return cascade(reg, ctx, cfg, out_meta, invoke, noop, noop, noop);
}

}  // namespace rac::routing

#endif  // RAC_ROUTING_INTERNAL_H
