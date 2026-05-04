/**
 * HybridRunAnywhereCore+Tools.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::mutex g_ragProtoMutex;
rac_handle_t g_ragProtoSession = nullptr;

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
        proto_compat::freeBuffer(&protoBuffer);
        return emptyToolsProtoBuffer();
    }
    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyToolsProtoBuffer();
    }
    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

std::shared_ptr<ArrayBuffer> callRagBufferProto(const std::vector<uint8_t>& bytes,
                                                const char* symbolName,
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
    auto fn = proto_compat::symbol<proto_compat::RAGBufferProtoFn>(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyToolsProtoBuffer();
    }
    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(session, data, bytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyToolsProtoBuffer();
    }
    return copyToolsProtoBuffer(out, operation);
}

std::shared_ptr<ArrayBuffer> callRagStatsProto(const char* symbolName,
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
    auto fn = proto_compat::symbol<proto_compat::RAGStatsProtoFn>(symbolName);
    if (!fn) {
        LOGE("%s: %s unavailable", operation, symbolName);
        return emptyToolsProtoBuffer();
    }
    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    rac_result_t rc = fn(session, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyToolsProtoBuffer();
    }
    return copyToolsProtoBuffer(out, operation);
}

rac_handle_t handleFromDouble(double handle) {
    return reinterpret_cast<rac_handle_t>(
        static_cast<uintptr_t>(static_cast<int64_t>(handle)));
}

double doubleFromHandle(rac_handle_t handle) {
    return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
}

} // namespace

// Tool Calling and RAG
// ============================================================================
// Tool Calling
//
// ARCHITECTURE:
// - Commons C ABI (rac_tool_call_*): SINGLE SOURCE OF TRUTH for parsing and
//   prompt formatting. Shared by all SDK frontends (Swift/Kotlin/Flutter/Web/RN).
// - ToolCallingBridge: Thin C++ wrapper that marshals std::string <-> C ABI.
// - TypeScript (RunAnywhere+ToolCalling.ts): Registry, executor storage,
//   orchestration. Executors stay in TS because they need JS APIs (fetch, etc.).
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::parseToolCallFromOutput(const std::string& llmOutput) {
    return Promise<std::string>::async([llmOutput]() -> std::string {
        LOGD("parseToolCallFromOutput: input length=%zu", llmOutput.length());
        return ::runanywhere::bridges::ToolCallingBridge::shared().parseToolCall(llmOutput);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::formatToolsForPrompt(
    const std::string& toolsJson,
    const std::string& format
) {
    return Promise<std::string>::async([toolsJson, format]() -> std::string {
        LOGD("formatToolsForPrompt: tools length=%zu, format=%s", toolsJson.length(), format.c_str());
        return ::runanywhere::bridges::ToolCallingBridge::shared().formatToolsPrompt(toolsJson, format);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::buildInitialPrompt(
    const std::string& userPrompt,
    const std::string& toolsJson,
    const std::string& optionsJson
) {
    return Promise<std::string>::async([userPrompt, toolsJson, optionsJson]() -> std::string {
        LOGD("buildInitialPrompt: prompt length=%zu, tools length=%zu",
             userPrompt.length(), toolsJson.length());
        return ::runanywhere::bridges::ToolCallingBridge::shared().buildInitialPrompt(
            userPrompt, toolsJson, optionsJson);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::buildFollowupPrompt(
    const std::string& originalPrompt,
    const std::string& toolsPrompt,
    const std::string& toolName,
    const std::string& resultJson,
    bool keepToolsAvailable
) {
    return Promise<std::string>::async([originalPrompt, toolsPrompt, toolName, resultJson, keepToolsAvailable]() -> std::string {
        LOGD("buildFollowupPrompt: tool=%s, keepTools=%d", toolName.c_str(), keepToolsAvailable);
        return ::runanywhere::bridges::ToolCallingBridge::shared().buildFollowupPrompt(
            originalPrompt, toolsPrompt, toolName, resultJson, keepToolsAvailable);
    });
}

// =============================================================================
// RAG Pipeline
// =============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragCreatePipeline(const std::string& configJson) {
    return Promise<bool>::async([configJson]() {
        return ::runanywhere::bridges::RAGBridge::shared().createPipeline(configJson);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragDestroyPipeline() {
    return Promise<bool>::async([]() {
        return ::runanywhere::bridges::RAGBridge::shared().destroyPipeline();
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragAddDocument(const std::string& text, const std::string& metadataJson) {
    return Promise<bool>::async([text, metadataJson]() {
        return ::runanywhere::bridges::RAGBridge::shared().addDocument(text, metadataJson);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragAddDocumentsBatch(const std::string& documentsJson) {
    return Promise<bool>::async([documentsJson]() {
        return ::runanywhere::bridges::RAGBridge::shared().addDocumentsBatch(documentsJson);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::ragQuery(const std::string& queryJson) {
    return Promise<std::string>::async([queryJson]() {
        return ::runanywhere::bridges::RAGBridge::shared().query(queryJson);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragClearDocuments() {
    return Promise<bool>::async([]() {
        return ::runanywhere::bridges::RAGBridge::shared().clearDocuments();
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::ragGetDocumentCount() {
    return Promise<double>::async([]() {
        return ::runanywhere::bridges::RAGBridge::shared().getDocumentCount();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::ragGetStatistics() {
    return Promise<std::string>::async([]() {
        return ::runanywhere::bridges::RAGBridge::shared().getStatistics();
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragCreatePipelineProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyToolsArrayBufferBytes(configBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        auto createFn = proto_compat::symbol<proto_compat::RAGSessionCreateProtoFn>(
            "rac_rag_session_create_proto");
        if (!createFn) {
            LOGE("ragCreatePipelineProto: rac_rag_session_create_proto unavailable");
            return false;
        }

        auto destroyFn = proto_compat::symbol<proto_compat::RAGSessionDestroyProtoFn>(
            "rac_rag_session_destroy_proto");
        {
            std::lock_guard<std::mutex> lock(g_ragProtoMutex);
            if (g_ragProtoSession && destroyFn) {
                destroyFn(g_ragProtoSession);
                g_ragProtoSession = nullptr;
            }
        }

        rac_handle_t session = nullptr;
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = createFn(data, bytes.size(), &session);
        if (rc != RAC_SUCCESS || !session) {
            LOGE("ragCreatePipelineProto: rc=%d", rc);
            return false;
        }
        {
            std::lock_guard<std::mutex> lock(g_ragProtoMutex);
            g_ragProtoSession = session;
        }
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ragDestroyPipelineProto() {
    return Promise<bool>::async([]() -> bool {
        auto destroyFn = proto_compat::symbol<proto_compat::RAGSessionDestroyProtoFn>(
            "rac_rag_session_destroy_proto");
        if (!destroyFn) {
            LOGE("ragDestroyPipelineProto: rac_rag_session_destroy_proto unavailable");
            return false;
        }
        rac_handle_t session = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_ragProtoMutex);
            session = g_ragProtoSession;
            g_ragProtoSession = nullptr;
        }
        if (session) {
            destroyFn(session);
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragIngestProto(const std::shared_ptr<ArrayBuffer>& documentBytes) {
    auto bytes = copyToolsArrayBufferBytes(documentBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callRagBufferProto(bytes, "rac_rag_ingest_proto", "ragIngestProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragQueryProto(const std::shared_ptr<ArrayBuffer>& queryBytes) {
    auto bytes = copyToolsArrayBufferBytes(queryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callRagBufferProto(bytes, "rac_rag_query_proto", "ragQueryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragClearProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        return callRagStatsProto("rac_rag_clear_proto", "ragClearProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ragStatsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        return callRagStatsProto("rac_rag_stats_proto", "ragStatsProto");
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::embeddingsCreateProto(
    const std::string& modelId,
    const std::optional<std::string>& configJson) {
    return Promise<double>::async([modelId, configJson]() -> double {
        rac_handle_t handle = nullptr;
        rac_result_t rc = static_cast<rac_result_t>(-1);
        if (configJson.has_value()) {
            auto createWithConfig =
                proto_compat::symbol<proto_compat::EmbeddingsCreateWithConfigFn>(
                    "rac_embeddings_create_with_config");
            if (!createWithConfig) {
                LOGE("embeddingsCreateProto: rac_embeddings_create_with_config unavailable");
                return 0;
            }
            rc = createWithConfig(modelId.c_str(), configJson->c_str(), &handle);
        } else {
            auto createFn = proto_compat::symbol<proto_compat::EmbeddingsCreateFn>(
                "rac_embeddings_create");
            if (!createFn) {
                LOGE("embeddingsCreateProto: rac_embeddings_create unavailable");
                return 0;
            }
            rc = createFn(modelId.c_str(), &handle);
        }
        if (rc != RAC_SUCCESS || !handle) {
            LOGE("embeddingsCreateProto: create rc=%d", rc);
            return 0;
        }

        if (auto initFn = proto_compat::symbol<proto_compat::EmbeddingsInitializeFn>(
                "rac_embeddings_initialize")) {
            rc = initFn(handle, modelId.c_str());
            if (rc != RAC_SUCCESS) {
                LOGE("embeddingsCreateProto: initialize rc=%d", rc);
                if (auto destroyFn = proto_compat::symbol<proto_compat::EmbeddingsDestroyFn>(
                        "rac_embeddings_destroy")) {
                    destroyFn(handle);
                }
                return 0;
            }
        }
        return doubleFromHandle(handle);
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::embeddingsEmbedBatchProto(
    double handle,
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyToolsArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [nativeHandle = handleFromDouble(handle), bytes = std::move(bytes)]() {
        auto fn = proto_compat::symbol<proto_compat::EmbeddingsEmbedBatchProtoFn>(
            "rac_embeddings_embed_batch_proto");
        if (!nativeHandle || !fn) {
            LOGE("embeddingsEmbedBatchProto: handle or proto ABI unavailable");
            return emptyToolsProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(nativeHandle, data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("embeddingsEmbedBatchProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyToolsProtoBuffer();
        }
        return copyToolsProtoBuffer(out, "embeddingsEmbedBatchProto");
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::embeddingsDestroyProto(double handle) {
    return Promise<void>::async([nativeHandle = handleFromDouble(handle)]() {
        auto fn = proto_compat::symbol<proto_compat::EmbeddingsDestroyFn>(
            "rac_embeddings_destroy");
        if (!nativeHandle || !fn) {
            LOGE("embeddingsDestroyProto: handle or rac_embeddings_destroy unavailable");
            return;
        }
        fn(nativeHandle);
    });
}

} // namespace margelo::nitro::runanywhere
