/**
 * @file rac_lora_service.cpp
 * @brief Proto-byte C ABI for LoRA operations.
 */

#include "rac/features/lora/rac_lora_service.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "lora_options.pb.h"
#include "sdk_events.pb.h"
#endif

extern "C" rac_result_t rac_lora_registry_register_catalog_entry_proto(
    rac_lora_registry_handle_t registry, const uint8_t* entry_proto_bytes, size_t entry_proto_size,
    rac_proto_buffer_t* out_entry);

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return rac_proto_bytes_validate(bytes, size) == RAC_SUCCESS;
}

struct TrackedLoRAState {
    std::string base_model_id;
    std::vector<runanywhere::v1::LoRAAdapterInfo> adapters;
};

std::mutex& tracked_lora_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::map<rac_handle_t, TrackedLoRAState>& tracked_lora_states() {
    static std::map<rac_handle_t, TrackedLoRAState> states;
    return states;
}

std::string current_base_model_id(rac_handle_t llm_component) {
    const char* model_id = rac_llm_component_get_model_id(llm_component);
    return model_id ? std::string(model_id) : std::string();
}

TrackedLoRAState& ensure_tracked_lora_state_locked(rac_handle_t llm_component,
                                                   const std::string& base_model_id) {
    auto& state = tracked_lora_states()[llm_component];
    if (state.base_model_id != base_model_id) {
        state.base_model_id = base_model_id;
        state.adapters.clear();
    }
    return state;
}

TrackedLoRAState snapshot_tracked_lora_state(rac_handle_t llm_component,
                                             const std::string& base_model_id) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    return ensure_tracked_lora_state_locked(llm_component, base_model_id);
}

void forget_tracked_lora_state(rac_handle_t llm_component) {
    if (!llm_component)
        return;
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    tracked_lora_states().erase(llm_component);
}

void populate_state_from_snapshot(const TrackedLoRAState& snapshot,
                                  runanywhere::v1::LoRAState* state) {
    if (!snapshot.base_model_id.empty()) {
        state->set_base_model_id(snapshot.base_model_id);
    }
    for (const auto& adapter : snapshot.adapters) {
        *state->add_loaded_adapters() = adapter;
    }
    state->set_has_active_adapters(!snapshot.adapters.empty());
}

void populate_tracked_state(rac_handle_t llm_component, const std::string& base_model_id,
                            runanywhere::v1::LoRAState* state) {
    populate_state_from_snapshot(snapshot_tracked_lora_state(llm_component, base_model_id), state);
}

void track_lora_cleared(rac_handle_t llm_component, const std::string& base_model_id) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(llm_component, base_model_id);
    state.adapters.clear();
}

void track_lora_applied(rac_handle_t llm_component, const std::string& base_model_id,
                        const runanywhere::v1::LoRAAdapterInfo& info) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(llm_component, base_model_id);
    auto existing = std::find_if(state.adapters.begin(), state.adapters.end(),
                                 [&](const runanywhere::v1::LoRAAdapterInfo& adapter) {
                                     return adapter.adapter_path() == info.adapter_path();
                                 });
    if (existing != state.adapters.end()) {
        *existing = info;
    } else {
        state.adapters.push_back(info);
    }
}

void track_lora_removed_path(rac_handle_t llm_component, const std::string& base_model_id,
                             const std::string& adapter_path) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(llm_component, base_model_id);
    state.adapters.erase(std::remove_if(state.adapters.begin(), state.adapters.end(),
                                        [&](const runanywhere::v1::LoRAAdapterInfo& adapter) {
                                            return adapter.adapter_path() == adapter_path;
                                        }),
                         state.adapters.end());
}

