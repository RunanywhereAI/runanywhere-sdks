/**
 * VoiceAgentStreamNativePort.mm
 *
 * iOS-only Flutter helper for voice-agent proto events.
 *
 * Dart `NativeCallable.isolateLocal` is only safe when native invokes the
 * callback on the isolate-local mutator thread. Voice turns can compose STT,
 * LLM, and TTS backends, including MLX Swift async work, so the Flutter bridge
 * cannot rely on same-thread callback delivery. This helper copies proto bytes
 * inside the C callback and posts owned typed-data messages to a Dart
 * ReceivePort.
 */

#include <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "runanywhere_native/RunAnywhereDartNativeApi.h"
#include "rac/core/rac_error.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"

namespace {

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);

struct VoiceNativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

std::mutex& contexts_mu() {
    static std::mutex mu;
    return mu;
}

std::unordered_map<rac_voice_agent_handle_t, std::unique_ptr<VoiceNativePortContext>>& contexts() {
    static std::unordered_map<rac_voice_agent_handle_t, std::unique_ptr<VoiceNativePortContext>> map;
    return map;
}

void post_int32(VoiceNativePortContext* context, int32_t value) {
    if (!context || !context->post || context->port == 0) {
        return;
    }

    Dart_CObject message;
    message.type = Dart_CObject_kInt32;
    message.value.as_int32 = value;
    if (!context->post(context->port, &message)) {
        context->post_failed.store(true, std::memory_order_relaxed);
    }
}

void stream_event_callback(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    auto* context = static_cast<VoiceNativePortContext*>(user_data);
    if (!context || !context->post || context->port == 0 || !event_bytes || event_size == 0) {
        return;
    }

    // `Dart_PostCObject` copies kTypedData before returning. Keep this local
    // vector alive until the post call completes; the commons buffer is only
    // valid for this callback invocation and may be reused immediately after.
    std::vector<uint8_t> owned(event_bytes, event_bytes + event_size);

    Dart_CObject message;
    message.type = Dart_CObject_kTypedData;
    message.value.as_typed_data.type = Dart_TypedData_kUint8;
    message.value.as_typed_data.length = static_cast<intptr_t>(owned.size());
    message.value.as_typed_data.values = owned.data();

    if (!context->post(context->port, &message)) {
        context->post_failed.store(true, std::memory_order_relaxed);
    }
}

void erase_context(rac_voice_agent_handle_t handle) {
    std::lock_guard<std::mutex> lock(contexts_mu());
    contexts().erase(handle);
}

}  // namespace

extern "C" int32_t ra_flutter_voice_agent_process_turn_proto_native_port(
    rac_voice_agent_handle_t handle,
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!handle || !request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    VoiceNativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_voice_agent_process_turn_proto(
        handle,
        request_proto_bytes,
        request_proto_size,
        stream_event_callback,
        &context);

    // The turn callback is synchronous today; quiesce also drains the
    // handle-level proto fan-out that the d7 turn path emits after the per-call
    // callback. Post the return-code sentinel last to match the Dart contract.
    rac_voice_agent_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}

extern "C" int32_t ra_flutter_voice_agent_unset_proto_callback_native_port(
    rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_result_t rc = rac_voice_agent_set_proto_callback(handle, nullptr, nullptr);
    rac_voice_agent_proto_quiesce();
    erase_context(handle);
    return rc;
}

extern "C" int32_t ra_flutter_voice_agent_set_proto_callback_native_port(
    rac_voice_agent_handle_t handle,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!handle || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    (void)ra_flutter_voice_agent_unset_proto_callback_native_port(handle);

    auto context = std::make_unique<VoiceNativePortContext>();
    context->port = port;
    context->post = post_cobject;
    auto* raw_context = context.get();

    const rac_result_t rc =
        rac_voice_agent_set_proto_callback(handle, stream_event_callback, raw_context);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    {
        std::lock_guard<std::mutex> lock(contexts_mu());
        contexts()[handle] = std::move(context);
    }
    return rc;
}
