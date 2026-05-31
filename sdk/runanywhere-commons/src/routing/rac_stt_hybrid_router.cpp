/**
 * @file rac_stt_hybrid_router.cpp
 * @brief STT hybrid router — owns one offline + one online rac_stt_service_t
 *        and dispatches each transcribe request between them.
 *
 * Algorithm:
 *   1. Build candidates = [offline?, online?].
 *   2. Filter candidates against rac_hybrid_routing_policy_t.hard_filters,
 *      using the per-request rac_hybrid_routing_context_t for runtime
 *      state (is_online, battery).
 *   3. Rank surviving candidates by rac_hybrid_rank_t.
 *   4. Invoke primary. If it succeeds with a real (non-NaN) confidence below
 *      RAC_HYBRID_STT_CONFIDENCE_THRESHOLD and a secondary exists, cascade to
 *      the secondary (confidence cascade). If it fails outright and a
 *      secondary exists, try the secondary (failure fallback). Either way the
 *      secondary result is returned with was_fallback=true on success;
 *      otherwise the primary's result/error stands.
 *
 * Confidence only flows from the offline (sherpa) side — the cloud (Sarvam)
 * does not surface a transcript-quality signal, so its confidence is NaN and
 * never triggers a cascade.
 */

#include "rac/routing/rac_stt_hybrid_router.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/routing/rac_hybrid_types.h"

namespace {

struct Candidate {
    rac_stt_service_t*            service;
    rac_hybrid_model_descriptor_t descriptor;
};

struct RouterImpl {
    std::mutex                       mutex;
    rac_stt_service_t*               offline_service = nullptr;
    rac_hybrid_model_descriptor_t    offline_descriptor{};
    bool                             has_offline = false;
    rac_stt_service_t*               online_service = nullptr;
    rac_hybrid_model_descriptor_t    online_descriptor{};
    bool                             has_online = false;
    std::vector<rac_hybrid_filter_t> filters;
    rac_hybrid_cascade_t             cascade{};
    rac_hybrid_rank_t                rank = RAC_HYBRID_RANK_UNSPECIFIED;
    // Set to the service currently executing transcribe so
    // rac_stt_hybrid_router_cancel can forward to its ops->cancel without
    // taking the (possibly contended) mutex.
    std::atomic<rac_stt_service_t*>  active_call_service{nullptr};
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
                              const void*              audio_data,
                              size_t                   audio_size,
                              const rac_stt_options_t* options,
                              rac_stt_result_t*        out) {
    if (c.service == nullptr || c.service->ops == nullptr ||
        c.service->ops->transcribe == nullptr) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    return c.service->ops->transcribe(c.service->impl, audio_data, audio_size, options, out);
}

}  // namespace

