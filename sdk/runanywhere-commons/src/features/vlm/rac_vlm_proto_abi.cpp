/**
 * @file rac_vlm_proto_abi.cpp
 * @brief Proto-byte C ABI for VLM service operations.
 */

#include "rac/features/vlm/rac_vlm_service.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "vlm_options.pb.h"
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

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
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

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_envelope(runanywhere::v1::SDKEvent* event,
                       runanywhere::v1::EventSeverity severity) {
    event->set_id(event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(runanywhere::v1::EVENT_CATEGORY_VLM);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
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
                        const char* operation, float progress, int64_t input_count,
                        int64_t output_count, const char* error) {
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, error && error[0] ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                                : runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    if (operation) cap->set_operation(operation);
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error) cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED,
                       operation, 0.0f, 0, 0,
                       message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "vlm", operation, RAC_TRUE);
}

void free_vlm_image(rac_vlm_image_t* image) {
    if (!image) return;
    rac_free(const_cast<char*>(image->file_path));
    rac_free(const_cast<uint8_t*>(image->pixel_data));
    rac_free(const_cast<char*>(image->base64_data));
    std::memset(image, 0, sizeof(*image));
}

rac_result_t parse_vlm_request(const uint8_t* image_bytes, size_t image_size,
                               const uint8_t* options_bytes, size_t options_size,
                               rac_vlm_image_t* out_image, rac_vlm_options_t* out_options,
                               const char** out_prompt, rac_proto_buffer_t* out_error) {
    if (!valid_bytes(image_bytes, image_size) || !valid_bytes(options_bytes, options_size)) {
        return parse_error(out_error, "VLM proto input bytes are invalid");
    }

    runanywhere::v1::VLMImage image_proto;
    if (!image_proto.ParseFromArray(parse_data(image_bytes, image_size),
                                    static_cast<int>(image_size))) {
        return parse_error(out_error, "failed to parse VLMImage");
    }

    runanywhere::v1::VLMGenerationOptions options_proto;
    if (!options_proto.ParseFromArray(parse_data(options_bytes, options_size),
                                      static_cast<int>(options_size))) {
        return parse_error(out_error, "failed to parse VLMGenerationOptions");
    }

    if (!rac::foundation::rac_vlm_image_from_proto(image_proto, out_image) ||
        !rac::foundation::rac_vlm_options_from_proto(options_proto, out_options,
                                                     out_prompt)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert VLM request");
    }
    if (!*out_prompt || (*out_prompt)[0] == '\0') {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMGenerationOptions.prompt is required");
    }
    if (!out_image->file_path && !out_image->pixel_data && !out_image->base64_data) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_INVALID_ARGUMENT,
                                          "VLMImage source is required");
    }
    return RAC_SUCCESS;
}

struct StreamCtx {
    rac_vlm_stream_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
    std::string text;
    int32_t token_count{0};
};

bool serialize_event(const runanywhere::v1::SDKEvent& event, std::vector<uint8_t>* out) {
    out->resize(event.ByteSizeLong());
    return out->empty() ||
           event.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_bool_t stream_token_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<StreamCtx*>(user_data);
    if (!ctx || !token) return RAC_TRUE;
    ctx->text += token;
    ++ctx->token_count;

    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* generation = event.mutable_generation();
    generation->set_kind(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED);
    generation->set_token(token);
    generation->set_streaming_text(ctx->text);
    generation->set_tokens_count(ctx->token_count);
    publish_event(event);

    if (!ctx->callback) return RAC_TRUE;
    std::vector<uint8_t> bytes;
    if (!serialize_event(event, &bytes)) return RAC_FALSE;
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

rac_result_t rac_vlm_process_proto(rac_handle_t handle,
                                   const uint8_t* image_proto_bytes,
                                   size_t image_proto_size,
                                   const uint8_t* options_proto_bytes,
                                   size_t options_proto_size,
                                   rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)image_proto_bytes;
    (void)image_proto_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.process",
                        "VLM lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "VLM lifecycle component is not loaded");
    }

    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rac_result_t rc = parse_vlm_request(image_proto_bytes, image_proto_size,
                                        options_proto_bytes, options_proto_size,
                                        &image, &options, &prompt, out_result);
    if (rc != RAC_SUCCESS) {
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        publish_failure(rc, "vlm.process", out_result->error_message);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED,
                       "vlm.process", 0.0f, 1, 0, nullptr);

    rac_vlm_result_t result = {};
    rc = rac_vlm_process(handle, &image, prompt, &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.process", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::VLMResult proto;
    if (!rac::foundation::rac_vlm_result_to_proto(&result, &proto)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode VLMResult");
    } else {
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.process", 1.0f, 1, proto.completion_tokens(), nullptr);
    rac_vlm_result_free(&result);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    return rc;
#endif
}

rac_result_t rac_vlm_process_stream_proto(
    rac_handle_t handle, const uint8_t* image_proto_bytes, size_t image_proto_size,
    const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_vlm_stream_proto_callback_fn callback, void* user_data,
    rac_proto_buffer_t* out_result) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)image_proto_bytes;
    (void)image_proto_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    (void)callback;
    (void)user_data;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.processStream",
                        "VLM lifecycle component is not loaded");
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                                       "VLM lifecycle component is not loaded")
                          : RAC_ERROR_COMPONENT_NOT_READY;
    }

    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rac_proto_buffer_t local_error;
    rac_proto_buffer_init(&local_error);
    rac_proto_buffer_t* error_buffer = out_result ? out_result : &local_error;
    rac_result_t rc = parse_vlm_request(image_proto_bytes, image_proto_size,
                                        options_proto_bytes, options_proto_size,
                                        &image, &options, &prompt, error_buffer);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.processStream", error_buffer->error_message);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        if (!out_result) rac_proto_buffer_free(&local_error);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED,
                       "vlm.processStream", 0.0f, 1, 0, nullptr);

    const auto start = std::chrono::steady_clock::now();
    StreamCtx ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    rc = rac_vlm_process_stream(handle, &image, prompt, &options,
                                stream_token_trampoline, &ctx);
    const auto end = std::chrono::steady_clock::now();

    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.processStream", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        return out_result ? rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc))
                          : rc;
    }

    if (out_result) {
        runanywhere::v1::VLMResult proto;
        proto.set_text(ctx.text);
        proto.set_completion_tokens(ctx.token_count);
        proto.set_total_tokens(ctx.token_count);
        proto.set_processing_time_ms(
            std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count());
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.processStream", 1.0f, 1, ctx.token_count, nullptr);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    return rc;
#endif
}

rac_result_t rac_vlm_cancel_proto(rac_handle_t handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.cancel",
                        "VLM lifecycle component is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    runanywhere::v1::SDKEvent requested;
    populate_envelope(&requested, runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    cancel->set_operation_id("vlm.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    rac_result_t rc = rac_vlm_cancel(handle);
    runanywhere::v1::SDKEvent completed;
    populate_envelope(&completed, rc == RAC_SUCCESS ? runanywhere::v1::EVENT_SEVERITY_INFO
                                                    : runanywhere::v1::EVENT_SEVERITY_ERROR);
    auto* completed_cancel = completed.mutable_cancellation();
    completed_cancel->set_kind(rc == RAC_SUCCESS
                                   ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    completed_cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    completed_cancel->set_operation_id("vlm.cancel");
    completed_cancel->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    completed_cancel->set_user_initiated(true);
    publish_event(completed);
    return rc;
#endif
}

}  // extern "C"
