/**
 * HybridRunAnywhereCore+Tools.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * Bridge classification:
 *   - SDK-facing pass-through: toolParseProto, toolFormatPromptProto,
 *     toolValidateProto, structuredOutputParseProto,
 *     structuredOutputPreparePromptProto, structuredOutputValidateProto,
 *     ragCreatePipelineProto, ragDestroyPipelineProto, ragIngestProto,
 *     ragQueryProto, ragClearProto, ragStatsProto,
 *     embeddingsEmbedBatchLifecycleProto (the commons embeddings lifecycle
 *     owns the component — no handle crosses the bridge; mirrors Swift
 *     CppBridge.EmbeddingsProto.embedBatchLifecycle).
 */
#include "HybridRunAnywhereCore+Common.hpp"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <future>
#include <stdexcept>

#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_schema_to_json.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::mutex g_ragProtoMutex;
rac_handle_t g_ragProtoSession = nullptr;
constexpr auto kToolExecutorTimeout = std::chrono::seconds(30);

struct ToolRunLoopExecutorState {
    HybridRunAnywhereCore::ToolRunLoopExecuteCallback onExecuteToolBytes;
};

std::vector<uint8_t> copyToolsArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }
    uint8_t* data = buffer->data();
    size_t size = buffer->size();
    if (!data || size == 0) {
        return bytes;
    }
    bytes.assign(data, data + size);
    return bytes;
}

std::shared_ptr<ArrayBuffer> emptyToolsProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

std::shared_ptr<ArrayBuffer> copyToolsProtoBuffer(rac_proto_buffer_t& protoBuffer,
                                                  const char* operation) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("%s proto error: %s", operation, protoBuffer.error_message);
        }
        rac_proto_buffer_free(&protoBuffer);
        return emptyToolsProtoBuffer();
    }
    if (!protoBuffer.data || protoBuffer.size == 0) {
        rac_proto_buffer_free(&protoBuffer);
        return emptyToolsProtoBuffer();
    }
    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    rac_proto_buffer_free(&protoBuffer);
    return buffer;
}

void setToolRunLoopError(rac_proto_buffer_t* out,
                         rac_result_t status,
                         const std::string& message) {
    if (!out) {
        return;
    }
    rac_proto_buffer_init(out);
    out->status = status;
    out->error_message = ::strdup(message.c_str());
}

bool waitForToolExecutorOuterPromise(
    const std::shared_ptr<Promise<std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>>>& promise,
    std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>* outInnerPromise) {
    if (!promise || !outInnerPromise) {
        return false;
    }
    auto future = promise->await();
    if (future.wait_for(kToolExecutorTimeout) != std::future_status::ready) {
        return false;
    }
    *outInnerPromise = future.get();
    return *outInnerPromise != nullptr;
}

bool waitForToolExecutorResult(
    const std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>& promise,
    std::shared_ptr<ArrayBuffer>* outResult) {
    if (!promise || !outResult) {
        return false;
    }
    auto future = promise->await();
    if (future.wait_for(kToolExecutorTimeout) != std::future_status::ready) {
        return false;
    }
    *outResult = future.get();
    return *outResult != nullptr;
}