extern "C" {

rac_result_t rac_stt_hybrid_router_create(rac_handle_t* out_handle) {
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

void rac_stt_hybrid_router_destroy(rac_handle_t handle) {
    if (handle == RAC_INVALID_HANDLE) {
        return;
    }
    delete impl_of(handle);
}

rac_result_t rac_stt_hybrid_router_set_offline_service(
    rac_handle_t                         handle,
    rac_stt_service_t*                   service,
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

rac_result_t rac_stt_hybrid_router_set_online_service(
    rac_handle_t                         handle,
    rac_stt_service_t*                   service,
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

rac_result_t rac_stt_hybrid_router_set_policy(
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

rac_result_t rac_stt_hybrid_router_transcribe(
    rac_handle_t                        handle,
    const rac_hybrid_routing_context_t* ctx,
    const void*                         audio_data,
    size_t                              audio_size,
    const rac_stt_options_t*            options,
    rac_stt_result_t*                   out_result,
    rac_hybrid_routed_metadata_t*       out_metadata) {
    if (out_metadata != nullptr) {
        std::memset(out_metadata, 0, sizeof(*out_metadata));
    }
    if (out_result != nullptr) {
        std::memset(out_result, 0, sizeof(*out_result));
    }
    auto* r = impl_of(handle);
    if (r == nullptr || ctx == nullptr || audio_data == nullptr || audio_size == 0 ||
        out_result == nullptr || out_metadata == nullptr) {
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

    const float kNaN = std::numeric_limits<float>::quiet_NaN();
    out_metadata->confidence = kNaN;
    out_metadata->primary_confidence = kNaN;

    const Candidate& primary = ordered.front();
    out_metadata->attempt_count = 1;
    copy_id_into(out_metadata->chosen_model_id, primary.descriptor.model_id);

    rac_stt_result_t primary_result{};
    r->active_call_service.store(primary.service, std::memory_order_release);
    rac_result_t     primary_rc =
        invoke_candidate(primary, audio_data, audio_size, options, &primary_result);
    r->active_call_service.store(nullptr, std::memory_order_release);

    const bool has_secondary = ordered.size() >= 2;

    if (primary_rc == RAC_SUCCESS) {
        const float primary_conf = primary_result.confidence;
        // Confidence cascade: when the primary returned a real (non-NaN)
        // confidence below the threshold AND a secondary candidate exists,
        // try the secondary. NaN means "no signal" — accept the primary.
        const bool low_confidence =
            !std::isnan(primary_conf) &&
            primary_conf < RAC_HYBRID_STT_CONFIDENCE_THRESHOLD;

        if (low_confidence && has_secondary) {
            rac_stt_result_t secondary_result{};
            const Candidate& secondary = ordered[1];
            out_metadata->attempt_count = 2;
            r->active_call_service.store(secondary.service, std::memory_order_release);
            rac_result_t secondary_rc = invoke_candidate(
                secondary, audio_data, audio_size, options, &secondary_result);
            r->active_call_service.store(nullptr, std::memory_order_release);
            if (secondary_rc == RAC_SUCCESS) {
                copy_id_into(out_metadata->chosen_model_id, secondary.descriptor.model_id);
                out_metadata->was_fallback = true;
                out_metadata->primary_confidence = primary_conf;
                out_metadata->confidence = secondary_result.confidence;
                // The primary did not error; leave primary_error_code at 0.
                rac_stt_result_free(&primary_result);
                *out_result = secondary_result;
                return RAC_SUCCESS;
            }
            // Cascade attempt failed — keep the primary result.
            rac_stt_result_free(&secondary_result);
        }

        out_metadata->confidence = primary_conf;
        *out_result = primary_result;
        return RAC_SUCCESS;
    }

    // Failure fallback: primary errored out; try the next-ranked candidate
    // unconditionally.
    if (has_secondary) {
        rac_stt_result_t secondary_result{};
        const Candidate& secondary = ordered[1];
        out_metadata->attempt_count = 2;
        r->active_call_service.store(secondary.service, std::memory_order_release);
        rac_result_t secondary_rc =
            invoke_candidate(secondary, audio_data, audio_size, options, &secondary_result);
        r->active_call_service.store(nullptr, std::memory_order_release);
        if (secondary_rc == RAC_SUCCESS) {
            copy_id_into(out_metadata->chosen_model_id, secondary.descriptor.model_id);
            out_metadata->was_fallback = true;
            out_metadata->primary_error_code = static_cast<int32_t>(primary_rc);
            copy_message_into(out_metadata->primary_error_message,
                              rac_error_message(primary_rc));
            out_metadata->confidence = secondary_result.confidence;
            *out_result = secondary_result;
            return RAC_SUCCESS;
        }
    }
    return primary_rc;
}

rac_result_t rac_stt_hybrid_router_cancel(rac_handle_t handle) {
    auto* r = impl_of(handle);
    if (r == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_stt_service_t* svc = r->active_call_service.load(std::memory_order_acquire);
    if (svc == nullptr || svc->ops == nullptr) {
        return RAC_SUCCESS;
    }
    // rac_stt_service_ops_t has no cancel op today; nothing to forward to.
    // Future engines that add one can wire it here.
    return RAC_SUCCESS;
}

}  // extern "C"
