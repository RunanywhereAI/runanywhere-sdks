/**
 * @file rac_vlm_proto_abi.cpp
 * @brief Proto-byte C ABI for VLM service operations.
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#include "features/vlm/rac_vlm_lifecycle_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_proto_adapters.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "vlm_options.pb.h"
#endif

namespace {

// pass2-syn-001-followup-vlm: lift the voice_agent in_flight quiesce pattern
// to the VLM proto-byte dispatcher. Even though VLM does NOT publish a
// registry-style set/unset stream-callback ABI (each rac_vlm_*_stream_proto
// entry point owns a per-call StreamCtx / GeneratedStreamCtx and invokes
// ops->process_stream synchronously), a defensive in_flight counter still
// closes two real race windows:
//   1. A buggy backend that fires a stray trampoline invocation AFTER
//      ops->process_stream has returned (the Phase 6f EXC_BAD_ACCESS that
//      motivated the existing unique_ptr<StreamCtx> heap allocation).
//   2. Any caller that tears down the lifecycle VLM (rac_vlm_component_destroy
//      / rac_lifecycle_destroy) while a stream entry-point is still mid-call
//      on another thread — release_lifecycle_vlm currently has no quiesce
//      contract, so a destroy thread can race the dispatch thread.
// We increment the counter on entry to each stream entry-point and decrement
// just before returning. rac_vlm_component_destroy spin-waits for the counter
// to drain to zero, exactly mirroring voice_agent.cpp:594.
//
// pass3-syn-089: complete the voice_agent pattern by adding an
// is_shutting_down barrier (voice_agent.cpp:569 / 1212-1221). Without it, a
// new caller could acquire the in_flight counter mid-quiesce and extend the
// spin-wait indefinitely (and worse, dispatch on a legacy struct-API service
// whose backend is being freed). VlmInFlightGuard now performs the canonical
// TOCTOU-safe sequence: check flag, increment counter, re-check flag, and
// expose admitted() so entry points can early-return without dispatching.
std::atomic<int>& vlm_in_flight() {
    static std::atomic<int> counter{0};
    return counter;
}

std::atomic<bool>& vlm_proto_shutting_down() {
    static std::atomic<bool> flag{false};
    return flag;
}

struct VlmInFlightGuard {
    VlmInFlightGuard() {
        if (vlm_proto_shutting_down().load(std::memory_order_acquire)) {
            return;
        }
        vlm_in_flight().fetch_add(1, std::memory_order_acq_rel);
        // Re-check after incrementing to avoid TOCTOU with rac_vlm_proto_quiesce.
        if (vlm_proto_shutting_down().load(std::memory_order_acquire)) {
            vlm_in_flight().fetch_sub(1, std::memory_order_acq_rel);
            return;
        }
        admitted_ = true;
    }
    ~VlmInFlightGuard() {
        if (admitted_) {
            vlm_in_flight().fetch_sub(1, std::memory_order_acq_rel);
        }
    }
    bool admitted() const { return admitted_; }
    VlmInFlightGuard(const VlmInFlightGuard&) = delete;
    VlmInFlightGuard& operator=(const VlmInFlightGuard&) = delete;

   private:
    bool admitted_{false};
};

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

std::string event_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%lld-%llu", static_cast<long long>(now_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return buffer;
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
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

rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

void populate_envelope(runanywhere::v1::SDKEvent* event, runanywhere::v1::ErrorSeverity severity) {
    event->set_id(event_id());
    event->set_timestamp_ms(now_ms());
    event->set_category(runanywhere::v1::EVENT_CATEGORY_VLM);
    event->set_severity(severity);
    event->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_source("cpp");
}

void publish_event(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        (void)rac_sdk_event_publish_proto(bytes.empty() ? nullptr : bytes.data(), bytes.size());
    }
}

void publish_capability(runanywhere::v1::CapabilityOperationEventKind kind, const char* operation,
                        float progress, int64_t input_count, int64_t output_count,
                        const char* error) {
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, (error != nullptr && error[0] != '\0')
                                  ? runanywhere::v1::ERROR_SEVERITY_ERROR
                                  : runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cap = event.mutable_capability();
    cap->set_kind(kind);
    cap->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    if (operation) {
        event.set_operation_id(operation);
        cap->set_operation(operation);
    }
    cap->set_progress(progress);
    cap->set_input_count(input_count);
    cap->set_output_count(output_count);
    if (error)
        cap->set_error(error);
    publish_event(event);
}

void publish_failure(rac_result_t code, const char* operation, const char* message) {
    publish_capability(
        runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED, operation, 0.0f, 0, 0,
        (message != nullptr && message[0] != '\0') ? message : rac_error_message(code));
    (void)rac_sdk_event_publish_failure(code, message, "vlm", operation, RAC_TRUE);
}

void free_vlm_image(rac_vlm_image_t* image) {
    if (!image)
        return;
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
        !rac::foundation::rac_vlm_options_from_proto(options_proto, out_options, out_prompt)) {
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

rac_result_t parse_vlm_generation_request(const uint8_t* request_bytes, size_t request_size,
                                          runanywhere::v1::VLMGenerationRequest* out_request,
                                          rac_vlm_image_t* out_image,
                                          rac_vlm_options_t* out_options, const char** out_prompt,
                                          rac_proto_buffer_t* out_error) {
    if (!valid_bytes(request_bytes, request_size)) {
        return parse_error(out_error, "VLMGenerationRequest bytes are invalid");
    }
    if (!out_request->ParseFromArray(parse_data(request_bytes, request_size),
                                     static_cast<int>(request_size))) {
        return parse_error(out_error, "failed to parse VLMGenerationRequest");
    }
    if (out_request->images_size() != 1) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_INVALID_ARGUMENT,
            "VLMGenerationRequest.images must contain exactly one image");
    }

    const runanywhere::v1::VLMGenerationOptions& options_proto =
        out_request->has_options() ? out_request->options()
                                   : runanywhere::v1::VLMGenerationOptions::default_instance();

    if (!rac::foundation::rac_vlm_image_from_proto(out_request->images(0), out_image) ||
        !rac::foundation::rac_vlm_options_from_proto(options_proto, out_options, out_prompt)) {
        return rac_proto_buffer_set_error(out_error, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert VLMGenerationRequest");
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

rac_result_t check_lifecycle_model(const runanywhere::v1::VLMGenerationRequest& request,
                                   const rac::vlm::LifecycleVlmRef& ref,
                                   rac_proto_buffer_t* out_error) {
    if (!request.model_id().empty() && ref.model_id && request.model_id() != ref.model_id) {
        return rac_proto_buffer_set_error(
            out_error, RAC_ERROR_INVALID_ARGUMENT,
            "VLMGenerationRequest.model_id does not match the lifecycle-loaded model");
    }
    return RAC_SUCCESS;
}

struct StreamCtx {
    rac_vlm_stream_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
    std::string text;
    int32_t token_count{0};
};

void populate_result_from_stream(const StreamCtx& ctx, int64_t elapsed_ms,
                                 runanywhere::v1::VLMResult* out) {
    out->set_text(ctx.text);
    out->set_completion_tokens(ctx.token_count);
    out->set_total_tokens(ctx.token_count);
    out->set_processing_time_ms(elapsed_ms);
    if (elapsed_ms > 0) {
        out->set_tokens_per_second(static_cast<float>(ctx.token_count) /
                                   (static_cast<float>(elapsed_ms) / 1000.0f));
    }
}

bool serialize_event(const runanywhere::v1::SDKEvent& event, std::vector<uint8_t>* out) {
    out->resize(event.ByteSizeLong());
    return out->empty() || event.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_bool_t stream_token_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<StreamCtx*>(user_data);
    if (!ctx || !token)
        return RAC_TRUE;
    ctx->text += token;
    ++ctx->token_count;

    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* generation = event.mutable_generation();
    generation->set_kind(runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED);
    generation->set_token(token);
    generation->set_streaming_text(ctx->text);
    generation->set_tokens_count(ctx->token_count);
    publish_event(event);

    if (!ctx->callback)
        return RAC_TRUE;
    std::vector<uint8_t> bytes;
    if (!serialize_event(event, &bytes))
        return RAC_FALSE;
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data) ==
                   RAC_TRUE
               ? RAC_TRUE
               : RAC_FALSE;
}

struct GeneratedStreamCtx {
    rac_vlm_stream_event_proto_callback_fn callback{nullptr};
    void* user_data{nullptr};
    rac::vlm::LifecycleVlmRef* ref{nullptr};
    std::string request_id;
    std::string text;
    uint64_t seq{0};
    int32_t token_count{0};
    int64_t started_ms{0};
    bool terminal_sent{false};
};

bool serialize_vlm_stream_event(const runanywhere::v1::VLMStreamEvent& event,
                                std::vector<uint8_t>* out) {
    out->resize(event.ByteSizeLong());
    return out->empty() || event.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_bool_t dispatch_vlm_stream_event(GeneratedStreamCtx* ctx,
                                     runanywhere::v1::VLMStreamEventKind kind, const char* token,
                                     bool is_final, const runanywhere::v1::VLMResult* result,
                                     const char* error_message, int32_t error_code) {
    if (!ctx || !ctx->callback) {
        return RAC_TRUE;
    }

    runanywhere::v1::VLMStreamEvent event;
    event.set_seq(++ctx->seq);
    event.set_timestamp_us(now_us());
    event.set_request_id(ctx->request_id);
    event.set_kind(kind);
    event.set_is_final(is_final);
    if (token != nullptr && token[0] != '\0') {
        event.set_token(token);
        event.set_token_index(ctx->token_count - 1);
    }
    if (result) {
        event.mutable_result()->CopyFrom(*result);
        event.set_tokens_per_second(result->tokens_per_second());
    }
    if (error_message != nullptr && error_message[0] != '\0') {
        event.set_error_message(error_message);
    }
    if (error_code != 0) {
        event.set_error_code(error_code);
    }

    std::vector<uint8_t> bytes;
    if (!serialize_vlm_stream_event(event, &bytes)) {
        return RAC_FALSE;
    }
    return ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
}

rac_bool_t dispatch_vlm_terminal_once(GeneratedStreamCtx* ctx,
                                      runanywhere::v1::VLMStreamEventKind kind,
                                      const runanywhere::v1::VLMResult* result,
                                      const char* error_message, int32_t error_code) {
    if (!ctx || ctx->terminal_sent) {
        return RAC_TRUE;
    }
    ctx->terminal_sent = true;
    return dispatch_vlm_stream_event(ctx, kind, nullptr, true, result, error_message, error_code);
}

rac_bool_t generated_stream_token_trampoline(const char* token, void* user_data) {
    auto* ctx = static_cast<GeneratedStreamCtx*>(user_data);
    if (!ctx || !ctx->ref)
        return RAC_FALSE;
    if (rac::vlm::lifecycle_vlm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    const char* safe_token = token ? token : "";
    ctx->text += safe_token;
    if (safe_token[0] != '\0') {
        ++ctx->token_count;
    }

    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* generation = event.mutable_generation();
    generation->set_kind(ctx->token_count == 1
                             ? runanywhere::v1::GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED
                             : runanywhere::v1::GENERATION_EVENT_KIND_TOKEN_GENERATED);
    generation->set_token(safe_token);
    generation->set_streaming_text(ctx->text);
    generation->set_tokens_count(ctx->token_count);
    if (ctx->ref->model_id)
        generation->set_model_id(ctx->ref->model_id);
    publish_event(event);

    return dispatch_vlm_stream_event(ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_TOKEN, safe_token,
                                     false, nullptr, nullptr, 0);
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

// Public quiesce helper. Callers (rac_vlm_component_destroy, lifecycle
// teardown paths in SDK bridges) spin-wait here before freeing any
// user_data that may have been passed into a rac_vlm_*_stream_proto call.
// Mirrors the contract documented in pass2-syn-001 for the LLM dispatcher.
//
// pass3-syn-089: set the is_shutting_down barrier FIRST so any caller that
// tries to enter the dispatcher after quiesce begins is rejected by
// VlmInFlightGuard, then spin-wait until currently-in-flight calls drain.
// This mirrors voice_agent.cpp:569-592 and rac_diffusion_proto_quiesce.
//
// e2e-rn-vlm-fix: the barrier MUST be cleared after the drain completes.
// The original implementation left the flag process-lifetime sticky on the
// assumption that VLM only quiesces at destroy. That assumption was wrong:
// the RN core Nitro bridge (HybridRunAnywhereCore+Voice.cpp:952) and the
// Flutter VLM bridge (dart_bridge_vlm.dart:164/175) both invoke this quiesce
// as a per-stream drain after EVERY rac_vlm_stream_proto call — the exact
// teardown recipe documented in rac_vlm_service.h:236-243 and shared with the
// LLM/STT/TTS dispatchers, whose quiesce helpers are pure idempotent drains.
// Leaving the flag latched poisoned the ABI: the SECOND describe (and the
// first RN describe after any earlier stream) was rejected by
// VlmInFlightGuard with RAC_ERROR_INVALID_STATE, surfacing in JS/Dart as
// "rac_vlm_stream_proto failed: invalid state". Clearing the barrier after
// the drain — identical to rac_diffusion_proto_quiesce, which already does
// this for its per-model-swap reuse — keeps the ABI reusable across streams
// while preserving the TOCTOU-safe barrier+drain window (any dispatcher entry
// that observed false→true was rejected or already drained before the clear).
// Swift is unaffected: its VLM stream path never calls this quiesce per
// stream (it cancels via rac_vlm_cancel_proto in onTermination). The destroy
// paths (vlm_component.cpp:350, rac_vlm_service.cpp:274) remain safe because
// they tear down the lifecycle immediately afterwards, so a post-clear
// acquire_lifecycle_vlm returns RAC_ERROR_NOT_INITIALIZED rather than
// dispatching into freed state.
void rac_vlm_proto_quiesce(void) {
    vlm_proto_shutting_down().store(true, std::memory_order_release);
    while (vlm_in_flight().load(std::memory_order_acquire) > 0) {
        std::this_thread::yield();
    }
    vlm_proto_shutting_down().store(false, std::memory_order_release);
}

rac_result_t rac_vlm_process_proto(rac_handle_t handle, const uint8_t* image_proto_bytes,
                                   size_t image_proto_size, const uint8_t* options_proto_bytes,
                                   size_t options_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    (void)image_proto_bytes;
    (void)image_proto_size;
    (void)options_proto_bytes;
    (void)options_proto_size;
    return feature_unavailable(out_result);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    // Phase 6j fix: prefer the lifecycle-owned VLM service over the caller's
    // handle. iOS SDK's `CppBridge.VLM` passes a `rac_vlm_component*` into this
    // proto ABI (the only VLM handle it owns), not a `rac_vlm_service_t*`.
    // Blindly casting to `rac_vlm_service_t*` previously misread the ops vtable
    // pointer out of the component's `LifecycleManager::logger_category`
    // std::string, producing `EXC_BAD_ACCESS` at `0x6566694c2e4d4c56` -- the
    // little-endian encoding of "VLM.Life" -- on iPhone 17 Pro Max. Routing
    // through `acquire_lifecycle_vlm` removes the handle-type dependency
    // entirely; Swift, Kotlin, and JNI callers all populate the lifecycle via
    // `rac_model_lifecycle_load_proto` before inference, so the lifecycle
    // reference is always authoritative. The `handle` parameter is retained
    // only for the legacy struct-API smoke tests that pass a mock
    // `rac_vlm_service_t*` without going through the lifecycle.
    rac::vlm::LifecycleVlmRef lifecycle_ref;
    const rac_result_t acquire_rc = rac::vlm::acquire_lifecycle_vlm(&lifecycle_ref);
    const bool have_lifecycle = (acquire_rc == RAC_SUCCESS);

    if (!have_lifecycle && !handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.process",
                        "VLM lifecycle component is not loaded");
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_COMPONENT_NOT_READY,
                                          "VLM lifecycle component is not loaded");
    }

    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rac_result_t rc = parse_vlm_request(image_proto_bytes, image_proto_size, options_proto_bytes,
                                        options_proto_size, &image, &options, &prompt, out_result);
    if (rc != RAC_SUCCESS) {
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
        publish_failure(rc, "vlm.process", out_result->error_message);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.process",
                       0.0f, 1, 0, nullptr);

    rac_vlm_result_t result = {};
    if (have_lifecycle) {
        if (!lifecycle_ref.ops || !lifecycle_ref.ops->process) {
            rc = RAC_ERROR_NOT_SUPPORTED;
        } else {
            rc = lifecycle_ref.ops->process(lifecycle_ref.impl, &image, prompt, &options, &result);
        }
    } else {
        // Legacy struct-API path: caller provided a `rac_vlm_service_t*`.
        rc = rac_vlm_process(handle, &image, prompt, &options, &result);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.process", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
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
    rac::foundation::rac_vlm_options_free_owned(&options);
    if (have_lifecycle)
        rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
    return rc;
#endif
}

rac_result_t rac_vlm_process_stream_proto(rac_handle_t handle, const uint8_t* image_proto_bytes,
                                          size_t image_proto_size,
                                          const uint8_t* options_proto_bytes,
                                          size_t options_proto_size,
                                          rac_vlm_stream_proto_callback_fn callback,
                                          void* user_data, rac_proto_buffer_t* out_result) {
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
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                                       "VLM proto ABI is shutting down")
                          : RAC_ERROR_INVALID_STATE;
    }
    // Phase 6j fix: mirror rac_vlm_process_proto -- prefer the lifecycle-owned
    // VLM service so Swift's component-handle and Kotlin's service-handle paths
    // converge on the correct ops vtable.
    rac::vlm::LifecycleVlmRef lifecycle_ref;
    const rac_result_t acquire_rc = rac::vlm::acquire_lifecycle_vlm(&lifecycle_ref);
    const bool have_lifecycle = (acquire_rc == RAC_SUCCESS);

    if (!have_lifecycle && !handle) {
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
    rac_result_t rc =
        parse_vlm_request(image_proto_bytes, image_proto_size, options_proto_bytes,
                          options_proto_size, &image, &options, &prompt, error_buffer);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.processStream", error_buffer->error_message);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (!out_result)
            rac_proto_buffer_free(&local_error);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
        return rc;
    }

    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED,
                       "vlm.processStream", 0.0f, 1, 0, nullptr);

    const auto start = std::chrono::steady_clock::now();
    // Heap-allocate StreamCtx via unique_ptr so its lifetime clearly outlives
    // any stray callback invocation the engine might trigger after
    // rac_vlm_process_stream returns. The previous stack-allocated ctx was
    // correct in principle (process_stream is synchronous) but showed up in
    // Phase 6f as an EXC_BAD_ACCESS with a garbage PC inside the trampoline
    // call site on iOS Simulator. Heap allocation + move-capture-style
    // ownership is the simpler, safer fix here than auditing every future
    // engine to guarantee no post-return callback invocation.
    auto ctx = std::make_unique<StreamCtx>();
    ctx->callback = callback;
    ctx->user_data = user_data;
    if (have_lifecycle) {
        if (!lifecycle_ref.ops || !lifecycle_ref.ops->process_stream) {
            rc = RAC_ERROR_NOT_SUPPORTED;
        } else {
            rc = lifecycle_ref.ops->process_stream(lifecycle_ref.impl, &image, prompt, &options,
                                                   stream_token_trampoline, ctx.get());
        }
    } else {
        rc = rac_vlm_process_stream(handle, &image, prompt, &options, stream_token_trampoline,
                                    ctx.get());
    }
    const auto end = std::chrono::steady_clock::now();

    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.processStream", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        if (have_lifecycle)
            rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
        return out_result ? rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc)) : rc;
    }

    if (out_result) {
        runanywhere::v1::VLMResult proto;
        proto.set_text(ctx->text);
        proto.set_completion_tokens(ctx->token_count);
        proto.set_total_tokens(ctx->token_count);
        proto.set_processing_time_ms(
            std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count());
        rc = copy_proto(proto, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.processStream", 1.0f, 1, ctx->token_count, nullptr);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    if (have_lifecycle)
        rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
    return rc;
#endif
}

rac_result_t rac_vlm_cancel_proto(rac_handle_t handle) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)handle;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return RAC_ERROR_INVALID_STATE;
    }
    // Phase 6j fix: prefer the lifecycle-owned VLM to avoid the handle-type
    // mismatch that crashed `rac_vlm_process_proto` on iOS. The `handle`
    // parameter is kept only as a legacy fallback for struct-API smoke tests.
    rac::vlm::LifecycleVlmRef lifecycle_ref;
    const rac_result_t acquire_rc = rac::vlm::acquire_lifecycle_vlm(&lifecycle_ref);
    const bool have_lifecycle = (acquire_rc == RAC_SUCCESS);

    if (!have_lifecycle && !handle) {
        publish_failure(RAC_ERROR_COMPONENT_NOT_READY, "vlm.cancel",
                        "VLM lifecycle component is not loaded");
        return RAC_ERROR_COMPONENT_NOT_READY;
    }
    runanywhere::v1::SDKEvent requested;
    populate_envelope(&requested, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    cancel->set_operation_id("vlm.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    rac_result_t rc;
    if (have_lifecycle) {
        if (lifecycle_ref.ops && lifecycle_ref.ops->cancel) {
            rc = lifecycle_ref.ops->cancel(lifecycle_ref.impl);
        } else {
            rc = RAC_SUCCESS;  // No-op if backend doesn't implement cancel
        }
    } else {
        rc = rac_vlm_cancel(handle);
    }
    runanywhere::v1::SDKEvent completed;
    populate_envelope(&completed, rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                    : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* completed_cancel = completed.mutable_cancellation();
    completed_cancel->set_kind(rc == RAC_SUCCESS
                                   ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    completed_cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    completed_cancel->set_operation_id("vlm.cancel");
    completed_cancel->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    completed_cancel->set_user_initiated(true);
    publish_event(completed);
    if (have_lifecycle)
        rac::vlm::release_lifecycle_vlm(&lifecycle_ref);
    return rc;
#endif
}

rac_result_t rac_vlm_generate_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                    rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return feature_unavailable(out_result);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", "no lifecycle VLM model loaded");
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle VLM model loaded");
    }

    runanywhere::v1::VLMGenerationRequest request;
    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rc = parse_vlm_generation_request(request_proto_bytes, request_proto_size, &request, &image,
                                      &options, &prompt, out_result);
    if (rc == RAC_SUCCESS) {
        rc = check_lifecycle_model(request, ref, out_result);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", out_result->error_message);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rc;
    }

    rac::vlm::clear_lifecycle_vlm_cancel(&ref);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.generate",
                       0.0f, 1, 0, nullptr);

    rac_vlm_result_t raw = {};
    rc = (ref.ops && ref.ops->process) ? ref.ops->process(ref.impl, &image, prompt, &options, &raw)
                                       : RAC_ERROR_NOT_SUPPORTED;
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.generate", rac_error_message(rc));
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::VLMResult result;
    if (!rac::foundation::rac_vlm_result_to_proto(&raw, &result)) {
        rc = rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                        "failed to encode VLMResult");
    } else {
        rc = copy_proto(result, out_result);
    }
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                       "vlm.generate", 1.0f, 1, result.completion_tokens(), nullptr);
    rac_vlm_result_free(&raw);
    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc;
#endif
}

rac_result_t rac_vlm_stream_proto(const uint8_t* request_proto_bytes, size_t request_proto_size,
                                  rac_vlm_stream_event_proto_callback_fn callback,
                                  void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback) {
        return RAC_ERROR_NULL_POINTER;
    }

    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return RAC_ERROR_INVALID_STATE;
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.stream", "no lifecycle VLM model loaded");
        return rc;
    }

    rac_proto_buffer_t error_buffer;
    rac_proto_buffer_init(&error_buffer);
    runanywhere::v1::VLMGenerationRequest request;
    rac_vlm_image_t image = {};
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;
    const char* prompt = nullptr;
    rc = parse_vlm_generation_request(request_proto_bytes, request_proto_size, &request, &image,
                                      &options, &prompt, &error_buffer);
    if (rc == RAC_SUCCESS) {
        rc = check_lifecycle_model(request, ref, &error_buffer);
    }
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.stream", error_buffer.error_message);
        rac_proto_buffer_free(&error_buffer);
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return rc;
    }
    rac_proto_buffer_free(&error_buffer);
    if (!ref.ops || !ref.ops->process_stream) {
        free_vlm_image(&image);
        rac_free(const_cast<char*>(prompt));
        rac::foundation::rac_vlm_options_free_owned(&options);
        rac::vlm::release_lifecycle_vlm(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac::vlm::clear_lifecycle_vlm_cancel(&ref);
    publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED, "vlm.stream",
                       0.0f, 1, 0, nullptr);

    GeneratedStreamCtx ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.request_id = request.request_id();
    ctx.started_ms = now_ms();

    dispatch_vlm_stream_event(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_STARTED, nullptr, false,
                              nullptr, nullptr, 0);

    rc = ref.ops->process_stream(ref.impl, &image, prompt, &options,
                                 generated_stream_token_trampoline, &ctx);

    const int64_t elapsed_ms = now_ms() - ctx.started_ms;
    const bool cancelled = rac::vlm::lifecycle_vlm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        runanywhere::v1::VLMResult result;
        populate_result_from_stream(StreamCtx{.callback = nullptr,
                                              .user_data = nullptr,
                                              .text = ctx.text,
                                              .token_count = ctx.token_count},
                                    elapsed_ms, &result);
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_COMPLETED, &result,
                                   nullptr, 0);
        rc = RAC_SUCCESS;
    } else if (rc != RAC_SUCCESS) {
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_ERROR, nullptr,
                                   rac_error_message(rc), static_cast<int32_t>(rc));
        publish_failure(rc, "vlm.stream", rac_error_message(rc));
    } else {
        runanywhere::v1::VLMResult result;
        populate_result_from_stream(StreamCtx{.callback = nullptr,
                                              .user_data = nullptr,
                                              .text = ctx.text,
                                              .token_count = ctx.token_count},
                                    elapsed_ms, &result);
        dispatch_vlm_terminal_once(&ctx, runanywhere::v1::VLM_STREAM_EVENT_KIND_COMPLETED, &result,
                                   nullptr, 0);
        publish_capability(runanywhere::v1::CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
                           "vlm.stream", 1.0f, 1, ctx.token_count, nullptr);
    }

    free_vlm_image(&image);
    rac_free(const_cast<char*>(prompt));
    rac::foundation::rac_vlm_options_free_owned(&options);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc;
#endif
}

rac_result_t rac_vlm_cancel_lifecycle_proto(rac_proto_buffer_t* out_event) {
    if (!out_event)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    return feature_unavailable(out_event);
#else
    VlmInFlightGuard in_flight_guard;
    if (!in_flight_guard.admitted()) {
        return rac_proto_buffer_set_error(out_event, RAC_ERROR_INVALID_STATE,
                                          "VLM proto ABI is shutting down");
    }
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        publish_failure(rc, "vlm.cancel", "no lifecycle VLM model loaded");
        return rac_proto_buffer_set_error(out_event, rc, "no lifecycle VLM model loaded");
    }

    rac::vlm::request_lifecycle_vlm_cancel(&ref);
    runanywhere::v1::SDKEvent requested;
    populate_envelope(&requested, runanywhere::v1::ERROR_SEVERITY_INFO);
    auto* cancel = requested.mutable_cancellation();
    cancel->set_kind(runanywhere::v1::CANCELLATION_EVENT_KIND_REQUESTED);
    cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    cancel->set_operation_id("vlm.cancel");
    cancel->set_reason("requested by caller");
    cancel->set_user_initiated(true);
    publish_event(requested);

    if (ref.ops && ref.ops->cancel) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }

    runanywhere::v1::SDKEvent completed;
    populate_envelope(&completed, rc == RAC_SUCCESS ? runanywhere::v1::ERROR_SEVERITY_INFO
                                                    : runanywhere::v1::ERROR_SEVERITY_ERROR);
    auto* completed_cancel = completed.mutable_cancellation();
    completed_cancel->set_kind(rc == RAC_SUCCESS
                                   ? runanywhere::v1::CANCELLATION_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::CANCELLATION_EVENT_KIND_FAILED);
    completed_cancel->set_component(runanywhere::v1::SDK_COMPONENT_VLM);
    completed_cancel->set_operation_id("vlm.cancel");
    completed_cancel->set_reason(rc == RAC_SUCCESS ? "cancelled" : rac_error_message(rc));
    completed_cancel->set_user_initiated(true);
    publish_event(completed);

    rac_result_t copy_rc = copy_proto(completed, out_event);
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc == RAC_SUCCESS ? copy_rc : rc;
#endif
}

}  // extern "C"