rac_result_t toolRunLoopExecuteCallback(const uint8_t* inToolCallBytes,
                                        size_t inSize,
                                        rac_proto_buffer_t* outToolResultBytes,
                                        void* userData) {
    auto* state = static_cast<ToolRunLoopExecutorState*>(userData);
    if (!state || !outToolResultBytes || !state->onExecuteToolBytes) {
        setToolRunLoopError(
            outToolResultBytes,
            RAC_ERROR_INVALID_ARGUMENT,
            "tool run-loop executor callback is not available");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    try {
        std::shared_ptr<ArrayBuffer> toolCallBuffer = nullptr;
        if (inToolCallBytes && inSize > 0) {
            toolCallBuffer = ArrayBuffer::copy(inToolCallBytes, inSize);
        } else {
            toolCallBuffer = emptyToolsProtoBuffer();
        }

        auto outerPromise = state->onExecuteToolBytes(toolCallBuffer);
        std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>> innerPromise;
        if (!waitForToolExecutorOuterPromise(outerPromise, &innerPromise)) {
            setToolRunLoopError(
                outToolResultBytes,
                RAC_ERROR_TIMEOUT,
                "tool run-loop executor did not return a ToolResult promise in time");
            return RAC_ERROR_TIMEOUT;
        }

        std::shared_ptr<ArrayBuffer> toolResultBuffer;
        if (!waitForToolExecutorResult(innerPromise, &toolResultBuffer)) {
            setToolRunLoopError(
                outToolResultBytes,
                RAC_ERROR_TIMEOUT,
                "tool run-loop executor did not resolve ToolResult bytes in time");
            return RAC_ERROR_TIMEOUT;
        }

        uint8_t* resultData = toolResultBuffer->data();
        size_t resultSize = toolResultBuffer->size();
        if (!resultData || resultSize == 0) {
            setToolRunLoopError(
                outToolResultBytes,
                RAC_ERROR_INVALID_ARGUMENT,
                "tool run-loop executor returned empty ToolResult bytes");
            return RAC_ERROR_INVALID_ARGUMENT;
        }

        rac_proto_buffer_init(outToolResultBytes);
        outToolResultBytes->data = static_cast<uint8_t*>(std::malloc(resultSize));
        if (!outToolResultBytes->data) {
            setToolRunLoopError(
                outToolResultBytes,
                RAC_ERROR_INTERNAL,
                "tool run-loop failed to allocate ToolResult buffer");
            return RAC_ERROR_INTERNAL;
        }
        std::memcpy(outToolResultBytes->data, resultData, resultSize);
        outToolResultBytes->size = resultSize;
        outToolResultBytes->status = RAC_SUCCESS;
        outToolResultBytes->error_message = nullptr;
        return RAC_SUCCESS;
    } catch (const std::exception& error) {
        setToolRunLoopError(outToolResultBytes, RAC_ERROR_INTERNAL, error.what());
        return RAC_ERROR_INTERNAL;
    } catch (...) {
        setToolRunLoopError(
            outToolResultBytes,
            RAC_ERROR_INTERNAL,
            "tool run-loop executor failed with an unknown error");
        return RAC_ERROR_INTERNAL;
    }
}

std::shared_ptr<ArrayBuffer> copyRequiredToolsProtoBuffer(rac_proto_buffer_t& protoBuffer,
                                                          const char* operation) {
    if (protoBuffer.status != RAC_SUCCESS) {
        std::string error = protoBuffer.error_message
            ? protoBuffer.error_message
            : "unknown proto error";
        LOGE("%s proto error: %s", operation, error.c_str());
        rac_proto_buffer_free(&protoBuffer);
        throw std::runtime_error(std::string(operation) + ": " + error);
    }
    if (!protoBuffer.data || protoBuffer.size == 0) {
        rac_proto_buffer_free(&protoBuffer);
        throw std::runtime_error(std::string(operation) + ": empty proto result");
    }
    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    rac_proto_buffer_free(&protoBuffer);
    return buffer;
}

using BufferProtoFn = decltype(&rac_tool_call_parse_proto);
using RagBufferProtoFn = decltype(&rac_rag_ingest_proto);
using RagStatsProtoFn = decltype(&rac_rag_stats_proto);

std::shared_ptr<ArrayBuffer> callCommonsBufferProto(const std::vector<uint8_t>& bytes,
                                                    BufferProtoFn fn,
                                                    const char* operation) {
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(data, bytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        rac_proto_buffer_free(&out);
        throw std::runtime_error(
            std::string(operation) + ": commons call failed rc=" + std::to_string(rc));
    }
    return copyRequiredToolsProtoBuffer(out, operation);
}

void toolsProtoBytesCallback(const uint8_t* protoBytes, size_t protoSize, void* userData) {
    if (!protoBytes || protoSize == 0 || !userData) {
        return;
    }
    auto* callback =
        static_cast<std::function<void(const std::shared_ptr<ArrayBuffer>&)>*>(userData);
    if (!callback || !(*callback)) {
        return;
    }
    try {
        (*callback)(ArrayBuffer::copy(protoBytes, protoSize));
    } catch (...) {
        LOGE("tools proto callback dispatch failed");
    }
}

std::shared_ptr<ArrayBuffer> callRagBufferProto(const std::vector<uint8_t>& bytes,
                                                RagBufferProtoFn fn,
                                                const char* operation) {
    rac_handle_t session = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_ragProtoMutex);
        session = g_ragProtoSession;
    }
    if (!session) {
        LOGE("%s: RAG proto session not created", operation);
        return emptyToolsProtoBuffer();
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(session, data, bytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        rac_proto_buffer_free(&out);
        return emptyToolsProtoBuffer();
    }
    return copyToolsProtoBuffer(out, operation);
}

