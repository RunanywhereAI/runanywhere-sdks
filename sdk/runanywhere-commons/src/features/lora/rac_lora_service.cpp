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
#include <cstring>
#include <fstream>
#include <map>
#include <mutex>
#include <ranges>
#include <string>
#include <utility>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "lora_options.pb.h"
#include "sdk_events.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
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

// Per-backend tracked LoRA state. The key is the lifecycle backend instance
// pointer (rac::llm::LifecycleLlmRef::impl) — stable for the lifetime of a
// loaded model and freed when the lifecycle service unloads. Reusing the same
// map for legacy callers via `rac_lora_forget_component_state(handle)` is safe
// because both keys are `void*` and addresses never collide while the
// underlying object is alive.
std::mutex& tracked_lora_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::map<void*, TrackedLoRAState>& tracked_lora_states() {
    static std::map<void*, TrackedLoRAState> states;
    return states;
}

TrackedLoRAState& ensure_tracked_lora_state_locked(void* backend_impl,
                                                   const std::string& base_model_id) {
    auto& state = tracked_lora_states()[backend_impl];
    if (state.base_model_id != base_model_id) {
        state.base_model_id = base_model_id;
        state.adapters.clear();
    }
    return state;
}

TrackedLoRAState snapshot_tracked_lora_state(void* backend_impl, const std::string& base_model_id) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    return ensure_tracked_lora_state_locked(backend_impl, base_model_id);
}

void forget_tracked_lora_state(void* backend_impl) {
    if (!backend_impl)
        return;
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    tracked_lora_states().erase(backend_impl);
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

void populate_tracked_state(void* backend_impl, const std::string& base_model_id,
                            runanywhere::v1::LoRAState* state) {
    populate_state_from_snapshot(snapshot_tracked_lora_state(backend_impl, base_model_id), state);
}

void track_lora_cleared(void* backend_impl, const std::string& base_model_id) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(backend_impl, base_model_id);
    state.adapters.clear();
}

void track_lora_applied(void* backend_impl, const std::string& base_model_id,
                        const runanywhere::v1::LoRAAdapterInfo& info) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(backend_impl, base_model_id);
    auto existing =
        std::ranges::find_if(state.adapters, [&](const runanywhere::v1::LoRAAdapterInfo& adapter) {
            return adapter.adapter_path() == info.adapter_path();
        });
    if (existing != state.adapters.end()) {
        *existing = info;
    } else {
        state.adapters.push_back(info);
    }
}

void track_lora_removed_path(void* backend_impl, const std::string& base_model_id,
                             const std::string& adapter_path) {
    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    auto& state = ensure_tracked_lora_state_locked(backend_impl, base_model_id);
    state.adapters.erase(
        std::ranges::remove_if(state.adapters,
                               [&](const runanywhere::v1::LoRAAdapterInfo& adapter) {
                                   return adapter.adapter_path() == adapter_path;
                               })
            .begin(),
        state.adapters.end());
}

rac_result_t resolve_lora_id_to_path(void* backend_impl, const std::string& base_model_id,
                                     const std::string& adapter_id, std::string* out_path,
                                     std::string* out_error) {
    if (adapter_id.empty()) {
        if (out_error)
            *out_error = "LoRARemoveRequest.adapter_ids cannot contain empty ids";
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(tracked_lora_mutex());
    const auto& state = ensure_tracked_lora_state_locked(backend_impl, base_model_id);
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
    if (std::ranges::find(*paths, path) == paths->end()) {
        paths->push_back(path);
    }
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the events layer so LoRA telemetry reaches the telemetry +
    // log sinks per the destination bitmask, not just the public proto stream.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        const char* error, const char* model_id = nullptr,
                        const char* adapter_id = nullptr, int64_t adapter_size_bytes = 0) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_LORA);
    event.set_severity((error != nullptr) && error[0] != '\0'
                           ? runanywhere::v1::ERROR_SEVERITY_ERROR
                           : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);  // base model — telemetry "base_model_id"
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    if (error)
        cap->set_error(error);
    if (adapter_id != nullptr && adapter_id[0] != '\0') {
        (*event.mutable_properties())["adapter_id"] = adapter_id;
    }
    if (adapter_size_bytes > 0) {
        (*event.mutable_properties())["adapter_size_bytes"] = std::to_string(adapter_size_bytes);
    }
    publish_event(event);
}

