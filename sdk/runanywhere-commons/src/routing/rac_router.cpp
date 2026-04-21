/**
 * @file rac_router.cpp
 * @brief Hybrid router implementation.
 */

#include "rac/routing/rac_router.h"

#include <mutex>
#include <new>
#include <string>

#include "rac/core/rac_logger.h"
#include "rac_routing_internal.h"

using rac::routing::Entry;
using rac::routing::Registry;
using rac::routing::cascade;

struct rac_router {
    Registry<rac_stt_service_t> stt;
};

namespace {

template <typename Service>
Entry<Service> make_entry(const rac_backend_descriptor_t* descriptor, Service* service) {
    Entry<Service> e;
    e.descriptor = *descriptor;
    if (descriptor->conditions && descriptor->condition_count > 0) {
        e.conditions.assign(descriptor->conditions,
                            descriptor->conditions + descriptor->condition_count);
    }
    e.descriptor.conditions      = e.conditions.data();
    e.descriptor.condition_count = static_cast<int32_t>(e.conditions.size());
    e.impl                       = service;
    e.vtable                     = nullptr;  // router uses service->ops directly
    return e;
}

}  // namespace

extern "C" rac_router_t* rac_router_create(void) {
    return new (std::nothrow) rac_router();
}

extern "C" void rac_router_destroy(rac_router_t* router) {
    if (!router) return;
    {
        std::lock_guard<std::mutex> lock(router->stt.mutex);
        router->stt.entries.clear();
    }
    delete router;
}

namespace {
std::once_flag g_router_once;
rac_router_t*  g_router       = nullptr;
std::mutex     g_router_mutex;
}  // namespace

extern "C" rac_router_t* rac_router_global(void) {
    std::call_once(g_router_once, [] { g_router = rac_router_create(); });
    return g_router;
}

extern "C" void rac_router_global_shutdown(void) {
    std::lock_guard<std::mutex> lock(g_router_mutex);
    if (g_router) {
        rac_router_destroy(g_router);
        g_router = nullptr;
    }
}

extern "C" rac_result_t rac_router_register_stt(rac_router_t*                   router,
                                                const rac_backend_descriptor_t* descriptor,
                                                rac_stt_service_t*              service) {
    if (!router || !descriptor || !service || !service->ops || !service->ops->transcribe) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (descriptor->capability != RAC_ROUTED_CAP_STT) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(router->stt.mutex);
    for (const auto& e : router->stt.entries) {
        if (std::strcmp(e.descriptor.module_id, descriptor->module_id) == 0) {
            return RAC_ERROR_INVALID_STATE;
        }
    }
    router->stt.entries.push_back(make_entry<rac_stt_service_t>(descriptor, service));
    RAC_LOG_INFO("RAC.ROUTER", "registered STT backend '%s' (priority=%d)",
                 descriptor->module_id, descriptor->base_priority);
    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_router_unregister_stt(rac_router_t* router, const char* module_id) {
    if (!router || !module_id) return RAC_ERROR_INVALID_PARAMETER;

    std::lock_guard<std::mutex> lock(router->stt.mutex);
    for (auto it = router->stt.entries.begin(); it != router->stt.entries.end(); ++it) {
        if (std::strcmp(it->descriptor.module_id, module_id) == 0) {
            router->stt.entries.erase(it);
            return RAC_SUCCESS;
        }
    }
    return RAC_ERROR_MODEL_NOT_FOUND;
}

extern "C" int32_t rac_router_stt_count(rac_router_t* router) {
    if (!router) return 0;
    std::lock_guard<std::mutex> lock(router->stt.mutex);
    return static_cast<int32_t>(router->stt.entries.size());
}

extern "C" rac_result_t rac_router_run_stt(rac_router_t*                router,
                                           const rac_routing_context_t* context,
                                           const void*                  audio_data,
                                           size_t                       audio_size,
                                           const rac_stt_options_t*     options,
                                           rac_stt_result_t*            out_result,
                                           rac_routed_metadata_t*       out_meta) {
    if (!router || !context || !audio_data || !out_result) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    if (out_meta) {
        out_meta->chosen_module_id[0] = '\0';
        out_meta->was_fallback        = false;
        out_meta->primary_confidence  = std::numeric_limits<float>::quiet_NaN();
        out_meta->attempt_count       = 0;
    }

    // Checkpoint storage for low-confidence fallback preservation.
    // rac_stt_result_t owns heap strings (text, detected_language) and a words
    // array — on keep(), move them out of out_result into checkpoint; on
    // restore(), move back; on drop(), free checkpoint via rac_stt_result_free.
    rac_stt_result_t checkpoint = {};

    return cascade(
        router->stt, *context, out_meta,
        [&](const Entry<rac_stt_service_t>& e, float* out_conf) -> rac_result_t {
            auto* svc = static_cast<rac_stt_service_t*>(e.impl);
            // Zero out_result before invoke so a failed call can't leak the
            // previous candidate's strings into the next attempt.
            *out_result = rac_stt_result_t{};
            rac_result_t rc =
                svc->ops->transcribe(svc->impl, audio_data, audio_size, options, out_result);
            if (rc == RAC_SUCCESS && out_conf) {
                *out_conf = out_result->confidence;
            }
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