std::shared_ptr<ArrayBuffer> callRagStatsProto(RagStatsProtoFn fn,
                                               const char* operation) {
    rac_handle_t session = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_ragProtoMutex);
        session = g_ragProtoSession;
    }
    if (!session) {
        LOGE("%s: RAG proto session not created", operation);
        return emptyToolsProtoBuffer();
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = fn(session, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        rac_proto_buffer_free(&out);
        return emptyToolsProtoBuffer();
    }
    return copyToolsProtoBuffer(out, operation);
}

} // namespace

// Tool Calling and RAG
// ============================================================================
// Tool Calling
//
// ARCHITECTURE:
// - Commons C ABI (rac_tool_call_*): SINGLE SOURCE OF TRUTH for parsing,
//   prompt formatting, and validation. Shared by all SDK frontends.
// - Nitro proto-byte methods expose generated request/result envelopes to TS.
// - TypeScript (RunAnywhere+ToolCalling.ts): Registry, executor storage,
//   orchestration. Executors stay in TS because they need JS APIs (fetch, etc.).
// ============================================================================

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::toolParseProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(bytes, rac_tool_call_parse_proto, "toolParseProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::toolFormatPromptProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes, rac_tool_call_format_prompt_proto, "toolFormatPromptProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::toolValidateProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes, rac_tool_call_validate_proto, "toolValidateProto");
    });
}

// Binds to the canonical commons `rac_tool_calling_run_loop_proto` ABI, which
// fires `on_handle_published(handle, user_data)` synchronously on the worker
// thread the moment the cancellable handle is minted and BEFORE the first
// iteration runs. The callback forwards the
// handle straight to the JS `onHandle` callback, mirroring the Swift
// `HandleBox.set` (RunAnywhere+ToolCalling.swift:374-449), Kotlin
// `CompletableDeferred.complete`, Flutter `Completer.complete`, and Web
// synchronous-capture contracts. JS then arms an AbortSignal listener that
// calls `toolRunLoopCancelProto(handle)` to interrupt long-running loops.
std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::toolRunLoopProtoWithHandle(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const ToolRunLoopExecuteCallback& onExecuteToolBytes,
    const ToolRunLoopHandleCallback& onHandle) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [bytes = std::move(bytes), onExecuteToolBytes, onHandle]() {
            ToolRunLoopExecutorState state{onExecuteToolBytes};
            rac_proto_buffer_t out;
            rac_proto_buffer_init(&out);

            struct OnHandleCtx {
                const ToolRunLoopHandleCallback& cb;
            };
            OnHandleCtx ctx{onHandle};
            auto onHandlePublished = [](uint64_t handle, void* userData) {
                auto* c = static_cast<OnHandleCtx*>(userData);
                if (!c || !c->cb) {
                    return;
                }
                try {
                    c->cb(static_cast<double>(handle));
                } catch (...) {
                    LOGE("toolRunLoopProtoWithHandle: onHandle callback threw");
                }
            };

            const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
            rac_result_t rc = rac_tool_calling_run_loop_proto(
                data,
                bytes.size(),
                toolRunLoopExecuteCallback,
                &state,
                onHandlePublished,
                &ctx,
                &out);

            if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
                LOGE("toolRunLoopProtoWithHandle: rc=%d", rc);
                rac_proto_buffer_free(&out);
                throw std::runtime_error(
                    "toolRunLoopProtoWithHandle: commons call failed rc=" +
                    std::to_string(rc));
            }

            return copyRequiredToolsProtoBuffer(out, "toolRunLoopProtoWithHandle");
        });
}