// Adapter file size for telemetry — read via ifstream (portable; no
// <filesystem> dependency). Best-effort: 0 if the path can't be opened.
int64_t adapter_file_size(const std::string& path) {
    if (path.empty())
        return 0;
    std::ifstream sz(path, std::ios::binary | std::ios::ate);
    return sz ? static_cast<int64_t>(sz.tellg()) : 0;
}

// adapter_id for telemetry attribution: prefer the catalog-linked id, else fall
// back to the adapter file's basename (without directory or .gguf extension) so
// the field is never blank when only a raw path was supplied.
std::string adapter_id_for(const runanywhere::v1::LoRAAdapterConfig& config) {
    if (!config.adapter_id().empty())
        return config.adapter_id();
    const std::string& path = config.adapter_path();
    if (path.empty())
        return std::string();
    size_t slash = path.find_last_of("/\\");
    std::string base = (slash == std::string::npos) ? path : path.substr(slash + 1);
    const std::string ext = ".gguf";
    if (base.size() > ext.size() && base.compare(base.size() - ext.size(), ext.size(), ext) == 0) {
        base.resize(base.size() - ext.size());
    }
    return base;
}

void publish_failure(rac_result_t code, const char* operation, const char* message,
                     const char* model_id = nullptr, const char* adapter_id = nullptr,
                     int64_t adapter_size_bytes = 0) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED, operation,
                       (message != nullptr) && message[0] != '\0' ? message
                                                                  : rac_error_message(code),
                       model_id, adapter_id, adapter_size_bytes);
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
    if ((error_message != nullptr) && error_message[0] != '\0')
        info.set_error_message(error_message);
    return info;
}

void mark_apply_error(runanywhere::v1::LoRAApplyResult* result, rac_result_t code,
                      const char* message) {
    result->set_success(false);
    result->set_error_code(static_cast<int32_t>(code));
    result->set_error_message((message != nullptr) && message[0] != '\0' ? message
                                                                         : rac_error_message(code));
}

void mark_state_error(runanywhere::v1::LoRAState* state, rac_result_t code, const char* message) {
    state->set_error_code(static_cast<int32_t>(code));
    state->set_error_message((message != nullptr) && message[0] != '\0' ? message
                                                                        : rac_error_message(code));
}

const char* no_service_message() {
    return "LoRA service is not loaded; load an LLM model before calling generated LoRA service "
           "operations";
}

