/**
 * HybridRunAnywhereCore+Tools.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

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

} // namespace margelo::nitro::runanywhere
