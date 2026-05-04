/**
 * @file rac_lora_service.cpp
 * @brief Proto-byte C ABI for LoRA operations.
 */

#include "rac/features/lora/rac_lora_service.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
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

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu",
                  static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message,
                        rac_proto_buffer_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize proto result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind,
                        const char* operation, const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_LORA);
    event.set_severity(error && error[0] ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                         : runanywhere::v1::EVENT_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_LLM);
    if (operation) cap->set_operation(operation);
    if (error) cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED,
                       operation, message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "llm", operation, RAC_TRUE);
}

rac_result_t parse_config(const uint8_t* bytes, size_t size,
                          runanywhere::v1::LoRAAdapterConfig* out,
                          rac_proto_buffer_t* error_out) {
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

runanywhere::v1::LoRAAdapterInfo make_info(
    const runanywhere::v1::LoRAAdapterConfig& config, bool applied,
    const char* error_message = nullptr) {
    runanywhere::v1::LoRAAdapterInfo info;
    if (config.has_adapter_id()) info.set_adapter_id(config.adapter_id());
    info.set_adapter_path(config.adapter_path());
    info.set_scale(config.scale() > 0.0f ? config.scale() : 1.0f);
    info.set_applied(applied);
    if (error_message && error_message[0]) info.set_error_message(error_message);
    return info;
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

rac_result_t rac_lora_register_proto(rac_lora_registry_handle_t registry,
                                     const uint8_t* entry_proto_bytes,
                                     size_t entry_proto_size,
                                     rac_proto_buffer_t* out_entry) {
    if (!out_entry) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)registry;
    (void)entry_proto_bytes;
    (void)entry_proto_size;
    return feature_unavailable(out_entry);
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }
    if (!valid_bytes(entry_proto_bytes, entry_proto_size)) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_DECODING_ERROR,
                                          "LoraAdapterCatalogEntry bytes are invalid");
    }
    runanywhere::v1::LoraAdapterCatalogEntry proto;
    if (!proto.ParseFromArray(parse_data(entry_proto_bytes, entry_proto_size),
                              static_cast<int>(entry_proto_size))) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse LoraAdapterCatalogEntry");
    }
    if (proto.id().empty()) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_INVALID_ARGUMENT,
                                          "LoraAdapterCatalogEntry.id is required");
    }

    auto* entry = static_cast<rac_lora_entry_t*>(std::calloc(1, sizeof(rac_lora_entry_t)));
    if (!entry) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_OUT_OF_MEMORY,
                                          "failed to allocate LoRA entry");
    }
    if (!rac::foundation::rac_lora_entry_from_proto(proto, entry)) {
        rac_lora_entry_free(entry);
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert LoraAdapterCatalogEntry");
    }
    rac_result_t rc = rac_lora_registry_register(registry, entry);
    rac_lora_entry_free(entry);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "lora.register", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_entry, rc, rac_error_message(rc));
    }
    return copy_proto(proto, out_entry);
#endif
}

rac_result_t rac_lora_compatibility_proto(rac_handle_t llm_component,
                                          const uint8_t* config_proto_bytes,
                                          size_t config_proto_size,
                                          rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return feature_unavailable(out_result);
#else
    runanywhere::v1::LoRAAdapterConfig config;
    rac_result_t rc = parse_config(config_proto_bytes, config_proto_size, &config, out_result);
    if (rc != RAC_SUCCESS) return rc;

    runanywhere::v1::LoraCompatibilityResult result;
    char* error = nullptr;
    rc = rac_llm_component_check_lora_compat(llm_component, config.adapter_path().c_str(),
                                             &error);
    result.set_is_compatible(rc == RAC_SUCCESS);
    if (rc != RAC_SUCCESS) {
        result.set_error_message(error ? error : rac_error_message(rc));
    }
    rac_free(error);
    return copy_proto(result, out_result);
#endif
}

rac_result_t rac_lora_load_proto(rac_handle_t llm_component,
                                 const uint8_t* config_proto_bytes,
                                 size_t config_proto_size,
                                 rac_proto_buffer_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return feature_unavailable(out_info);
#else
    runanywhere::v1::LoRAAdapterConfig config;
    rac_result_t rc = parse_config(config_proto_bytes, config_proto_size, &config, out_info);
    if (rc != RAC_SUCCESS) return rc;

    const float scale = config.scale() > 0.0f ? config.scale() : 1.0f;
    rc = rac_llm_component_load_lora(llm_component, config.adapter_path().c_str(), scale);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "lora.load", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_info, rc, rac_error_message(rc));
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED,
                       "lora.load", nullptr);
    return copy_proto(make_info(config, true), out_info);
#endif
}

rac_result_t rac_lora_remove_proto(rac_handle_t llm_component,
                                   const uint8_t* config_proto_bytes,
                                   size_t config_proto_size,
                                   rac_proto_buffer_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    (void)config_proto_bytes;
    (void)config_proto_size;
    return feature_unavailable(out_info);
#else
    runanywhere::v1::LoRAAdapterConfig config;
    rac_result_t rc = parse_config(config_proto_bytes, config_proto_size, &config, out_info);
    if (rc != RAC_SUCCESS) return rc;

    rc = rac_llm_component_remove_lora(llm_component, config.adapter_path().c_str());
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "lora.remove", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_info, rc, rac_error_message(rc));
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                       "lora.remove", nullptr);
    return copy_proto(make_info(config, false), out_info);
#endif
}

rac_result_t rac_lora_clear_proto(rac_handle_t llm_component, rac_proto_buffer_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)llm_component;
    return feature_unavailable(out_info);
#else
    rac_result_t rc = rac_llm_component_clear_lora(llm_component);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "lora.clear", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_info, rc, rac_error_message(rc));
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
                       "lora.clear", nullptr);
    runanywhere::v1::LoRAAdapterInfo info;
    info.set_applied(false);
    return copy_proto(info, out_info);
#endif
}

}  // extern "C"
