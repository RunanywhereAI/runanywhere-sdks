/**
 * RagQueryStreamNativePort.mm
 *
 * iOS-only Flutter helper for streaming RAG query events.
 *
 * Mirrors VoiceAgentStreamNativePort.mm: the RAG query stream composes ONNX
 * embeddings + llama.cpp generation, so the Flutter bridge cannot rely on
 * same-thread `NativeCallable.isolateLocal` delivery. This helper copies each
 * serialized RAGStreamEvent inside the C callback and posts owned typed-data
 * messages to a Dart ReceivePort, then posts the return code as the final
 * sentinel.
 *
 * The RAG control callback returns `rac_bool_t`: returning RAC_FALSE stops
 * generation early (backpressure) — used here when a post fails.
 */

#include <Foundation/Foundation.h>

#include <atomic>
#include <cstdint>
#include <vector>

#include "runanywhere_native/RunAnywhereDartNativeApi.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace {

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);
using RagStreamCallback = rac_bool_t (*)(const uint8_t*, size_t, void*);

struct RagNativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

void post_int32(RagNativePortContext* context, int32_t value) {
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

rac_bool_t stream_event_callback(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    auto* context = static_cast<RagNativePortContext*>(user_data);
    if (!context || !context->post || context->port == 0 || !event_bytes || event_size == 0) {
        return RAC_TRUE;
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
        return RAC_FALSE;  // Consumer is gone — stop native generation.
    }
    return RAC_TRUE;
}

}  // namespace

// Forward-declared (not pulled from rac_rag.h) so this helper stays robust
// against a vendored-header lag; the symbol is exported by RACommons.
extern "C" rac_result_t rac_rag_query_stream_proto(rac_handle_t session,
                                                   const uint8_t* query_proto_bytes,
                                                   size_t query_proto_size,
                                                   RagStreamCallback callback,
                                                   void* user_data);

extern "C" int32_t ra_flutter_rag_query_stream_proto_native_port(
    rac_handle_t session,
    const uint8_t* query_proto_bytes,
    size_t query_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!session || !query_proto_bytes || query_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RagNativePortContext context;
    context.port = port;
    context.post = post_cobject;

    // Synchronous: all RAGStreamEvents fire before this returns. Post the
    // return-code sentinel last to match the Dart contract.
    const rac_result_t rc = rac_rag_query_stream_proto(
        session, query_proto_bytes, query_proto_size, stream_event_callback, &context);
    post_int32(&context, rc);
    return rc;
}
