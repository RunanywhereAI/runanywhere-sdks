/**
 * @file embeddings_module.cpp
 * @brief Unified Embeddings feature module.
 *
 * Owns the handle-based embeddings proto ABI and the lifecycle-owned proto ABI.
 */

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_proto_adapters.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "embeddings_options.pb.h"
#include "sdk_events.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

#include "embeddings_service_internal.h"

// =============================================================================
// PROTO-BYTE C ABI (formerly rac_embeddings_proto_abi.cpp) +
// LIFECYCLE-OWNED GENERATED-PROTO C ABI (formerly Embeddings slice of
// rac_nonllm_lifecycle_proto_abi.cpp)
//
// rac_embeddings_embed_batch_proto / rac_embeddings_create_proto are
// handle-based; rac_embeddings_embed_batch_lifecycle_proto resolves the loaded
// model via the global registry (rac::lifecycle::acquire_lifecycle_embeddings).
// =============================================================================

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
    return rac::proto::parse_bytes(bytes, size);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return rac::proto::bytes_valid(bytes, size);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

// Carried from rac_nonllm_lifecycle_proto_abi.cpp — needed by the lifecycle
// embed_batch verb below. Internal linkage; no ODR clash.
rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac::proto::parse_error(out, message);
}

rac_result_t check_model_id(const std::string& requested, const char* loaded, const char* message,
                            rac_proto_buffer_t* out) {
    if (!requested.empty() && loaded && requested != loaded) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_INVALID_ARGUMENT, message);
    }
    return RAC_SUCCESS;
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the destination router (sdk_event_publish) so the envelope's
    // TELEMETRY destination bit reaches the telemetry manager. A direct
    // rac_sdk_event_publish_proto call feeds only the PUBLIC stream, so these
    // capability events would never be recorded as telemetry.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, int64_t input_count, int64_t output_count,
                        const char* error, double duration_ms = 0.0,
                        int64_t embedding_dimension = 0, const char* model_id = nullptr,
                        const char* framework = nullptr) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_EMBEDDINGS);
    event.set_severity((error != nullptr && error[0] != '\0')
                           ? runanywhere::v1::ERROR_SEVERITY_ERROR
                           : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS);
    event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_EMBEDDINGS);
    // model_id → telemetry base model_id + embeddings embedding_model column;
    // framework rides the properties carrier (CapabilityOperationEvent has no
    // framework field).
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);
    }
    if (framework != nullptr && framework[0] != '\0') {
        (*event.mutable_properties())["framework"] = framework;
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error)
        cap->set_error(error);
    // CapabilityOperationEvent has no duration field; telemetry reads it from
    // the envelope properties map (see telemetry_manager kCapability extraction).
    if (duration_ms > 0.0) {
        (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    }
    if (embedding_dimension > 0) {
        (*event.mutable_properties())["embedding_dimension"] = std::to_string(embedding_dimension);
    }
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(
        runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED, operation, 0.0f, 0, 0,
        (message != nullptr && message[0] != '\0') ? message : rac_error_message(code));
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

rac_result_t rac_embeddings_embed_batch_proto(rac_handle_t handle,
                                              const uint8_t* request_proto_bytes,
                                              size_t request_proto_size,
                                              rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
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

    if (request.texts_size() == 0) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "EmbeddingsRequest.texts is required");
    }
    // Proto contract: EmbeddingsResult.vectors carries one entry per input
    // text in input order, so callers can index by position. Silently
    // filtering empties would shift downstream indices; reject instead.
    std::vector<std::string> texts;
    texts.reserve(static_cast<size_t>(request.texts_size()));
    for (const auto& text : request.texts()) {
        if (text.empty()) {
            return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                              "EmbeddingsRequest.texts contains an empty entry");
        }
        texts.push_back(text);
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
                       "embeddings.embedBatch", 0.0f, static_cast<int64_t>(texts.size()), 0,
                       nullptr);

    rac_embeddings_result_t result = {};
    rac_result_t rc =
        rac_embeddings_embed_batch(handle, c_texts.data(), c_texts.size(), &options, &result);
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
    const int n_vectors_to_label = std::min(proto.vectors_size(), static_cast<int>(texts.size()));
    for (int i = 0; i < n_vectors_to_label; ++i) {
        proto.mutable_vectors(i)->set_text(texts[static_cast<size_t>(i)]);
    }
    rc = copy_proto(proto, out_result);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED,
                       "embeddings.embedBatch", 1.0f, static_cast<int64_t>(texts.size()),
                       proto.vectors_size(), nullptr,
                       static_cast<double>(result.processing_time_ms));
    rac_embeddings_result_free(&result);
    return rc;
#endif
}

