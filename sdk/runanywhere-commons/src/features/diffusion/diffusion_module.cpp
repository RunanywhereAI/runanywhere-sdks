/**
 * @file diffusion_module.cpp
 * @brief Unified Diffusion feature module.
 *
 * Owns the handle-based diffusion proto ABI and the lifecycle-owned proto ABI.
 *
 * Supports text-to-image, image-to-image, and inpainting.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_proto_adapters.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diffusion_options.pb.h"
#include "sdk_events.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "infrastructure/events/sdk_event_publish.h"
#endif

// =============================================================================
// PROTO-BYTE C ABI (formerly rac_diffusion_proto_abi.cpp) +
// LIFECYCLE-OWNED GENERATED-PROTO C ABI (formerly Diffusion slice of
// rac_nonllm_lifecycle_proto_abi.cpp)
//
// rac_diffusion_generate_proto / _with_progress / cancel are handle-based;
// rac_diffusion_generate_lifecycle_proto resolves the loaded model via the
// global registry (rac::lifecycle::acquire_lifecycle_diffusion).
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

const char* service_model_id(rac_handle_t handle) {
    const auto* service = static_cast<const rac_diffusion_service_t*>(handle);
    return service ? service->model_id : nullptr;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

// Carried from rac_nonllm_lifecycle_proto_abi.cpp — needed by the lifecycle
// generate verb below. Internal linkage; no ODR clash.
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

void free_diffusion_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    rac_free(const_cast<uint8_t*>(options->input_image_data));
    rac_free(const_cast<uint8_t*>(options->mask_data));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

bool serialize_proto(const google::protobuf::MessageLite& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    // Route through the destination router (sdk_event_publish) so the envelope's
    // TELEMETRY destination bit reaches the telemetry manager. A direct
    // rac_sdk_event_publish_proto call feeds only the PUBLIC stream, so these
    // capability events would never be recorded as telemetry.
    (void)rac::events::publish_prebuilt(event);
}

void publish_capability(
    runanywhere::v1::CapabilityOperationEventKind kind, const char* operation, float progress,
    const char* error, double duration_ms = 0.0, const char* model_id = nullptr,
    int32_t prompt_length = 0, int32_t negative_prompt_length = 0, int32_t image_width = 0,
    int32_t image_height = 0, int32_t num_inference_steps = 0, double guidance_scale = 0.0,
    int64_t seed = 0, int64_t output_size_bytes = 0,
    runanywhere::v1::EventDestination destination = runanywhere::v1::EVENT_DESTINATION_ALL) {
    runanywhere::v1::SDKEvent event;
    event.set_id(event_id());
    event.set_timestamp_ms(now_ms());
    event.set_category(runanywhere::v1::EVENT_CATEGORY_DIFFUSION);
    event.set_severity(error && error[0] != '\0' ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                                 : runanywhere::v1::ERROR_SEVERITY_INFO);
    event.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    event.set_destination(destination);
    event.set_source("cpp");
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    if (model_id != nullptr && model_id[0] != '\0') {
        cap->set_model_id(model_id);
    }
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    if (error)
        cap->set_error(error);
    // CapabilityOperationEvent has no duration field; telemetry reads it from
    // the envelope properties map (see telemetry_manager kCapability extraction).
    if (duration_ms > 0.0) {
        (*event.mutable_properties())["duration_ms"] = std::to_string(duration_ms);
    }
    // ImageGen detail fields ride the properties carrier (extracted in the
    // telemetry kCapability SDK_COMPONENT_DIFFUSION branch). Gated on >0 so the
    // started/failed emits (which pass defaults) don't carry them.
    if (prompt_length > 0)
        (*event.mutable_properties())["prompt_length"] = std::to_string(prompt_length);
    if (negative_prompt_length > 0)
        (*event.mutable_properties())["negative_prompt_length"] =
            std::to_string(negative_prompt_length);
    if (image_width > 0)
        (*event.mutable_properties())["image_width"] = std::to_string(image_width);
    if (image_height > 0)
        (*event.mutable_properties())["image_height"] = std::to_string(image_height);
    if (num_inference_steps > 0)
        (*event.mutable_properties())["num_inference_steps"] = std::to_string(num_inference_steps);
    if (guidance_scale > 0.0)
        (*event.mutable_properties())["guidance_scale"] = std::to_string(guidance_scale);
    if (output_size_bytes > 0) {
        (*event.mutable_properties())["output_size_bytes"] = std::to_string(output_size_bytes);
        // seed is meaningful (incl. 0) but only emit it on a real completed
        // generation — keyed off output_size_bytes being present.
        (*event.mutable_properties())["seed"] = std::to_string(seed);
    }
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED, operation,
                       0.0f, message && message[0] != '\0' ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "diffusion", operation, RAC_TRUE);
}

void free_options(rac_diffusion_options_t* options) {
    if (!options)
        return;
    rac_free(const_cast<char*>(options->prompt));
    rac_free(const_cast<char*>(options->negative_prompt));
    rac_free(const_cast<uint8_t*>(options->input_image_data));
    rac_free(const_cast<uint8_t*>(options->mask_data));
    *options = RAC_DIFFUSION_OPTIONS_DEFAULT;
}

rac_result_t parse_options(const uint8_t* bytes, size_t size, rac_diffusion_options_t* out_options,
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
    if (!progress)
        return RAC_TRUE;

    runanywhere::v1::DiffusionProgress proto;
    if (!rac::foundation::rac_diffusion_progress_to_proto(progress, &proto)) {
        return RAC_FALSE;
    }

    // Progress is UI-only: at default steps a single generation would otherwise
    // land ~28 telemetry rows. Started/completed carry the backend record.
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS,
                       "diffusion.generate", progress->progress, nullptr, 0.0, nullptr, 0, 0, 0, 0,
                       0, 0.0, 0, 0, runanywhere::v1::EVENT_DESTINATION_PUBLIC);

    if (!ctx || !ctx->callback)
        return RAC_TRUE;
    std::vector<uint8_t> bytes;
    if (!serialize_proto(proto, &bytes))
        return RAC_FALSE;
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data) ==
                   RAC_TRUE
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

rac_result_t rac_diffusion_generate_proto(rac_handle_t handle, const uint8_t* options_proto_bytes,
                                          size_t options_proto_size,
                                          rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
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
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size, &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    const char* model_id = service_model_id(handle);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr, 0.0, model_id);
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
    if (rc == RAC_SUCCESS) {
        publish_capability(
            runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
            "diffusion.generate", 1.0f, nullptr, static_cast<double>(result.generation_time_ms),
            model_id, options.prompt ? static_cast<int32_t>(strlen(options.prompt)) : 0,
            options.negative_prompt ? static_cast<int32_t>(strlen(options.negative_prompt)) : 0,
            result.width, result.height, options.steps, static_cast<double>(options.guidance_scale),
            result.seed_used, static_cast<int64_t>(result.image_size));
    } else {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
    }
    rac_diffusion_result_free(&result);
    free_options(&options);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_with_progress_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    rac_diffusion_progress_proto_callback_fn progress_callback, void* user_data,
    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
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
    rac_result_t rc = parse_options(options_proto_bytes, options_proto_size, &options, out_result);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "diffusion.generate", out_result->error_message);
        free_options(&options);
        return rc;
    }

    const char* model_id = service_model_id(handle);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
                       "diffusion.generate", 0.0f, nullptr, 0.0, model_id);
    ProgressCtx ctx;
    ctx.callback = progress_callback;
    ctx.user_data = user_data;
    rac_diffusion_result_t result = {};
    rc = rac_diffusion_generate_with_progress(handle, &options, progress_trampoline, &ctx, &result);
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
    if (rc == RAC_SUCCESS) {
        publish_capability(
            runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
            "diffusion.generate", 1.0f, nullptr, static_cast<double>(result.generation_time_ms),
            model_id, options.prompt ? static_cast<int32_t>(strlen(options.prompt)) : 0,
            options.negative_prompt ? static_cast<int32_t>(strlen(options.negative_prompt)) : 0,
            result.width, result.height, options.steps, static_cast<double>(options.guidance_scale),
            result.seed_used, static_cast<int64_t>(result.image_size));
    } else {
        publish_failure(rc, "diffusion.generate", rac_error_message(rc));
    }
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
    requested.set_severity(runanywhere::v1::ERROR_SEVERITY_INFO);
    requested.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    requested.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    requested.set_source("cpp");
    requested.set_operation_id("diffusion.cancel");
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
    completed.set_severity(rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                             : runanywhere::v1::ERROR_SEVERITY_ERROR);
    completed.set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    completed.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    completed.set_source("cpp");
    completed.set_operation_id("diffusion.cancel");
    auto* done = completed.mutable_cancellation();
    done->set_kind(rc == RAC_SUCCESS ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                     : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    done->set_component(runanywhere::v1::SDK_COMPONENT_DIFFUSION);
    done->set_operation_id("diffusion.cancel");
    done->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    done->set_user_initiated(true);
    publish_event(completed);
    return rc;
#endif
}

rac_result_t rac_diffusion_generate_lifecycle_proto(const uint8_t* request_proto_bytes,
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
        return parse_error(out_result, "DiffusionGenerationRequest bytes are invalid");
    }
    runanywhere::v1::DiffusionGenerationRequest request;
    if (!request.ParseFromArray(parse_data(request_proto_bytes, request_proto_size),
                                static_cast<int>(request_proto_size))) {
        return parse_error(out_result, "failed to parse DiffusionGenerationRequest");
    }
    if (!request.has_options()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationRequest.options is required");
    }

    rac::lifecycle::LifecycleDiffusionRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_diffusion(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc,
                                          "Diffusion lifecycle model is not loaded");
    }
    rc = check_model_id(
        request.model_id(), ref.model_id,
        "DiffusionGenerationRequest.model_id does not match the lifecycle-loaded model",
        out_result);
    if (rc != RAC_SUCCESS) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rc;
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    if (!rac::foundation::rac_diffusion_options_from_proto(request.options(), &options)) {
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert DiffusionGenerationOptions");
    }
    if (!options.prompt || options.prompt[0] == '\0') {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "DiffusionGenerationOptions.prompt is required");
    }

    rac_diffusion_service_t service{ref.ops, ref.impl, ref.model_id};
    rac_diffusion_result_t raw = {};
    rc = rac_diffusion_generate(&service, &options, &raw);
    if (rc != RAC_SUCCESS) {
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiffusionResult result;
    if (!rac::foundation::rac_diffusion_result_to_proto(&raw, &result)) {
        rac_diffusion_result_free(&raw);
        free_diffusion_options(&options);
        rac::lifecycle::release_lifecycle_diffusion(&ref);
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "failed to encode DiffusionResult");
    }
    rc = copy_proto(result, out_result);
    rac_diffusion_result_free(&raw);
    free_diffusion_options(&options);
    rac::lifecycle::release_lifecycle_diffusion(&ref);
    return rc;
#endif
}

}  // extern "C"