rac_result_t resolve_lora_id_to_path(rac_handle_t llm_component, const std::string& base_model_id,
                                     const std::string& adapter_id, std::string* out_path,
                                     std::string* out_error) {
    if (adapter_id.empty()) {
        if (out_error)
            *out_error = "LoRARemoveRequest.adapter_ids cannot contain empty ids";
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    const auto& state = ensure_tracked_lora_state_locked(llm_component, base_model_id);
    const runanywhere::v1::LoRAAdapterInfo* match = nullptr;
    for (const auto& adapter : state.adapters) {
        if (adapter.adapter_id() != adapter_id)
            continue;
        if (match) {
            if (out_error) {
                *out_error =
                    "LoRARemoveRequest.adapter_ids is ambiguous for duplicate active adapter id";
            }
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        match = &adapter;
    }

    if (!match) {
        if (out_error) {
            *out_error = "LoRARemoveRequest.adapter_ids contains an adapter id that is not active";
        }
        return RAC_ERROR_NOT_FOUND;
    }
    if (out_path)
        *out_path = match->adapter_path();
    return RAC_SUCCESS;
}

void add_unique_path(std::vector<std::string>* paths, const std::string& path) {
    if (std::find(paths->begin(), paths->end(), path) == paths->end()) {
        paths->push_back(path);
    }
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_LORA);
    event.set_severity(error && error[0] ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                         : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    if (error)
        cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED, operation,
                       message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "llm", operation, RAC_TRUE);
}

rac_result_t parse_config(const uint8_t* bytes, size_t size,
                          runanywhere::v1::LoRAAdapterConfig* out, rac_proto_buffer_t* error_out) {
    if (!valid_bytes(bytes, size)) {
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR,
                                          "LoRAAdapterConfig bytes are invalid");
    }
    if (!out->ParseFromArray(parse_data(bytes, size), static_cast<int>(size))) {
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse LoRAAdapterConfig");
    }
    if (out->adapter_path().empty()) {
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_INVALID_ARGUMENT,
                                          "LoRAAdapterConfig.adapter_path is required");
    }
    return RAC_SUCCESS;
}

template <class Message>
rac_result_t parse_message(const uint8_t* bytes, size_t size, Message* out,
                           const char* message_name, rac_proto_buffer_t* error_out) {
    if (!valid_bytes(bytes, size)) {
        std::string message = std::string(message_name) + " bytes are invalid";
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR, message.c_str());
    }
    if (!out->ParseFromArray(parse_data(bytes, size), static_cast<int>(size))) {
        std::string message = std::string("failed to parse ") + message_name;
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR, message.c_str());
    }
    return RAC_SUCCESS;
}

runanywhere::v1::LoRAAdapterInfo make_info(const runanywhere::v1::LoRAAdapterConfig& config,
                                           bool applied, const char* error_message = nullptr,
                                           rac_result_t error_code = RAC_SUCCESS) {
    runanywhere::v1::LoRAAdapterInfo info;
    if (config.has_adapter_id())
        info.set_adapter_id(config.adapter_id());
    info.set_adapter_path(config.adapter_path());
    info.set_scale(config.scale() > 0.0f ? config.scale() : 1.0f);
    info.set_applied(applied);
    info.set_error_code(static_cast<int32_t>(error_code));
    if (applied)
        info.set_loaded_at_ms(now_ms());
    if (error_message && error_message[0])
        info.set_error_message(error_message);
    return info;
}

void mark_apply_error(runanywhere::v1::LoRAApplyResult* result, rac_result_t code,
                      const char* message) {
    result->set_success(false);
    result->set_error_code(static_cast<int32_t>(code));
    result->set_error_message(message && message[0] ? message : rac_error_message(code));
}

void mark_state_error(runanywhere::v1::LoRAState* state, rac_result_t code, const char* message) {
    state->set_error_code(static_cast<int32_t>(code));
    state->set_error_message(message && message[0] ? message : rac_error_message(code));
}

bool lora_service_loaded(rac_handle_t llm_component) {
    return llm_component && rac_llm_component_is_loaded(llm_component) == RAC_TRUE;
}

const char* no_service_message() {
    return "LoRA service is not loaded; load an LLM model before calling generated LoRA service "
           "operations";
}

#endif  // RAC_HAVE_PROTOBUF

#if !defined(RAC_HAVE_PROTOBUF)
rac_result_t feature_unavailable(rac_proto_buffer_t* out) {
    if (out) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                          "protobuf support is not available");
    }
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}
#endif

}  // namespace