// Acquire the lifecycle-owned LLM backend. On the not-loaded path the caller
// receives a typed COMPONENT_NOT_READY error so it can surface the failure on
// the result message instead of leaking the raw lifecycle error code.
rac_result_t acquire_lifecycle_llm_for_lora(rac::llm::LifecycleLlmRef* out_ref) {
    const rac_result_t rc = rac::llm::acquire_lifecycle_llm(out_ref);
    if (rc == RAC_SUCCESS) {
        return RAC_SUCCESS;
    }
    if (rc == RAC_ERROR_NOT_INITIALIZED || rc == RAC_ERROR_NOT_SUPPORTED) {
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    return rc;
}

struct LoraConfigValidation {
    rac_result_t code{RAC_SUCCESS};
    std::string message;
    std::string required_model;

    bool ok() const { return code == RAC_SUCCESS; }
};

LoraConfigValidation lora_validation_error(rac_result_t code, std::string message,
                                           std::string required_model = {}) {
    LoraConfigValidation validation;
    validation.code = code;
    validation.message = std::move(message);
    validation.required_model = std::move(required_model);
    return validation;
}

std::string base_model_id_for_message(const rac::llm::LifecycleLlmRef& ref) {
    return (ref.model_id != nullptr && ref.model_id[0] != '\0') ? ref.model_id : "<unknown>";
}

bool config_has_adapter_id(const runanywhere::v1::LoRAAdapterConfig& config) {
    return config.has_adapter_id() && !config.adapter_id().empty();
}

bool catalog_entry_supports_model(const rac_lora_entry_t* entry, const std::string& model_id) {
    if (!entry || model_id.empty() || !entry->compatible_model_ids) {
        return false;
    }
    for (size_t i = 0; i < entry->compatible_model_count; ++i) {
        const char* compatible_id = entry->compatible_model_ids[i];
        if (compatible_id && model_id == compatible_id) {
            return true;
        }
    }
    return false;
}

std::string first_compatible_model_id(const rac_lora_entry_t* entry) {
    if (!entry || !entry->compatible_model_ids) {
        return {};
    }
    for (size_t i = 0; i < entry->compatible_model_count; ++i) {
        const char* compatible_id = entry->compatible_model_ids[i];
        if (compatible_id && compatible_id[0] != '\0') {
            return compatible_id;
        }
    }
    return {};
}

LoraConfigValidation
validate_lora_config_for_loaded_model(const rac::llm::LifecycleLlmRef& ref,
                                      const runanywhere::v1::LoRAAdapterConfig& config) {
    if (config.adapter_path().empty()) {
        return lora_validation_error(RAC_ERROR_INVALID_ARGUMENT,
                                     "LoRAAdapterConfig.adapter_path is required");
    }
    if (!ref.supports_lora) {
        return lora_validation_error(RAC_ERROR_NOT_SUPPORTED,
                                     "Loaded model '" + base_model_id_for_message(ref) +
                                         "' does not declare LoRA support");
    }
    if (!ref.ops || !ref.ops->load_lora) {
        return lora_validation_error(RAC_ERROR_NOT_SUPPORTED,
                                     "Backend does not support LoRA adapters");
    }
    if (!config_has_adapter_id(config)) {
        return {};
    }

    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    rac_lora_entry_t* entry = nullptr;
    const rac_result_t rc = rac_lora_registry_get(registry, config.adapter_id().c_str(), &entry);
    if (rc != RAC_SUCCESS) {
        return lora_validation_error(rc == RAC_ERROR_NOT_FOUND ? RAC_ERROR_NOT_FOUND : rc,
                                     "LoRA adapter '" + config.adapter_id() +
                                         "' is not registered in the catalog");
    }

    const std::string base_model_id =
        (ref.model_id != nullptr && ref.model_id[0] != '\0') ? ref.model_id : std::string();
    const std::string required_model = first_compatible_model_id(entry);
    const bool is_compatible = catalog_entry_supports_model(entry, base_model_id);
    rac_lora_entry_free(entry);

    if (!is_compatible) {
        return lora_validation_error(RAC_ERROR_INVALID_ARGUMENT,
                                     "LoRA adapter '" + config.adapter_id() +
                                         "' is not compatible with loaded model '" +
                                         base_model_id_for_message(ref) + "'",
                                     required_model);
    }

    return {};
}

void populate_compatibility_error(runanywhere::v1::LoraCompatibilityResult* result,
                                  const LoraConfigValidation& validation) {
    result->set_is_compatible(false);
    result->set_error_code(static_cast<int32_t>(validation.code));
    result->set_error_message(validation.message);
    if (!validation.required_model.empty()) {
        result->set_base_model_required(validation.required_model);
    }
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
    // Legacy entry point: best-effort cleanup of tracked LoRA state keyed by
    // the supplied handle. After the lifecycle refactor the proto ABIs key
    // state on the lifecycle backend impl pointer, so this only fires for
    // legacy llm_component callers whose handles still happen to match a
    // tracked entry. Safe to call unconditionally.
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

rac_result_t rac_lora_compatibility_proto(const uint8_t* config_proto_bytes,
                                          size_t config_proto_size,
                                          rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)config_proto_bytes;
    (void)config_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::LoRAAdapterConfig config;
    rac_result_t rc = parse_config(config_proto_bytes, config_proto_size, &config, out_result);
    if (rc != RAC_SUCCESS)
        return rc;

    runanywhere::v1::LoraCompatibilityResult result;

    rac::llm::LifecycleLlmRef ref;
    rc = acquire_lifecycle_llm_for_lora(&ref);
    if (rc != RAC_SUCCESS) {
        result.set_is_compatible(false);
        result.set_error_message(no_service_message());
        result.set_error_code(static_cast<int32_t>(RAC_ERROR_COMPONENT_NOT_READY));
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.compatibility", no_service_message());
        return copy_proto(result, out_result);
    }

    const LoraConfigValidation validation = validate_lora_config_for_loaded_model(ref, config);
    if (!validation.ok()) {
        populate_compatibility_error(&result, validation);
        rac::llm::release_lifecycle_llm(&ref);
        return copy_proto(result, out_result);
    }

    {
        std::ifstream file(config.adapter_path(), std::ios::binary);
        if (!file.is_open()) {
            result.set_is_compatible(false);
            result.set_error_message("Adapter file not found");
            result.set_error_code(static_cast<int32_t>(RAC_ERROR_INVALID_ARGUMENT));
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }
        uint32_t magic = 0;
        file.read(reinterpret_cast<char*>(&magic), sizeof(magic));
        if (!file || magic != 0x46554747u) {  // "GGUF" in little-endian
            result.set_is_compatible(false);
            result.set_error_message("Adapter file is not a valid GGUF file");
            result.set_error_code(static_cast<int32_t>(RAC_ERROR_INVALID_ARGUMENT));
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }
    }

    result.set_is_compatible(true);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_lora_apply_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                  rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
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

    rac::llm::LifecycleLlmRef ref;
    rc = acquire_lifecycle_llm_for_lora(&ref);
    if (rc != RAC_SUCCESS) {
        mark_apply_error(&result, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.apply", no_service_message());
        return copy_proto(result, out_result);
    }

    void* const backend_impl = ref.impl;
    const std::string base_model_id = (ref.model_id != nullptr) ? ref.model_id : std::string();

    if (request.adapters_size() == 0) {
        mark_apply_error(&result, RAC_ERROR_INVALID_ARGUMENT,
                         "LoRAApplyRequest.adapters is required");
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.apply",
                        "LoRAApplyRequest.adapters is required", base_model_id.c_str());
        rac::llm::release_lifecycle_llm(&ref);
        return copy_proto(result, out_result);
    }

    for (const auto& config : request.adapters()) {
        const LoraConfigValidation validation = validate_lora_config_for_loaded_model(ref, config);
        if (!validation.ok()) {
            auto* info = result.add_adapters();
            *info = make_info(config, false, validation.message.c_str(), validation.code);
            mark_apply_error(&result, validation.code, validation.message.c_str());
            publish_failure(validation.code, "lora.apply", validation.message.c_str(),
                            base_model_id.c_str(), adapter_id_for(config).c_str(),
                            adapter_file_size(config.adapter_path()));
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }
    }

    if (request.replace_existing()) {
        if (!ref.ops->clear_lora) {
            mark_apply_error(&result, RAC_ERROR_NOT_SUPPORTED,
                             "Backend does not support LoRA clear");
            publish_failure(RAC_ERROR_NOT_SUPPORTED, "lora.apply",
                            "Backend does not support LoRA clear", base_model_id.c_str());
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }
        rc = ref.ops->clear_lora(ref.impl);
        if (rc != RAC_SUCCESS) {
            mark_apply_error(&result, rc, rac_error_message(rc));
            publish_failure(rc, "lora.apply", rac_error_message(rc), base_model_id.c_str());
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }
        track_lora_cleared(backend_impl, base_model_id);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.apply.replaceExisting", nullptr, base_model_id.c_str());
    }

    for (const auto& config : request.adapters()) {
        const float scale = config.scale() > 0.0f ? config.scale() : 1.0f;
        rc = ref.ops->load_lora(ref.impl, config.adapter_path().c_str(), scale);
        if (rc != RAC_SUCCESS) {
            auto* info = result.add_adapters();
            *info = make_info(config, false, rac_error_message(rc), rc);
            mark_apply_error(&result, rc, rac_error_message(rc));
            publish_failure(rc, "lora.apply", rac_error_message(rc), base_model_id.c_str(),
                            adapter_id_for(config).c_str(),
                            adapter_file_size(config.adapter_path()));
            rac::llm::release_lifecycle_llm(&ref);
            return copy_proto(result, out_result);
        }

        runanywhere::v1::LoRAAdapterInfo applied_info = make_info(config, true);
        track_lora_applied(backend_impl, base_model_id, applied_info);
        auto* info = result.add_adapters();
        *info = applied_info;
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED,
                           "lora.apply", nullptr, base_model_id.c_str(),
                           adapter_id_for(config).c_str(),
                           adapter_file_size(config.adapter_path()));
    }

    result.set_success(true);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_lora_remove_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                   rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
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

    rac::llm::LifecycleLlmRef ref;
    rc = acquire_lifecycle_llm_for_lora(&ref);
    if (rc != RAC_SUCCESS) {
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.remove", no_service_message());
        return copy_proto(state, out_state);
    }

    void* const backend_impl = ref.impl;
    const std::string base_model_id = (ref.model_id != nullptr) ? ref.model_id : std::string();

    auto finish = [&](rac_result_t copy_rc) {
        rac::llm::release_lifecycle_llm(&ref);
        return copy_rc;
    };

    if (request.clear_all()) {
        if (!ref.ops || !ref.ops->clear_lora) {
            populate_tracked_state(backend_impl, base_model_id, &state);
            mark_state_error(&state, RAC_ERROR_NOT_SUPPORTED,
                             "Backend does not support LoRA clear");
            publish_failure(RAC_ERROR_NOT_SUPPORTED, "lora.remove",
                            "Backend does not support LoRA clear");
            return finish(copy_proto(state, out_state));
        }
        rc = ref.ops->clear_lora(ref.impl);
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(backend_impl, base_model_id, &state);
            mark_state_error(&state, rc, rac_error_message(rc));
            publish_failure(rc, "lora.remove", rac_error_message(rc));
            return finish(copy_proto(state, out_state));
        }
        track_lora_cleared(backend_impl, base_model_id);
        populate_tracked_state(backend_impl, base_model_id, &state);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.remove", nullptr, base_model_id.c_str());
        return finish(copy_proto(state, out_state));
    }

    std::vector<std::string> paths;
    for (const auto& adapter_id : request.adapter_ids()) {
        std::string path;
        std::string error;
        rc = resolve_lora_id_to_path(backend_impl, base_model_id, adapter_id, &path, &error);
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(backend_impl, base_model_id, &state);
            mark_state_error(&state, rc, error.c_str());
            publish_failure(rc, "lora.remove", error.c_str());
            return finish(copy_proto(state, out_state));
        }
        add_unique_path(&paths, path);
    }

    for (const auto& adapter_path : request.adapter_paths()) {
        if (adapter_path.empty()) {
            const char* message = "LoRARemoveRequest.adapter_paths cannot contain empty paths";
            populate_tracked_state(backend_impl, base_model_id, &state);
            mark_state_error(&state, RAC_ERROR_INVALID_ARGUMENT, message);
            publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.remove", message);
            return finish(copy_proto(state, out_state));
        }
        add_unique_path(&paths, adapter_path);
    }

    if (paths.empty()) {
        const char* message =
            "LoRARemoveRequest.clear_all, adapter_ids, or adapter_paths is required";
        populate_tracked_state(backend_impl, base_model_id, &state);
        mark_state_error(&state, RAC_ERROR_INVALID_ARGUMENT, message);
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "lora.remove", message);
        return finish(copy_proto(state, out_state));
    }

    if (!ref.ops || !ref.ops->remove_lora) {
        populate_tracked_state(backend_impl, base_model_id, &state);
        mark_state_error(&state, RAC_ERROR_NOT_SUPPORTED, "Backend does not support LoRA remove");
        publish_failure(RAC_ERROR_NOT_SUPPORTED, "lora.remove",
                        "Backend does not support LoRA remove");
        return finish(copy_proto(state, out_state));
    }

    for (const auto& adapter_path : paths) {
        rc = ref.ops->remove_lora(ref.impl, adapter_path.c_str());
        if (rc != RAC_SUCCESS) {
            populate_tracked_state(backend_impl, base_model_id, &state);
            mark_state_error(&state, rc, rac_error_message(rc));
            publish_failure(rc, "lora.remove", rac_error_message(rc));
            return finish(copy_proto(state, out_state));
        }
        track_lora_removed_path(backend_impl, base_model_id, adapter_path);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                           "lora.remove", nullptr, base_model_id.c_str());
    }

    populate_tracked_state(backend_impl, base_model_id, &state);
    return finish(copy_proto(state, out_state));