// Cancel an in-flight tool-calling run loop. Idempotent per the
// commons contract — a stale or already-retired handle still returns
// RAC_SUCCESS, so callers can wire this directly to AbortSignal abort events.
std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::toolRunLoopCancelProto(
    double runLoopHandle) {
    return Promise<bool>::async([runLoopHandle]() -> bool {
        const auto handle = static_cast<uint64_t>(runLoopHandle);
        rac_result_t rc = rac_tool_calling_run_loop_cancel_proto(handle);
        if (rc != RAC_SUCCESS) {
            LOGE("toolRunLoopCancelProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::structuredOutputParseProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes, rac_structured_output_parse_proto, "structuredOutputParseProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::structuredOutputPreparePromptProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes,
            rac_structured_output_prepare_prompt_proto,
            "structuredOutputPreparePromptProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::structuredOutputValidateProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes, rac_structured_output_validate_proto, "structuredOutputValidateProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::structuredOutputGenerateProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes, rac_structured_output_generate_proto, "structuredOutputGenerateProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::structuredOutputGenerateStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<void>::async([bytes = std::move(bytes), onEventBytes]() {
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onEventBytes);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = rac_structured_output_generate_stream_proto(
            data, bytes.size(), toolsProtoBytesCallback, callback.get());
        if (rc != RAC_SUCCESS) {
            LOGE("structuredOutputGenerateStreamProto: rc=%d", rc);
        }
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::structuredOutputSchemaToJsonProto(
    const std::shared_ptr<ArrayBuffer>& schemaBytes) {
    auto bytes = copyToolsArrayBufferBytes(schemaBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callCommonsBufferProto(
            bytes,
            rac_structured_output_schema_to_json_proto,
            "structuredOutputSchemaToJsonProto");
    });
}

// =============================================================================
// RAG Pipeline
// =============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragCreatePipelineProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyToolsArrayBufferBytes(configBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        // Hold the mutex across destroy + create + install so concurrent
        // callers cannot interleave and leak a session (Kotlin CppBridgeRAG
        // serializes the same sequence with @Synchronized).
        std::lock_guard<std::mutex> lock(g_ragProtoMutex);
        if (g_ragProtoSession) {
            rac_rag_session_destroy_proto(g_ragProtoSession);
            g_ragProtoSession = nullptr;
        }

        rac_handle_t session = nullptr;
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = rac_rag_session_create_proto(data, bytes.size(), &session);
        if (rc != RAC_SUCCESS || !session) {
            LOGE("ragCreatePipelineProto: rc=%d", rc);
            return false;
        }
        g_ragProtoSession = session;
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragDestroyPipelineProto() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t session = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_ragProtoMutex);
            session = g_ragProtoSession;
            g_ragProtoSession = nullptr;
        }
        if (session) {
            rac_rag_session_destroy_proto(session);
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragIngestProto(const std::shared_ptr<ArrayBuffer>& documentBytes) {
    auto bytes = copyToolsArrayBufferBytes(documentBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callRagBufferProto(bytes, rac_rag_ingest_proto, "ragIngestProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragQueryProto(const std::shared_ptr<ArrayBuffer>& queryBytes) {
    auto bytes = copyToolsArrayBufferBytes(queryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callRagBufferProto(bytes, rac_rag_query_proto, "ragQueryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragClearProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        return callRagStatsProto(rac_rag_clear_proto, "ragClearProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragStatsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        return callRagStatsProto(rac_rag_stats_proto, "ragStatsProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::embeddingsEmbedBatchLifecycleProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = rac_embeddings_embed_batch_lifecycle_proto(
            data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("embeddingsEmbedBatchLifecycleProto: rc=%d", rc);
            rac_proto_buffer_free(&out);
            return emptyToolsProtoBuffer();
        }
        return copyToolsProtoBuffer(out, "embeddingsEmbedBatchLifecycleProto");
    });
}

} // namespace margelo::nitro::runanywhere
