/**
 * @file rac_hybrid_router.cpp
 * @brief Handle-based hybrid router implementation.
 */

#include "rac/routing/rac_hybrid_router.h"

#include <cstring>
#include <limits>
#include <mutex>
#include <new>

#include "rac/core/rac_logger.h"
#include "rac_routing_internal.h"

using rac::routing::cascade;
using rac::routing::Entry;
using rac::routing::Registry;
using rac::routing::RouterConfig;

struct rac_hybrid_router {
    rac_routed_capability_t capability;
    Registry                registry;
    std::mutex              config_mutex;  // protects cfg
    RouterConfig            cfg;
};

namespace {

Entry make_entry(const rac_backend_descriptor_t* descriptor, void* service_handle) {
    Entry e;
    e.descriptor = *descriptor;
    if (descriptor->conditions && descriptor->condition_count > 0) {
        e.conditions.assign(descriptor->conditions,
                            descriptor->conditions + descriptor->condition_count);
    }
    e.descriptor.conditions      = e.conditions.data();
    e.descriptor.condition_count = static_cast<int32_t>(e.conditions.size());
    e.impl                       = service_handle;
    return e;
}

RouterConfig snapshot_config(rac_hybrid_router_t* r) {
    std::lock_guard<std::mutex> lock(r->config_mutex);
    return r->cfg;
}

}  // namespace

extern "C" rac_hybrid_router_t* rac_hybrid_router_create(rac_routed_capability_t capability) {
    auto* r = new (std::nothrow) rac_hybrid_router();
    if (!r) return nullptr;
    r->capability = capability;
    return r;
}

extern "C" void rac_hybrid_router_destroy(rac_hybrid_router_t* router) {
    if (!router) return;
    {
        std::lock_guard<std::mutex> lock(router->registry.mutex);
        router->registry.entries.clear();
    }
    delete router;
}

extern "C" rac_routed_capability_t
rac_hybrid_router_capability(const rac_hybrid_router_t* router) {
    return router ? router->capability : static_cast<rac_routed_capability_t>(0);
}