extern "C" {

void rac_lora_forget_component_state(rac_handle_t llm_component) {
#if defined(RAC_HAVE_PROTOBUF)
    forget_tracked_lora_state(llm_component);
#else
    (void)llm_component;
#endif
}

rac_result_t rac_lora_register_proto(rac_lora_registry_handle_t registry,
                                     const uint8_t* entry_proto_bytes, size_t entry_proto_size,
                                     rac_proto_buffer_t* out_entry) {
    return rac_lora_registry_register_catalog_entry_proto(registry, entry_proto_bytes,
                                                          entry_proto_size, out_entry);
}

rac_result_t rac_lora_compatibility_proto(rac_handle_t llm_component,
                                          const uint8_t* config_proto_bytes,
                                          size_t config_proto_size,
                                          rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::LoRAAdapterConfig config;
    rac_result_t rc = parse_config(config_proto_bytes, config_proto_size, &config, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    runanywhere::v1::LoraCompatibilityResult result;
    char* error = nullptr;
    rc = rac_llm_component_check_lora_compat(llm_component, config.adapter_path().c_str(), &error);
    result.set_is_compatible(rc == RAC_SUCCESS);
    if (rc != RAC_SUCCESS) {
        result.set_error_message(error ? error : rac_error_message(rc));
        result.set_error_code(static_cast<int32_t>(rc));
    }
    rac_free(error);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_lora_apply_proto(rac_handle_t llm_component, const uint8_t* request_proto_bytes,
                                  size_t request_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::LoRAApplyRequest request;
    rac_result_t rc = parse_message(request_proto_bytes, request_proto_size, &request,
                                    "LoRAApplyRequest", out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    runanywhere::v1::LoRAApplyResult result;
    result.set_request_id(request.request_id());

    if (!lora_service_loaded(llm_component)) {
        forget_tracked_lora_state(llm_component);
        mark_apply_error(&result, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.apply", no_service_message());
        return copy_proto(result, out_result);
    }
    const std::string base_model_id = current_base_model_id(llm_component);

    if (request.adapters_size() == 0) {
        mark_apply_error(&result, RAC_ERROR_INVALID_ARGUMENT,
                         "LoRAApplyRequest.adapters is required");
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.apply",
                        "LoRAApplyRequest.adapters is required");
        return copy_proto(result, out_result);
    }

    if (request.replace_existing()) {
        rc = rac_llm_component_clear_lora(llm_component);
        if (rc != RAC_SUCCESS) {
            mark_apply_error(&result, rc, rac_error_message(rc));
            publish_failure(rc, "lora.apply", rac_error_message(rc));
            return copy_proto(result, out_result);
        }
        track_lora_cleared(llm_component, base_model_id);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.apply.replaceExisting", nullptr);
    }

    for (const auto& config : request.adapters()) {
        if (config.adapter_path().empty()) {
            auto* info = result.add_adapters();
            *info = make_info(config, false, "LoRAAdapterConfig.adapter_path is required",
                              RAC_ERROR_INVALID_ARGUMENT);
            mark_apply_error(&result, RAC_ERROR_INVALID_ARGUMENT,
                             "LoRAAdapterConfig.adapter_path is required");
            publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.apply",
                            "LoRAAdapterConfig.adapter_path is required");
            return copy_proto(result, out_result);
        }

        const float scale = config.scale() > 0.0f ? config.scale() : 1.0f;
        rc = rac_llm_component_load_lora(llm_component, config.adapter_path().c_str(), scale);
        if (rc != RAC_SUCCESS) {
            auto* info = result.add_adapters();
            *info = make_info(config, false, rac_error_message(rc), rc);
            mark_apply_error(&result, rc, rac_error_message(rc));
            publish_failure(rc, "lora.apply", rac_error_message(rc));
            return copy_proto(result, out_result);
        }

        runanywhere::v1::LoRAAdapterInfo applied_info = make_info(config, true);
        track_lora_applied(llm_component, base_model_id, applied_info);
        auto* info = result.add_adapters();
        *info = applied_info;
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED,
                           "lora.apply", nullptr);
    }

    result.set_success(true);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_lora_remove_proto(rac_handle_t llm_component, const uint8_t* request_proto_bytes,
                                   size_t request_proto_size, rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_state);
#else
    runanywhere::v1::LoRARemoveRequest request;
    rac_result_t rc = parse_message(request_proto_bytes, request_proto_size, &request,
                                    "LoRARemoveRequest", out_state);
    if (rc != RAC_SUCCESS)
        return rc;

    runanywhere::v1::LoRAState state;
    if (!lora_service_loaded(llm_component)) {
        forget_tracked_lora_state(llm_component);
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.remove", no_service_message());
        return copy_proto(state, out_state);
    }
    const std::string base_model_id = current_base_model_id(llm_component);

    if (request.clear_all()) {
        rc = rac_llm_component_clear_lora(llm_component);
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(llm_component, base_model_id, &state);
            mark_state_error(&state, rc, rac_error_message(rc));
            publish_failure(rc, "lora.remove", rac_error_message(rc));
            return copy_proto(state, out_state);
        }
        track_lora_cleared(llm_component, base_model_id);
        populate_tracked_state(llm_component, base_model_id, &state);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.remove", nullptr);
        return copy_proto(state, out_state);
    }

    std::vector<std::string> paths;
    for (const auto& adapter_id : request.adapter_ids()) {
        std::string path;
        std::string error;
        rc = resolve_lora_id_to_path(llm_component, base_model_id, adapter_id, &path, &error);
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(llm_component, base_model_id, &state);
            mark_state_error(&state, rc, error.c_str());
            publish_failure(rc, "lora.remove", error.c_str());
            return copy_proto(state, out_state);
        }
        add_unique_path(&paths, path);
    }

    for (const auto& adapter_path : request.adapter_paths()) {
        if (adapter_path.empty()) {
            const char* message = "LoRARemoveRequest.adapter_paths cannot contain empty paths";
            populate_tracked_state(llm_component, base_model_id, &state);
            mark_state_error(&state, RAC_ERROR_INVALID_ARGUMENT, message);
            publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.remove", message);
            return copy_proto(state, out_state);
        }
        add_unique_path(&paths, adapter_path);
    }

    if (paths.empty()) {
        const char* message =
            "LoRARemoveRequest.clear_all, adapter_ids, or adapter_paths is required";
        populate_tracked_state(llm_component, base_model_id, &state);
        mark_state_error(&state, RAC_ERROR_INVALID_ARGUMENT, message);
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.remove", message);
        return copy_proto(state, out_state);
    }

    for (const auto& adapter_path : paths) {
        rc = rac_llm_component_remove_lora(llm_component, adapter_path.c_str());
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(llm_component, base_model_id, &state);
            mark_state_error(&state, rc, rac_error_message(rc));
            publish_failure(rc, "lora.remove", rac_error_message(rc));
            return copy_proto(state, out_state);
        }
        track_lora_removed_path(llm_component, base_model_id, adapter_path);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.remove", nullptr);
    }

    populate_tracked_state(llm_component, base_model_id, &state);
    return copy_proto(state, out_state);
