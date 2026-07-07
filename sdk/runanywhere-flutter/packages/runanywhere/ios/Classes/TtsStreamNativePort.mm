/**
 * TtsStreamNativePort.mm
 *
 * iOS-only Flutter helper for lifecycle-owned TTS streaming.
 *
 * Dart `NativeCallable.isolateLocal` is only safe when native invokes the
 * callback on the isolate-local mutator thread. MLX TTS bridges through Swift
 * async work, so the Flutter bridge cannot assume the stream callback arrives
 * on the Dart worker isolate thread. This helper copies proto bytes before
 * returning to commons and posts owned typed-data messages to a Dart
 * ReceivePort.
 */

#include <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <vector>

#include "dart_native_api.h"
#include "rac/core/rac_error.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_stream.h"

namespace {

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);

struct TtsNativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

void post_int32(TtsNativePortContext* context, int32_t value) {
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
    auto* context = static_cast<TtsNativePortContext*>(user_data);
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

}  // namespace

extern "C" int32_t ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    TtsNativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_tts_synthesize_stream_lifecycle_proto(
        request_proto_bytes,
        request_proto_size,
        stream_event_callback,
        &context);

    // Match the Dart worker contract: the return-code sentinel is posted last.
    // Quiesce first so a backend that finishes a callback on another thread
    // cannot race this stack-owned context.
    rac_tts_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}