extern "C" rac_result_t rac_hybrid_router_set_cascade(rac_hybrid_router_t* router,
                                                       bool enabled, float threshold) {
    if (!router) return RAC_ERROR_INVALID_PARAMETER;
    if (threshold < 0.0f || threshold > 1.0f) return RAC_ERROR_INVALID_PARAMETER;
    std::lock_guard<std::mutex> lock(router->config_mutex);
    router->cfg.cascade_enabled   = enabled;
    router->cfg.cascade_threshold = threshold;
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_hybrid_router_set_custom_policy(rac_hybrid_router_t* router,
                                                             rac_custom_policy_fn fn,
                                                             void* user_data) {
    if (!router) return RAC_ERROR_INVALID_PARAMETER;
    std::lock_guard<std::mutex> lock(router->config_mutex);
    router->cfg.custom_policy_fn   = fn;
    router->cfg.custom_policy_user = user_data;
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_hybrid_router_register_backend(
    rac_hybrid_router_t* router, const rac_backend_descriptor_t* descriptor,
    void* service_handle) {
    if (!router || !descriptor || !service_handle) return RAC_ERROR_INVALID_PARAMETER;
    if (descriptor->capability != router->capability) return RAC_ERROR_INVALID_PARAMETER;

    // Capability-specific minimal validity check on the service handle.
    if (router->capability == RAC_ROUTED_CAP_STT) {
        auto* svc = static_cast<rac_stt_service_t*>(service_handle);
        if (!svc->ops || !svc->ops->transcribe) return RAC_ERROR_INVALID_PARAMETER;
    } else if (router->capability == RAC_ROUTED_CAP_VAD) {
        auto* svc = static_cast<rac_vad_routing_service_t*>(service_handle);
        if (!svc->ops || !svc->ops->process) return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(router->registry.mutex);
    for (const auto& e : router->registry.entries) {
        if (std::strcmp(e.descriptor.module_id, descriptor->module_id) == 0) {
            return RAC_ERROR_INVALID_STATE;
        }
    }
    router->registry.entries.push_back(make_entry(descriptor, service_handle));
    RAC_LOG_INFO("RAC.ROUTER", "registered backend '%s' cap=%d priority=%d",
                 descriptor->module_id, descriptor->capability, descriptor->base_priority);
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_hybrid_router_unregister(rac_hybrid_router_t* router,
                                                     const char*          module_id) {
    if (!router || !module_id) return RAC_ERROR_INVALID_PARAMETER;
    std::lock_guard<std::mutex> lock(router->registry.mutex);
    for (auto it = router->registry.entries.begin(); it != router->registry.entries.end(); ++it) {
        if (std::strcmp(it->descriptor.module_id, module_id) == 0) {
            router->registry.entries.erase(it);
            return RAC_SUCCESS;
        }
    }
    return RAC_ERROR_MODEL_NOT_FOUND;
}

extern "C" int32_t rac_hybrid_router_count(const rac_hybrid_router_t* router) {
    if (!router) return 0;
    auto& reg = const_cast<Registry&>(router->registry);
    std::lock_guard<std::mutex> lock(reg.mutex);
    return static_cast<int32_t>(reg.entries.size());
}

extern "C" rac_result_t rac_hybrid_router_run_vad(rac_hybrid_router_t*         router,
                                                  const rac_routing_context_t* context,
                                                  const float*                 samples,
                                                  size_t                       num_samples,
                                                  rac_vad_routed_result_t*     out_result,
                                                  rac_routed_metadata_t*       out_meta) {
    if (!router || !context || !samples || !out_result) return RAC_ERROR_INVALID_PARAMETER;
    if (router->capability != RAC_ROUTED_CAP_VAD) return RAC_ERROR_INVALID_STATE;

    if (out_meta) {
        out_meta->chosen_module_id[0] = '\0';
        out_meta->was_fallback        = false;
        out_meta->primary_confidence  = std::numeric_limits<float>::quiet_NaN();
        out_meta->attempt_count       = 0;
        out_meta->cascade_error_code  = RAC_SUCCESS;
        out_meta->cascade_error_module_id[0] = '\0';
    }

    RouterConfig cfg = snapshot_config(router);
    // VAD doesn't checkpoint — `out_result` is small POD; the no-checkpoint
    // cascade overload returns the first SUCCESS or the last error.
    return cascade(router->registry, *context, cfg, out_meta,
                   [&](const Entry& e, float* out_conf) -> rac_result_t {
                       auto* svc = static_cast<rac_vad_routing_service_t*>(e.impl);
                       *out_result = rac_vad_routed_result_t{};
                       rac_result_t rc =
                           svc->ops->process(svc->impl, samples, num_samples, out_result);
                       if (rc == RAC_SUCCESS && out_conf) *out_conf = out_result->confidence;
                       return rc;
                   });
}

extern "C" rac_result_t rac_hybrid_router_run_stt(rac_hybrid_router_t*         router,
                                                  const rac_routing_context_t* context,
                                                  const void*                  audio_data,
                                                  size_t                       audio_size,
                                                  const rac_stt_options_t*     options,
                                                  rac_stt_result_t*            out_result,
                                                  rac_routed_metadata_t*       out_meta) {
    if (!router || !context || !audio_data || !out_result) return RAC_ERROR_INVALID_PARAMETER;
    if (router->capability != RAC_ROUTED_CAP_STT) return RAC_ERROR_INVALID_STATE;

    if (out_meta) {
        out_meta->chosen_module_id[0] = '\0';
        out_meta->was_fallback        = false;
        out_meta->primary_confidence  = std::numeric_limits<float>::quiet_NaN();
        out_meta->attempt_count       = 0;
        out_meta->cascade_error_code  = RAC_SUCCESS;
        out_meta->cascade_error_module_id[0] = '\0';
    }

    rac_stt_result_t checkpoint = {};
    RouterConfig     cfg        = snapshot_config(router);

    return cascade(
        router->registry, *context, cfg, out_meta,
        [&](const Entry& e, float* out_conf) -> rac_result_t {
            auto* svc = static_cast<rac_stt_service_t*>(e.impl);
            *out_result = rac_stt_result_t{};
            rac_result_t rc =
                svc->ops->transcribe(svc->impl, audio_data, audio_size, options, out_result);
            if (rc == RAC_SUCCESS && out_conf) *out_conf = out_result->confidence;
            return rc;
        },
        /*on_keep*/ [&] {
            checkpoint  = *out_result;
            *out_result = rac_stt_result_t{};
        },
        /*on_restore*/ [&] {
            *out_result = checkpoint;
            checkpoint  = rac_stt_result_t{};
        },
        /*on_drop*/ [&] {
            rac_stt_result_free(&checkpoint);
            checkpoint = rac_stt_result_t{};
        });
}