#endif
}

rac_result_t rac_lora_list_proto(rac_handle_t llm_component, const uint8_t* state_proto_bytes,
                                 size_t state_proto_size, rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)state_proto_bytes;
    (void)state_proto_size;
    return feature_unavailable(out_state);
#else
    runanywhere::v1::LoRAState request;
    rac_result_t rc =
        parse_message(state_proto_bytes, state_proto_size, &request, "LoRAState", out_state);
    if (rc != RAC_SUCCESS)
        return rc;
    (void)request;

    runanywhere::v1::LoRAState state;
    if (!lora_service_loaded(llm_component)) {
        forget_tracked_lora_state(llm_component);
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.list", no_service_message());
        return copy_proto(state, out_state);
    }
    const std::string base_model_id = current_base_model_id(llm_component);
    populate_tracked_state(llm_component, base_model_id, &state);
    return copy_proto(state, out_state);
#endif
}

rac_result_t rac_lora_state_proto(rac_handle_t llm_component, const uint8_t* state_proto_bytes,
                                  size_t state_proto_size, rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)state_proto_bytes;
    (void)state_proto_size;
    return feature_unavailable(out_state);
#else
    runanywhere::v1::LoRAState request;
    rac_result_t rc =
        parse_message(state_proto_bytes, state_proto_size, &request, "LoRAState", out_state);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    (void)request;

    runanywhere::v1::LoRAState state;
    if (!lora_service_loaded(llm_component)) {
        forget_tracked_lora_state(llm_component);
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.state", no_service_message());
        return copy_proto(state, out_state);
    }
    const std::string base_model_id = current_base_model_id(llm_component);
    populate_tracked_state(llm_component, base_model_id, &state);
    return copy_proto(state, out_state);
#endif
}

}  // extern "C"