rac_result_t rac_embeddings_create_proto(const uint8_t* request_proto_bytes,
                                         size_t request_proto_size,
                                         rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "EmbeddingsCreateRequest bytes are invalid");
    }

    runanywhere::v1::EmbeddingsCreateRequest request;
    if (request_proto_size > 0 &&
        !request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse EmbeddingsCreateRequest");
    }

    runanywhere::v1::EmbeddingsCreateResult create_result;
    create_result.set_model_id(request.model_id());

    if (request.model_id().empty()) {
        const char* msg = "EmbeddingsCreateRequest.model_id is required";
        create_result.set_error_code(static_cast<int32_t>(RAC_ERROR_INVALID_ARGUMENT));
        create_result.set_error_message(msg);
        publish_failure(RAC_ERROR_INVALID_ARGUMENT, "embeddings.create", msg);
        return copy_proto(create_result, out_result);
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = RAC_SUCCESS;
    const std::string& cfg_json = request.has_config_json() ? request.config_json() : std::string();
    rc = rac::embeddings::create_service(request.model_id().c_str(),
                                         cfg_json.empty() ? nullptr : cfg_json.c_str(), &handle);

    if (rc != RAC_SUCCESS || !handle) {
        const char* msg = rac_error_message(rc != RAC_SUCCESS ? rc : RAC_ERROR_UNKNOWN);
        create_result.set_handle(0);
        create_result.set_error_code(
            static_cast<int32_t>(rc != RAC_SUCCESS ? rc : RAC_ERROR_UNKNOWN));
        create_result.set_error_message(msg ? msg : "embeddings create failed");
        publish_failure(rc != RAC_SUCCESS ? rc : RAC_ERROR_UNKNOWN, "embeddings.create",
                        create_result.error_message().c_str());
        return copy_proto(create_result, out_result);
    }

    create_result.set_handle(reinterpret_cast<uint64_t>(handle));

    rac_embeddings_info_t info = {};
    if (rac_embeddings_get_info(handle, &info) == RAC_SUCCESS) {
        create_result.set_dimension(static_cast<int32_t>(info.dimension));
        create_result.set_max_tokens(static_cast<int32_t>(info.max_tokens));
    }

    // No event on create: service creation is not an embed request; the
    // unpaired STARTED here counted as a phantom embedding per create.
    return copy_proto(create_result, out_result);
#endif
}

rac_result_t rac_embeddings_embed_batch_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                        size_t request_proto_size,
                                                        rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    if (!valid_bytes(request_proto_bytes, request_proto_size)) {
        return parse_error(out_result, "EmbeddingsRequest bytes are invalid");
    }
    runanywhere::v1::EmbeddingsRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse EmbeddingsRequest");
    }

    // The generated-proto contract requires exactly one output vector per
    // input text, in the original order. Match the handle-based ABI by
    // rejecting empty entries instead of filtering them and shifting every
    // subsequent input_index.
    if (request.texts_size() == 0) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "EmbeddingsRequest.texts is required");
    }
    std::vector<std::string> texts;
    texts.reserve(static_cast<size_t>(request.texts_size()));
    for (const auto& text : request.texts()) {
        if (text.empty()) {
            return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                              "EmbeddingsRequest.texts contains an empty entry");
        }
        texts.push_back(text);
    }

    rac::lifecycle::LifecycleEmbeddingsRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_embeddings(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "Embeddings lifecycle model is not loaded");
    }
    rc = check_model_id(request.model_id(), ref.model_id,
                        "EmbeddingsRequest.model_id does not match the lifecycle-loaded model",
                        out_result);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rc;
    }

    // Telemetry: the lifecycle embed path is the one platform SDKs call, so it
    // must publish the embeddings capability events (the component-handle path's
    // publishes never fire for them). input_count = texts; output_count =
    // vectors produced (extracted into the embeddings V2 row).
    const int64_t embed_start_ms = now_ms();
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED,
                       "embeddings.embed", 0.0f, static_cast<int64_t>(texts.size()), 0, nullptr);

    rac_embeddings_options_t options = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    if (request.has_options() &&
        !rac::foundation::rac_embeddings_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert EmbeddingsOptions");
    }

    std::vector<const char*> c_texts;
    c_texts.reserve(texts.size());
    for (const auto& text : texts) {
        c_texts.push_back(text.c_str());
    }

    rac_embeddings_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_embeddings_result_t raw = {};
    rc = rac_embeddings_embed_batch(&service, c_texts.data(), c_texts.size(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "embeddings.embed", rac_error_message(rc));
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::EmbeddingsResult result;
    if (!rac::foundation::rac_embeddings_result_to_proto(&raw, &result)) {
        rac_embeddings_result_free(&raw);
        rac::lifecycle::release_lifecycle_embeddings(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode EmbeddingsResult");
    }
    for (int i = 0; i < result.vectors_size() && std::cmp_less(i, texts.size()); ++i) {
        result.mutable_vectors(i)->set_text(texts[static_cast<size_t>(i)]);
        result.mutable_vectors(i)->set_input_index(i);
    }
    result.set_model_id(ref.model_id ? ref.model_id : "");
    result.set_request_id(request.request_id());
    publish_capability(
        runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED, "embeddings.embed",
        1.0f, static_cast<int64_t>(texts.size()), static_cast<int64_t>(result.vectors_size()),
        nullptr, static_cast<double>(now_ms() - embed_start_ms),
        raw.num_embeddings > 0 ? static_cast<int64_t>(raw.embeddings[0].dimension) : 0,
        ref.model_id, ref.framework_name);
    rc = copy_proto(result, out_result);
    rac_embeddings_result_free(&raw);
    rac::lifecycle::release_lifecycle_embeddings(&ref);
    return rc;
#endif
}

}  // extern "C"
