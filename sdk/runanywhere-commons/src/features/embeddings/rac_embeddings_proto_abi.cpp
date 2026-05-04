/**
 * @file rac_embeddings_proto_abi.cpp
 * @brief Proto-byte C ABI for embeddings service operations.
 */

#include "rac/features/embeddings/rac_embeddings_service.h"

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
#include "embeddings_options.pb.h"
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
                        const char* operation, float progress, int64_t input_count,
                        int64_t output_count, const char* error) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_EMBEDDINGS);
    event.set_severity(error && error[0] ? runanywhere::v1::EVENT_SEVERITY_ERROR
                                         : runanywhere::v1::EVENT_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS);
    if (operation) cap->set_operation(operation);
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error) cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED,
                       operation, 0.0f, 0, 0,
                       message && message[0] ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "embeddings", operation, RAC_TRUE);
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

rac_result_t rac_embeddings_embed_batch_proto(
    rac_handle_t handle, const uint8_t* request_proto_bytes, size_t request_proto_size,
    rac_proto_buffer_t* out_result) {
    if (!out_result) return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "embeddings.embedBatch",
                        "Embeddings lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "Embeddings lifecycle component is not loaded");
    }
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "EmbeddingsRequest bytes are invalid");
    }

    runanywhere::v1::EmbeddingsRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse EmbeddingsRequest");
    }

    std::vector<std::string> texts;
    texts.reserve(static_cast<size_t>(request.texts_size()));
    for (const auto& text : request.texts()) {
        if (!text.empty()) texts.push_back(text);
    }
    if (texts.empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "EmbeddingsRequest.texts is required");
    }

    rac_embeddings_options_t options = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_embeddings_options_from_proto(request.options(), &options)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert EmbeddingsOptions");
    }

    std::vector<const char*> c_texts;
    c_texts.reserve(texts.size());
    for (const auto& text : texts) {
        c_texts.push_back(text.c_str());
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED,
                       "embeddings.embedBatch", 0.0f,
                       static_cast<int64_t>(texts.size()), 0, nullptr);

    rac_embeddings_result_t result = {};
    rac_result_t rc = rac_embeddings_embed_batch(handle, c_texts.data(), c_texts.size(),
                                                 &options, &result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "embeddings.embedBatch", rac_error_message(rc));
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::EmbeddingsResult proto;
    if (!rac::foundation::rac_embeddings_result_to_proto(&result, &proto)) {
        rac_embeddings_result_free(&result);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode EmbeddingsResult");
    }
    for (int i = 0; i < proto.vectors_size() && i < static_cast<int>(texts.size()); ++i) {
        proto.mutable_vectors(i)->set_text(texts[static_cast<size_t>(i)]);
    }
    rc = copy_proto(proto, out_result);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED,
                       "embeddings.embedBatch", 1.0f,
                       static_cast<int64_t>(texts.size()), proto.vectors_size(), nullptr);
    rac_embeddings_result_free(&result);
    return rc;
#endif
}

}  // extern "C"
