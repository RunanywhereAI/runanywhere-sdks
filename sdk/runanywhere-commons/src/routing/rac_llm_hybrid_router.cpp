/**
 * @file rac_llm_hybrid_router.cpp
 * @brief LLM hybrid router — capability-specific router that owns one
 *        offline + one online rac_llm_service_t and dispatches per request.
 *
 * Algorithm:
 *   1. Build candidates = [offline?, online?].
 *   2. Filter candidates against rac_hybrid_routing_policy_t.hard_filters,
 *      using the per-request rac_hybrid_routing_context_t for runtime
 *      state (is_online, battery, input sensitivity).
 *   3. Rank surviving candidates by rac_hybrid_rank_t.
 *   4. Invoke primary. If primary fails AND a secondary candidate exists,
 *      try the secondary (failure fallback). Return secondary result with
 *      was_fallback=true on success; otherwise return primary's error.
 *   5. (Confidence-based cascade on primary success is task #26,
 *      streaming-only.)
 */

#include "rac/routing/rac_llm_hybrid_router.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/routing/rac_hybrid_types.h"

namespace {

struct Candidate {
    rac_llm_service_t*            service;
    rac_hybrid_model_descriptor_t descriptor;
};

struct RouterImpl {
    std::mutex                       mutex;
    rac_llm_service_t*               offline_service = nullptr;
    rac_hybrid_model_descriptor_t    offline_descriptor{};
    bool                             has_offline = false;
    rac_llm_service_t*               online_service = nullptr;
    rac_hybrid_model_descriptor_t    online_descriptor{};
    bool                             has_online = false;
    std::vector<rac_hybrid_filter_t> filters;
    rac_hybrid_cascade_t             cascade{};
    rac_hybrid_rank_t                rank = RAC_HYBRID_RANK_UNSPECIFIED;
    // Set to the service currently executing generate / generate_stream so
    // rac_llm_hybrid_router_cancel can forward to its ops->cancel without
    // taking the (possibly contended) mutex.
    std::atomic<rac_llm_service_t*>  active_call_service{nullptr};
};

inline RouterImpl* impl_of(rac_handle_t h) {
    return static_cast<RouterImpl*>(h);
}

bool evaluate_filter(const rac_hybrid_filter_t&          f,
                     const Candidate&                    c,
                     const rac_hybrid_routing_context_t& ctx) {
    switch (f.kind) {
        case RAC_HYBRID_FILTER_NONE:
            return true;
        case RAC_HYBRID_FILTER_NETWORK:
            if (c.descriptor.model_type == RAC_HYBRID_MODEL_TYPE_ONLINE) {
                return ctx.is_online;
            }
            return true;
        case RAC_HYBRID_FILTER_QUALITY:
            return true;
        case RAC_HYBRID_FILTER_BATTERY:
            if (c.descriptor.model_type == RAC_HYBRID_MODEL_TYPE_ONLINE) {
                if (ctx.battery_percent < f.data.battery.min_battery_percent) {
                    return false;
                }
            }
            return true;
        case RAC_HYBRID_FILTER_CUSTOM:
            if (f.data.custom.check == nullptr) {
                return true;
            }
            return f.data.custom.check(c.descriptor.model_id, f.data.custom.user_data);
    }
    return true;
}

bool rank_less(const Candidate& a, const Candidate& b, rac_hybrid_rank_t rank) {
    switch (rank) {
        case RAC_HYBRID_RANK_PREFER_LOCAL_FIRST:
            return a.descriptor.model_type == RAC_HYBRID_MODEL_TYPE_OFFLINE &&
                   b.descriptor.model_type != RAC_HYBRID_MODEL_TYPE_OFFLINE;
        case RAC_HYBRID_RANK_PREFER_ONLINE_FIRST:
            return a.descriptor.model_type == RAC_HYBRID_MODEL_TYPE_ONLINE &&
                   b.descriptor.model_type != RAC_HYBRID_MODEL_TYPE_ONLINE;
        case RAC_HYBRID_RANK_UNSPECIFIED:
        default:
            return false;
    }
}

std::vector<Candidate> collect_eligible(const RouterImpl&                   r,
                                        const rac_hybrid_routing_context_t& ctx) {
    std::vector<Candidate> out;
    out.reserve(2);
    if (r.has_offline && r.offline_service != nullptr) {
        out.push_back({r.offline_service, r.offline_descriptor});
    }
    if (r.has_online && r.online_service != nullptr) {
        out.push_back({r.online_service, r.online_descriptor});
    }
    out.erase(std::remove_if(out.begin(), out.end(),
                              [&](const Candidate& c) {
                                  for (const auto& f : r.filters) {
                                      if (!evaluate_filter(f, c, ctx)) {
                                          return true;
                                      }
                                  }
                                  return false;
                              }),
              out.end());
    std::stable_sort(out.begin(), out.end(),
                     [&](const Candidate& a, const Candidate& b) {
                         return rank_less(a, b, r.rank);
                     });
    return out;
}

void copy_id_into(char (&dst)[128], const char* src) {
    if (src == nullptr) {
        dst[0] = '\0';
        return;
    }
    std::strncpy(dst, src, sizeof(dst) - 1);
    dst[sizeof(dst) - 1] = '\0';
}

void copy_message_into(char (&dst)[256], const char* src) {
    if (src == nullptr) {
        dst[0] = '\0';
        return;
    }
    std::strncpy(dst, src, sizeof(dst) - 1);
    dst[sizeof(dst) - 1] = '\0';
}

rac_result_t invoke_candidate(const Candidate&         c,
                              const char*              prompt,
                              const rac_llm_options_t* options,
                              rac_llm_result_t*        out) {
    if (c.service == nullptr || c.service->ops == nullptr ||
        c.service->ops->generate == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return c.service->ops->generate(c.service->impl, prompt, options, out);
}

}  // namespace

extern "C" {

rac_result_t rac_llm_hybrid_router_create(rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    auto* r = new (std::nothrow) RouterImpl();
    if (r == nullptr) {
        *out_handle = RAC_INVALID_HANDLE;
        return RAC_ERROR_INITIALIZATION_FAILED;
    }
    *out_handle = static_cast<rac_handle_t>(r);
    return RAC_SUCCESS;
}

void rac_llm_hybrid_router_destroy(rac_handle_t handle) {
    if (handle == RAC_INVALID_HANDLE) {
        return;
    }
    delete impl_of(handle);
}

rac_result_t rac_llm_hybrid_router_set_offline_service(
    rac_handle_t                         handle,
    rac_llm_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor) {
    auto* r = impl_of(handle);
    if (r == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::lock_guard<std::mutex> lock(r->mutex);
    r->offline_service = service;
    if (service != nullptr && descriptor != nullptr) {
        r->offline_descriptor = *descriptor;
        r->offline_descriptor.model_type = RAC_HYBRID_MODEL_TYPE_OFFLINE;
        r->has_offline = true;
    } else {
        r->has_offline = false;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_llm_hybrid_router_set_online_service(
    rac_handle_t                         handle,
    rac_llm_service_t*                   service,
    const rac_hybrid_model_descriptor_t* descriptor) {
    auto* r = impl_of(handle);
    if (r == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::lock_guard<std::mutex> lock(r->mutex);
    r->online_service = service;
    if (service != nullptr && descriptor != nullptr) {
        r->online_descriptor = *descriptor;
        r->online_descriptor.model_type = RAC_HYBRID_MODEL_TYPE_ONLINE;
        r->has_online = true;
    } else {
        r->has_online = false;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_llm_hybrid_router_set_policy(
    rac_handle_t                       handle,
    const rac_hybrid_routing_policy_t* policy) {
    auto* r = impl_of(handle);
    if (r == nullptr || policy == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::lock_guard<std::mutex> lock(r->mutex);
    r->filters.clear();
    if (policy->hard_filters != nullptr && policy->hard_filter_count > 0) {
        r->filters.reserve(static_cast<size_t>(policy->hard_filter_count));
        for (int32_t i = 0; i < policy->hard_filter_count; ++i) {
            r->filters.push_back(policy->hard_filters[i]);
        }
    }
    r->cascade = policy->cascade;
    r->rank = policy->rank;
    return RAC_SUCCESS;
}

rac_result_t rac_llm_hybrid_router_generate(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const char*                         prompt,
    const rac_llm_options_t*            options,
    rac_llm_result_t*                   out_result,
    rac_hybrid_routed_metadata_t*       out_metadata) {
    if (out_metadata != nullptr) {
        std::memset(out_metadata, 0, sizeof(*out_metadata));
    }
    if (out_result != nullptr) {
        std::memset(out_result, 0, sizeof(*out_result));
    }
    auto* r = impl_of(handle);
    if (r == nullptr || ctx == nullptr || prompt == nullptr || out_result == nullptr ||
        out_metadata == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::vector<Candidate> ordered;
    {
        std::lock_guard<std::mutex> lock(r->mutex);
        ordered = collect_eligible(*r, *ctx);
    }
    if (ordered.empty()) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    const Candidate& primary = ordered.front();
    out_metadata->attempt_count = 1;
    copy_id_into(out_metadata->chosen_model_id, primary.descriptor.model_id);

    rac_llm_result_t primary_result{};
    r->active_call_service.store(primary.service, std::memory_order_release);
    rac_result_t     primary_rc = invoke_candidate(primary, prompt, options, &primary_result);
    r->active_call_service.store(nullptr, std::memory_order_release);

    if (primary_rc == RAC_SUCCESS) {
        *out_result = primary_result;
        return RAC_SUCCESS;
    }

    // Failure fallback: primary errored out; try the next-ranked candidate
    // unconditionally. Confidence-based cascade-on-success is task #26 and
    // is not wired into the non-streaming path.
    const bool has_secondary = ordered.size() >= 2;
    if (has_secondary) {
        rac_llm_result_t secondary_result{};
        const Candidate& secondary = ordered[1];
        out_metadata->attempt_count = 2;
        r->active_call_service.store(secondary.service, std::memory_order_release);
        rac_result_t secondary_rc =
            invoke_candidate(secondary, prompt, options, &secondary_result);
        r->active_call_service.store(nullptr, std::memory_order_release);
        if (secondary_rc == RAC_SUCCESS) {
            copy_id_into(out_metadata->chosen_model_id, secondary.descriptor.model_id);
            out_metadata->was_fallback = true;
            out_metadata->primary_error_code = static_cast<int32_t>(primary_rc);
            copy_message_into(out_metadata->primary_error_message,
                              rac_error_message(primary_rc));
            *out_result = secondary_result;
            return RAC_SUCCESS;
        }
    }
    return primary_rc;
}

rac_result_t rac_llm_hybrid_router_generate_stream(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const char*                         prompt,
    const rac_llm_options_t*            options,
    rac_llm_stream_callback_fn          callback,
    void*                               user_data,
    rac_hybrid_routed_metadata_t*       out_metadata) {
    if (out_metadata != nullptr) {
        std::memset(out_metadata, 0, sizeof(*out_metadata));
    }
    auto* r = impl_of(handle);
    if (r == nullptr || ctx == nullptr || prompt == nullptr || callback == nullptr ||
        out_metadata == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::vector<Candidate> ordered;
    {
        std::lock_guard<std::mutex> lock(r->mutex);
        ordered = collect_eligible(*r, *ctx);
    }
    if (ordered.empty()) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    const Candidate& primary = ordered.front();
    out_metadata->attempt_count = 1;
    copy_id_into(out_metadata->chosen_model_id, primary.descriptor.model_id);

    if (primary.service == nullptr || primary.service->ops == nullptr ||
        primary.service->ops->generate_stream == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    r->active_call_service.store(primary.service, std::memory_order_release);
    rac_result_t primary_rc = primary.service->ops->generate_stream(
        primary.service->impl, prompt, options, callback, user_data);
    r->active_call_service.store(nullptr, std::memory_order_release);

    if (primary_rc == RAC_SUCCESS) {
        return RAC_SUCCESS;
    }

    // Failure fallback: primary's stream errored before completing; try the
    // next-ranked candidate. Confidence-based cascade-on-streaming is task
    // #26 and will layer on top of this by inspecting per-token confidence.
    const bool has_secondary = ordered.size() >= 2;
    if (has_secondary) {
        const Candidate& secondary = ordered[1];
        if (secondary.service == nullptr || secondary.service->ops == nullptr ||
            secondary.service->ops->generate_stream == nullptr) {
            return primary_rc;
        }
        out_metadata->attempt_count = 2;
        r->active_call_service.store(secondary.service, std::memory_order_release);
        rac_result_t secondary_rc = secondary.service->ops->generate_stream(
            secondary.service->impl, prompt, options, callback, user_data);
        r->active_call_service.store(nullptr, std::memory_order_release);
        if (secondary_rc == RAC_SUCCESS) {
            copy_id_into(out_metadata->chosen_model_id, secondary.descriptor.model_id);
            out_metadata->was_fallback = true;
            out_metadata->primary_error_code = static_cast<int32_t>(primary_rc);
            copy_message_into(out_metadata->primary_error_message,
                              rac_error_message(primary_rc));
            return RAC_SUCCESS;
        }
    }
    return primary_rc;
}

rac_result_t rac_llm_hybrid_router_cancel(rac_handle_t handle) {
    auto* r = impl_of(handle);
    if (r == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_llm_service_t* svc = r->active_call_service.load(std::memory_order_acquire);
    if (svc == nullptr || svc->ops == nullptr || svc->ops->cancel == nullptr) {
        return RAC_SUCCESS;
    }
    return svc->ops->cancel(svc->impl);
}

}  // extern "C"
