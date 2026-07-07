/**
 * SttStreamNativePort.mm
 *
 * iOS-only Flutter helper for chunk-feed STT streaming sessions.
 *
 * The public Flutter STT stream API registers one callback per STT handle.
 * Dart `NativeCallable.isolateLocal` is unsafe if a backend, such as MLX via
 * Swift async streaming, invokes that callback from a non-Dart thread. This
 * helper owns the callback context natively, copies proto bytes inside the C
 * callback, and posts owned typed-data messages to a Dart ReceivePort.
 */

#include <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "dart_native_api.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_stream.h"

namespace {

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);

struct SttNativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

std::mutex& contexts_mu() {
    static std::mutex mu;
    return mu;
}

std::unordered_map<rac_handle_t, std::unique_ptr<SttNativePortContext>>& contexts() {
    static std::unordered_map<rac_handle_t, std::unique_ptr<SttNativePortContext>> map;
    return map;
}

void stream_event_callback(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    auto* context = static_cast<SttNativePortContext*>(user_data);
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

void erase_context(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(contexts_mu());
    contexts().erase(handle);
}

}  // namespace

extern "C" int32_t ra_flutter_stt_unset_stream_proto_native_port(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_result_t rc = rac_stt_unset_stream_proto_callback(handle);
    rac_stt_proto_quiesce();
    erase_context(handle);
    return rc;
}

extern "C" int32_t ra_flutter_stt_set_stream_proto_native_port(
    rac_handle_t handle,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!handle || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    (void)ra_flutter_stt_unset_stream_proto_native_port(handle);

    auto context = std::make_unique<SttNativePortContext>();
    context->port = port;
    context->post = post_cobject;
    auto* raw_context = context.get();

    const rac_result_t rc =
        rac_stt_set_stream_proto_callback(handle, stream_event_callback, raw_context);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    {
        std::lock_guard<std::mutex> lock(contexts_mu());
        contexts()[handle] = std::move(context);
    }
    return rc;
}
