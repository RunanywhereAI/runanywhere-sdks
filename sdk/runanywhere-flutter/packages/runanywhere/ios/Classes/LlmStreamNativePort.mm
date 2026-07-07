/**
 * LlmStreamNativePort.mm
 *
 * iOS-only Flutter helper for lifecycle-owned LLM streaming.
 *
 * Dart `NativeCallable.isolateLocal` is only safe when native invokes the
 * callback on the isolate-local mutator thread. MLX streams can call the C
 * callback from Swift/Metal worker threads, so the Flutter bridge needs a
 * thread-safe native-port hop. This helper receives the commons callback on
 * whatever thread the backend uses, copies the proto bytes before returning,
 * and posts owned typed-data messages to a Dart ReceivePort.
 */

#include <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <vector>

#include "dart_native_api.h"
#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"

namespace {

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);

struct LlmNativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

void post_int32(LlmNativePortContext* context, int32_t value) {
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
    auto* context = static_cast<LlmNativePortContext*>(user_data);
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

extern "C" int32_t ra_flutter_llm_generate_stream_proto_native_port(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    LlmNativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_llm_generate_stream_proto(
        request_proto_bytes,
        request_proto_size,
        stream_event_callback,
        &context);

    // Match the Dart worker contract: the return-code sentinel is posted last.
    // Quiesce first so a backend that finishes a callback on another thread
    // cannot race this stack-owned context.
    rac_llm_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}
