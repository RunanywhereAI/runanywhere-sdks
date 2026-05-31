/**
 * @file rac_llm_hybrid_router_proto.cpp
 * @brief Proto-byte wrappers for the hybrid router. All proto type usage
 *        stays inside rac_commons.so so the hidden-visibility default
 *        doesn't strand symbols at the .so boundary.
 *
 * Each wrapper:
 *   1. Decodes the runanywhere.v1.* proto bytes into a transient message.
 *   2. Translates that message into the native C struct surface the
 *      router consumes (rac_hybrid_filter_t, rac_hybrid_routing_policy_t,
 *      rac_hybrid_routing_context_t, ...).
 *   3. Calls the existing rac_llm_hybrid_router_* C ABI.
 *   4. For generate_proto, builds and serialises a
 *      runanywhere.v1.HybridLlmGenerateResponse and returns it as a heap
 *      allocation the binding frees via
 *      rac_llm_hybrid_router_proto_buffer_free.
 */

#include "rac/routing/rac_llm_hybrid_router_proto.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "hybrid_router.pb.h"

#include "rac/features/llm/rac_llm_types.h"
#include "rac/routing/rac_hybrid_device_state.h"
#include "rac/routing/rac_hybrid_types.h"
#include "rac/routing/rac_llm_hybrid_router.h"

namespace v1 = ::runanywhere::v1;