#endif
}

rac_result_t rac_lora_list_proto(const uint8_t* state_proto_bytes, size_t state_proto_size,
                                 rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
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

    rac::llm::LifecycleLlmRef ref;
    rc = acquire_lifecycle_llm_for_lora(&ref);
    if (rc != RAC_SUCCESS) {
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.list", no_service_message());
        return copy_proto(state, out_state);
    }
    const std::string base_model_id = (ref.model_id != nullptr) ? ref.model_id : std::string();
    populate_tracked_state(ref.impl, base_model_id, &state);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(state, out_state);
#endif
}

rac_result_t rac_lora_state_proto(const uint8_t* state_proto_bytes, size_t state_proto_size,
                                  rac_proto_buffer_t* out_state) {
    if (!out_state)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
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

    rac::llm::LifecycleLlmRef ref;
    rc = acquire_lifecycle_llm_for_lora(&ref);
    if (rc != RAC_SUCCESS) {
        mark_state_error(&state, RAC_ERROR_COMPONENT_NOT_READY, no_service_message());
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "lora.state", no_service_message());
        return copy_proto(state, out_state);
    }
    const std::string base_model_id = (ref.model_id != nullptr) ? ref.model_id : std::string();
    populate_tracked_state(ref.impl, base_model_id, &state);
    rac::llm::release_lifecycle_llm(&ref);
    return copy_proto(state, out_state);
#endif
}

}  // extern "C"
