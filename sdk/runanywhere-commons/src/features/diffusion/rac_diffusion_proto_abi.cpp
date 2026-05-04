/**
 * @file rac_diffusion_proto_abi.cpp
 * @brief Proto-byte C ABI for diffusion service operations.
 */

#include "rac/features/diffusion/rac_diffusion_service.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
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

bool serialize_proto(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() ||
           message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    std::vector<uint8_t> bytes;
    if (serialize_proto(event, &bytes)) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind,
                        const char* operation, float progress, const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_DIFFUSION);
    event.set_severity(error && error[0] ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                         : runanywhere::v1::EVENT_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    if (operation) cap->set_operation(operation);
    cap->set_progress(progress);
    if (error) cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED,
                       operation, 0.0f,
                       message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "diffusion", operation, RAC_TRUE);
}

void free_options(rac_diffusion_options_t* options) {
    if (!options) return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

rac_result_t parse_options(const uint8_t* bytes, size_t size,
                           rac_diffusion_options_t* out_options,
                           rac_proto_buffer_t* out_error) {
    if (!valid_bytes(bytes, size)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "Diffusion options bytes are invalid");
    }
    runanywhere::v1::DiffusionGenerationOptions proto;
    if (!proto.ParseFromArray(parse_data(bytes, size), static_cast<int>(size))) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse DiffusionGenerationOptions");
    }
    if (!rac::foundation::rac_diffusion_options_from_proto(proto, out_options)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert DiffusionGenerationOptions");
    }
    if (!out_options->prompt || out_options->prompt[0] == '\0') {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationOptions.prompt is required");
    }
    return RAC_SUCCESS;
}

struct ProgressCtx {
    rac_diffusion_progress_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
};

rac_bool_t progress_trampoline(const rac_diffusion_progress_t* progress, void* user_data) {
    auto* ctx = static_cast<ProgressCtx*>(user_data);
    if (!progress) return RAC_TRUE;

    runanywhere::v1::DiffusionProgress proto;
    if (!rac::foundation::rac_diffusion_progress_to_proto(progress, &proto)) {
        return RAC_FALSE;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS,
                       "diffusion.generate", progress->progress, nullptr);

    if (!ctx || !ctx->callback) return RAC_TRUE;
    std::vector<uint8_t> bytes;
    if (!serialize_proto(proto, &bytes)) return RAC_FALSE;
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                         ctx->user_data) == RAC_TRUE
               ? RAC_TRUE
               : RAC_FALSE;
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

rac_result_t rac_diffusion_generate_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.generate",
                        "Diffusion lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "Diffusion lifecycle component is not loaded");
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size,
                                    &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr);
    rac_diffusion_result_t result = {};
    rc = rac_diffusion_generate(handle, &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
        free_options(&options);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult proto;
    if (!rac::foundation::rac_diffusion_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode DiffusionResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
                       "diffusion.generate", 1.0f, nullptr);
    rac_diffusion_result_free(&result);
    free_options(&options);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_with_progress_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_diffusion_progress_proto_callback_fn progress_callback, void* user_data,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)options_proto_bytes;
    (void)options_proto_size;
    (void)progress_callback;
    (void)user_data;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.generate",
                        "Diffusion lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "Diffusion lifecycle component is not loaded");
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size,
                                    &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr);
    ProgressCtx ctx;
    ctx.callback = progress_callback;
    ctx.user_data = user_data;
    rac_diffusion_result_t result = {};
    rc = rac_diffusion_generate_with_progress(handle, &options, progress_trampoline,
                                              &ctx, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
        free_options(&options);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult proto;
    if (!rac::foundation::rac_diffusion_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode DiffusionResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
                       "diffusion.generate", 1.0f, nullptr);
    rac_diffusion_result_free(&result);
    free_options(&options);
    return rc;
#endif
}

rac_result_t rac_diffusion_cancel_proto(rac_handle_t handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "diffusion.cancel",
                        "Diffusion lifecycle component is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    runanywhere::v1::SDKEvent requested;
    requested.set_id(event_id());
    requested.set_timestamp_ms(now_ms());
    requested.set_category(runanywhere::v1::EVENT_CATEGORY_CANCELLATION);
    requested.set_severity(runanywhere::v1::EVENT_SEVERITY_INFO);
    requested.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    requested.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    cancel->set_operation_id("diffusion.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    rac_result_t rc = rac_diffusion_cancel(handle);
    runanywhere::v1::SDKEvent completed;
    completed.set_id(event_id());
    completed.set_timestamp_ms(now_ms());
    completed.set_category(runanywhere::v1::EVENT_CATEGORY_CANCELLATION);
    completed.set_severity(rc == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                                             : runanywhere::v1::EVENT_SEVERITY_ERROR);
    completed.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    completed.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* done = completed.mutable_cancellation();
    done->set_kind(rc == RAC_SUCCESS
                       ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                       : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    done->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    done->set_operation_id("diffusion.cancel");
    done->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    done->set_user_initiated(true);
    publish_event(completed);
    return rc;
#endif
}

}  // extern "C"