namespace {

void parse_descriptor(const uint8_t* bytes, size_t size,
                      rac_hybrid_model_descriptor_t& out) {
    std::memset(&out, 0, sizeof(out));
    if (bytes == nullptr || size == 0) {
        return;
    }
    v1::HybridModelDescriptor msg;
    if (!msg.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }
    const auto& id = msg.model_id();
    std::strncpy(out.model_id, id.c_str(), sizeof(out.model_id) - 1);
    out.model_type = static_cast<rac_hybrid_model_type_t>(msg.model_type());
    out.backend = static_cast<rac_hybrid_backend_kind_t>(msg.backend());
}

bool parse_filter(const v1::HybridFilter& f, rac_hybrid_filter_t& out) {
    std::memset(&out, 0, sizeof(out));
    switch (f.kind_case()) {
        case v1::HybridFilter::kNetwork:
            out.kind = RAC_HYBRID_FILTER_NETWORK;
            out.data.network_required = f.network();
            return true;
        case v1::HybridFilter::kQualityTier:
            out.kind = RAC_HYBRID_FILTER_QUALITY;
            out.data.quality_tier = f.quality_tier();
            return true;
        case v1::HybridFilter::kBattery:
            out.kind = RAC_HYBRID_FILTER_BATTERY;
            out.data.battery.min_battery_percent = f.battery().min_battery_percent();
            return true;
        case v1::HybridFilter::kCustom:
            // Custom filters require a callback that lives in the
            // host-language SDK. The binding evaluates them before
            // calling this entry point, so the native router never
            // sees a CUSTOM kind here.
            return false;
        case v1::HybridFilter::KIND_NOT_SET:
        default:
            return false;
    }
}

void parse_policy(const uint8_t* bytes, size_t size,
                  std::vector<rac_hybrid_filter_t>& filters,
                  rac_hybrid_routing_policy_t& policy) {
    filters.clear();
    std::memset(&policy, 0, sizeof(policy));
    if (bytes != nullptr && size > 0) {
        v1::HybridRoutingPolicy msg;
        if (msg.ParseFromArray(bytes, static_cast<int>(size))) {
            for (const auto& f : msg.hard_filters()) {
                rac_hybrid_filter_t parsed{};
                if (parse_filter(f, parsed)) {
                    filters.push_back(parsed);
                }
            }
            if (msg.has_cascade()) {
                const auto& c = msg.cascade();
                if (c.kind_case() == v1::HybridCascade::kConfidence) {
                    policy.cascade.kind = RAC_HYBRID_CASCADE_CONFIDENCE;
                    policy.cascade.data.confidence.threshold = c.confidence().threshold();
                }
            }
            policy.rank = static_cast<rac_hybrid_rank_t>(msg.rank());
        }
    }
    policy.hard_filters = filters.empty() ? nullptr : filters.data();
    policy.hard_filter_count = static_cast<int32_t>(filters.size());
}

/** Build the eval-time context from the device-state vtable. The proto
    context message currently carries no fields, so `proto_ctx` is unused;
    it remains in the signature so future per-call hints can be added
    without changing every caller. */
void build_context(const v1::HybridRoutingContext& /*proto_ctx*/,
                   rac_hybrid_routing_context_t&   out) {
    std::memset(&out, 0, sizeof(out));
    rac_hybrid_device_state_snapshot_t snap{};
    if (rac_hybrid_get_device_state_snapshot(&snap) == RAC_SUCCESS) {
        out.is_online = snap.is_online;
        out.battery_percent = snap.battery_percent;
        // snap.thermal_throttled is captured but not yet consumed by any
        // filter; carrying it forward is a no-op until a filter reads it.
    } else {
        out.is_online = true;
        out.battery_percent = 100;
    }
}

/** Serialise a generate response into a heap buffer for the binding. */
rac_result_t build_response_bytes(const rac_llm_result_t&             result,
                                  const rac_hybrid_routed_metadata_t& meta,
                                  rac_result_t                        generate_rc,
                                  uint8_t**                           out_bytes,
                                  size_t*                             out_size) {
    v1::HybridLlmGenerateResponse msg;
    msg.set_rc(static_cast<int32_t>(generate_rc));
    msg.set_text(result.text != nullptr ? result.text : "");
    auto* routing = msg.mutable_routing();
    routing->set_chosen_model_id(meta.chosen_model_id);
    routing->set_was_fallback(meta.was_fallback);
    routing->set_attempt_count(meta.attempt_count);
    routing->set_primary_error_code(meta.primary_error_code);
    routing->set_primary_error_message(meta.primary_error_message);

    const std::string serialised = msg.SerializeAsString();
    auto* buf = static_cast<uint8_t*>(std::malloc(serialised.size()));
    if (buf == nullptr && !serialised.empty()) {
        *out_bytes = nullptr;
        *out_size = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (!serialised.empty()) {
        std::memcpy(buf, serialised.data(), serialised.size());
    }
    *out_bytes = buf;
    *out_size = serialised.size();
    return RAC_SUCCESS;
}

}  // namespace

extern "C" {

rac_result_t rac_llm_hybrid_router_set_offline_service_proto(
    rac_handle_t handle, rac_llm_service_t* service,
    const uint8_t* descriptor_bytes, size_t descriptor_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_hybrid_model_descriptor_t desc{};
    parse_descriptor(descriptor_bytes, descriptor_size, desc);
    return rac_llm_hybrid_router_set_offline_service(
        handle, service, service != nullptr ? &desc : nullptr);
}

rac_result_t rac_llm_hybrid_router_set_online_service_proto(
    rac_handle_t handle, rac_llm_service_t* service,
    const uint8_t* descriptor_bytes, size_t descriptor_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_hybrid_model_descriptor_t desc{};
    parse_descriptor(descriptor_bytes, descriptor_size, desc);
    return rac_llm_hybrid_router_set_online_service(
        handle, service, service != nullptr ? &desc : nullptr);
}

rac_result_t rac_llm_hybrid_router_set_policy_proto(
    rac_handle_t handle, const uint8_t* policy_bytes, size_t policy_size) {
    if (handle == RAC_INVALID_HANDLE) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::vector<rac_hybrid_filter_t> filters;
    rac_hybrid_routing_policy_t      policy{};
    parse_policy(policy_bytes, policy_size, filters, policy);
    return rac_llm_hybrid_router_set_policy(handle, &policy);
}

rac_result_t rac_llm_hybrid_router_generate_proto(
    rac_handle_t handle, const uint8_t* request_bytes, size_t request_size,
    uint8_t** out_response_bytes, size_t* out_response_size) {
    if (out_response_bytes == nullptr || out_response_size == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_response_bytes = nullptr;
    *out_response_size = 0;
    if (handle == RAC_INVALID_HANDLE || request_bytes == nullptr || request_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    v1::HybridLlmGenerateRequest req;
    if (!req.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return RAC_ERROR_INVALID_RESPONSE;
    }

    rac_hybrid_routing_context_t ctx{};
    build_context(req.context(), ctx);

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    const auto& opt = req.options();
    if (opt.max_tokens() > 0) {
        options.max_tokens = opt.max_tokens();
    }
    options.temperature = opt.temperature();
    options.top_p = opt.top_p();
    options.streaming_enabled = opt.streaming_enabled() ? RAC_TRUE : RAC_FALSE;
    std::string system_prompt_storage = opt.system_prompt();
    options.system_prompt =
        system_prompt_storage.empty() ? nullptr : system_prompt_storage.c_str();

    const std::string prompt = req.prompt();

    rac_llm_result_t             result{};
    rac_hybrid_routed_metadata_t meta{};
    const rac_result_t           generate_rc = rac_llm_hybrid_router_generate(
        handle, &ctx, prompt.c_str(), &options, &result, &meta);

    const rac_result_t encode_rc = build_response_bytes(
        result, meta, generate_rc, out_response_bytes, out_response_size);
    rac_llm_result_free(&result);
    if (encode_rc != RAC_SUCCESS) {
        return encode_rc;
    }
    // generate_rc is communicated to the binding via the response proto's
    // `rc` field; this function returns RAC_SUCCESS as long as we got a
    // response buffer back.
    return RAC_SUCCESS;
}

void rac_llm_hybrid_router_proto_buffer_free(uint8_t* response_bytes) {
    std::free(response_bytes);
}

}  // extern "C"

namespace {

/**
 * Per-call shim that carries the binding's stream callback + user_data
 * across the rac_llm_stream_callback_fn boundary. We can't pass a
 * binding-specific callback type through rac_llm_hybrid_router_generate_stream
 * (it accepts only rac_llm_stream_callback_fn), so we install this adapter
 * and stash the binding callback in user_data.
 */
struct StreamShim {
    rac_hybrid_stream_token_fn on_token;
    void*                      user_data;
};

rac_bool_t stream_token_adapter(const char* token, void* user_data) {
    auto* shim = static_cast<StreamShim*>(user_data);
    if (shim == nullptr || shim->on_token == nullptr) {
        return RAC_TRUE;
    }
    return shim->on_token(token, shim->user_data);
}

}  // namespace

extern "C" {

rac_result_t rac_llm_hybrid_router_generate_stream_proto(
    rac_handle_t               handle,
    const uint8_t*             request_bytes,
    size_t                     request_size,
    rac_hybrid_stream_token_fn on_token,
    rac_hybrid_stream_done_fn  on_done,
    void*                      user_data) {
    if (handle == RAC_INVALID_HANDLE || on_token == nullptr ||
        request_bytes == nullptr || request_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    v1::HybridLlmGenerateRequest req;
    if (!req.ParseFromArray(request_bytes, static_cast<int>(request_size))) {
        return RAC_ERROR_INVALID_RESPONSE;
    }

    rac_hybrid_routing_context_t ctx{};
    build_context(req.context(), ctx);

    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    const auto& opt = req.options();
    if (opt.max_tokens() > 0) {
        options.max_tokens = opt.max_tokens();
    }
    options.temperature = opt.temperature();
    options.top_p = opt.top_p();
    options.streaming_enabled = RAC_TRUE;
    std::string system_prompt_storage = opt.system_prompt();
    options.system_prompt =
        system_prompt_storage.empty() ? nullptr : system_prompt_storage.c_str();

    const std::string prompt = req.prompt();

    StreamShim shim{on_token, user_data};

    rac_hybrid_routed_metadata_t meta{};
    const rac_result_t stream_rc = rac_llm_hybrid_router_generate_stream(
        handle, &ctx, prompt.c_str(), &options, stream_token_adapter, &shim, &meta);

    if (on_done != nullptr) {
        rac_llm_result_t empty_result{};
        uint8_t* response_bytes = nullptr;
        size_t   response_size = 0;
        const rac_result_t encode_rc = build_response_bytes(
            empty_result, meta, stream_rc, &response_bytes, &response_size);
        if (encode_rc == RAC_SUCCESS) {
            on_done(stream_rc, response_bytes, response_size, user_data);
        } else {
            on_done(stream_rc, nullptr, 0, user_data);
        }
        std::free(response_bytes);
    }
    return stream_rc;
}

}  // extern "C"