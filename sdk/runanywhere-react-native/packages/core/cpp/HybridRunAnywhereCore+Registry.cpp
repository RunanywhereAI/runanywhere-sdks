/**
 * HybridRunAnywhereCore+Registry.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Model Registry and Compatibility
// ============================================================================
// Model Registry
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getAvailableModels() {
    return Promise<std::string>::async([]() -> std::string {
        try {
            auto models = ModelRegistryBridge::shared().getAllModels();

            LOGI("getAvailableModels: Building JSON for %zu models", models.size());

            std::string result = "[";
            for (size_t i = 0; i < models.size(); i++) {
                if (i > 0) result += ",";
                const auto& m = models[i];
                std::string categoryStr = "unknown";
                switch (m.category) {
                    case RAC_MODEL_CATEGORY_LANGUAGE: categoryStr = "language"; break;
                    case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION: categoryStr = "speech-recognition"; break;
                    case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS: categoryStr = "speech-synthesis"; break;
                    case RAC_MODEL_CATEGORY_VISION: categoryStr = "vision"; break;
                    case RAC_MODEL_CATEGORY_IMAGE_GENERATION: categoryStr = "image-generation"; break;
                    case RAC_MODEL_CATEGORY_AUDIO: categoryStr = "audio"; break;
                    case RAC_MODEL_CATEGORY_MULTIMODAL: categoryStr = "multimodal"; break;
                    case RAC_MODEL_CATEGORY_EMBEDDING: categoryStr = "embedding"; break;
                    default: categoryStr = "unknown"; break;
                }
                std::string formatStr = "unknown";
                switch (m.format) {
                    case RAC_MODEL_FORMAT_GGUF: formatStr = "gguf"; break;
                    case RAC_MODEL_FORMAT_ONNX: formatStr = "onnx"; break;
                    case RAC_MODEL_FORMAT_ORT: formatStr = "ort"; break;
                    case RAC_MODEL_FORMAT_BIN: formatStr = "bin"; break;
                    default: formatStr = "unknown"; break;
                }
                std::string frameworkStr = "unknown";
                switch (m.framework) {
                    case RAC_FRAMEWORK_LLAMACPP: frameworkStr = "LlamaCpp"; break;
                    case RAC_FRAMEWORK_ONNX: frameworkStr = "ONNX"; break;
#ifdef __APPLE__
                    case RAC_FRAMEWORK_COREML: frameworkStr = "CoreML"; break;
#endif
                    case RAC_FRAMEWORK_FOUNDATION_MODELS: frameworkStr = "FoundationModels"; break;
                    case RAC_FRAMEWORK_SYSTEM_TTS: frameworkStr = "SystemTTS"; break;
                    case 11: frameworkStr = "Genie"; break; // RAC_FRAMEWORK_GENIE
                    default: frameworkStr = "unknown"; break;
                }

                result += buildJsonObject({
                    {"id", jsonString(m.id)},
                    {"name", jsonString(m.name)},
                    {"localPath", jsonString(m.localPath)},
                    {"downloadURL", jsonString(m.downloadUrl)},
                    {"category", jsonString(categoryStr)},
                    {"format", jsonString(formatStr)},
                    {"preferredFramework", jsonString(frameworkStr)},
                    {"compatibleFrameworks", "[" + jsonString(frameworkStr) + "]"},
                    {"downloadSize", std::to_string(m.downloadSize)},
                    {"memoryRequired", std::to_string(m.memoryRequired)},
                    {"supportsThinking", m.supportsThinking ? "true" : "false"},
                    {"isDownloaded", m.isDownloaded ? "true" : "false"},
                    {"isAvailable", "true"}
                });
            }
            result += "]";

            LOGD("getAvailableModels: JSON length=%zu", result.length());
            return result;
        } catch (const std::exception& e) {
            LOGE("getAvailableModels exception: %s", e.what());
            return "[]";
        } catch (...) {
            LOGE("getAvailableModels unknown exception");
            return "[]";
        }
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelInfo(
    const std::string& modelId) {
    return Promise<std::string>::async([modelId]() -> std::string {
        auto model = ModelRegistryBridge::shared().getModel(modelId);
        if (!model.has_value()) {
            return "{}";
        }

        const auto& m = model.value();

        // Convert enums to strings (same as getAvailableModels)
        std::string categoryStr = "unknown";
        switch (m.category) {
            case RAC_MODEL_CATEGORY_LANGUAGE: categoryStr = "language"; break;
            case RAC_MODEL_CATEGORY_SPEECH_RECOGNITION: categoryStr = "speech-recognition"; break;
            case RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS: categoryStr = "speech-synthesis"; break;
            case RAC_MODEL_CATEGORY_AUDIO: categoryStr = "audio"; break;
            case RAC_MODEL_CATEGORY_VISION: categoryStr = "vision"; break;
            case RAC_MODEL_CATEGORY_IMAGE_GENERATION: categoryStr = "image-generation"; break;
            case RAC_MODEL_CATEGORY_MULTIMODAL: categoryStr = "multimodal"; break;
            case RAC_MODEL_CATEGORY_EMBEDDING: categoryStr = "embedding"; break;
            default: categoryStr = "unknown"; break;
        }
        std::string formatStr = "unknown";
        switch (m.format) {
            case RAC_MODEL_FORMAT_GGUF: formatStr = "gguf"; break;
            case RAC_MODEL_FORMAT_ONNX: formatStr = "onnx"; break;
            case RAC_MODEL_FORMAT_ORT: formatStr = "ort"; break;
            case RAC_MODEL_FORMAT_BIN: formatStr = "bin"; break;
            default: formatStr = "unknown"; break;
        }
        std::string frameworkStr = "unknown";
        switch (m.framework) {
            case RAC_FRAMEWORK_LLAMACPP: frameworkStr = "LlamaCpp"; break;
            case RAC_FRAMEWORK_ONNX: frameworkStr = "ONNX"; break;
#ifdef __APPLE__
            case RAC_FRAMEWORK_COREML: frameworkStr = "CoreML"; break;
#endif
            case RAC_FRAMEWORK_FOUNDATION_MODELS: frameworkStr = "FoundationModels"; break;
            case RAC_FRAMEWORK_SYSTEM_TTS: frameworkStr = "SystemTTS"; break;
            case 11: frameworkStr = "Genie"; break; // RAC_FRAMEWORK_GENIE
            default: frameworkStr = "unknown"; break;
        }

        return buildJsonObject({
            {"id", jsonString(m.id)},
            {"name", jsonString(m.name)},
            {"description", jsonString(m.description)},
            {"localPath", jsonString(m.localPath)},
            {"downloadURL", jsonString(m.downloadUrl)},  // Fixed: downloadURL (capital URL) to match TypeScript
            {"category", jsonString(categoryStr)},       // String for TypeScript
            {"format", jsonString(formatStr)},           // String for TypeScript
            {"preferredFramework", jsonString(frameworkStr)}, // String for TypeScript (preferredFramework key)
            {"downloadSize", std::to_string(m.downloadSize)},
            {"memoryRequired", std::to_string(m.memoryRequired)},
            {"contextLength", std::to_string(m.contextLength)},
            {"supportsThinking", m.supportsThinking ? "true" : "false"},
            {"isDownloaded", m.isDownloaded ? "true" : "false"},
            {"isAvailable", "true"}  // Added isAvailable field
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isModelDownloaded(
    const std::string& modelId) {
    return Promise<bool>::async([modelId]() -> bool {
        return ModelRegistryBridge::shared().isModelDownloaded(modelId);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getModelPath(
    const std::string& modelId) {
    return Promise<std::string>::async([modelId]() -> std::string {
        auto path = ModelRegistryBridge::shared().getModelPath(modelId);
        return path.value_or("");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::registerModel(
    const std::string& modelJson) {
    return Promise<bool>::async([modelJson]() -> bool {
        LOGI("Registering model from JSON: %.200s", modelJson.c_str());

        ModelInfo model;
        model.id = extractStringValue(modelJson, "id");
        model.name = extractStringValue(modelJson, "name");
        model.description = extractStringValue(modelJson, "description");
        model.localPath = extractStringValue(modelJson, "localPath");

        // Support both TypeScript naming (downloadURL) and C++ naming (downloadUrl)
        model.downloadUrl = extractStringValue(modelJson, "downloadURL");
        if (model.downloadUrl.empty()) {
            model.downloadUrl = extractStringValue(modelJson, "downloadUrl");
        }

        model.downloadSize = extractIntValue(modelJson, "downloadSize", 0);
        model.memoryRequired = extractIntValue(modelJson, "memoryRequired", 0);
        model.contextLength = extractIntValue(modelJson, "contextLength", 0);
        model.supportsThinking = extractBoolValue(modelJson, "supportsThinking", false);

        // Handle category - could be string (TypeScript) or int
        std::string categoryStr = extractStringValue(modelJson, "category");
        if (!categoryStr.empty()) {
            model.category = categoryFromString(categoryStr);
        } else {
            model.category = static_cast<rac_model_category_t>(extractIntValue(modelJson, "category", RAC_MODEL_CATEGORY_UNKNOWN));
        }

        // Handle format - could be string (TypeScript) or int
        std::string formatStr = extractStringValue(modelJson, "format");
        if (!formatStr.empty()) {
            model.format = formatFromString(formatStr);
        } else {
            model.format = static_cast<rac_model_format_t>(extractIntValue(modelJson, "format", RAC_MODEL_FORMAT_UNKNOWN));
        }

        // Handle framework - prefer string extraction for TypeScript compatibility
        std::string frameworkStr = extractStringValue(modelJson, "preferredFramework");
        if (!frameworkStr.empty()) {
            model.framework = frameworkFromString(frameworkStr);
        } else {
            frameworkStr = extractStringValue(modelJson, "framework");
            if (!frameworkStr.empty()) {
                model.framework = frameworkFromString(frameworkStr);
            } else {
                model.framework = static_cast<rac_inference_framework_t>(extractIntValue(modelJson, "preferredFramework", RAC_FRAMEWORK_UNKNOWN));
            }
        }

        LOGI("Registering model: id=%s, name=%s, framework=%d, category=%d",
             model.id.c_str(), model.name.c_str(), model.framework, model.category);

        rac_result_t result = ModelRegistryBridge::shared().addModel(model);

        if (result == RAC_SUCCESS) {
            LOGI("✅ Model registered successfully: %s", model.id.c_str());
        } else {
            LOGE("❌ Model registration failed: %s, result=%d", model.id.c_str(), result);
        }

        return result == RAC_SUCCESS;
    });
}

// ============================================================================
// Compatibility Service
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::checkCompatibility(
    const std::string& modelId) {
    return Promise<std::string>::async([modelId]() -> std::string {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("Model registry not initialized");
            return "{}";
        }

        // Delegate to CompatibilityBridge - it handles querying device capabilities
        auto result = CompatibilityBridge::checkCompatibility(modelId, registryHandle);

        return buildJsonObject({
            {"isCompatible", result.isCompatible ? "true" : "false"},
            {"canRun", result.canRun ? "true" : "false"},
            {"canFit", result.canFit ? "true" : "false"},
            {"requiredMemory", std::to_string(result.requiredMemory)},
            {"availableMemory", std::to_string(result.availableMemory)},
            {"requiredStorage", std::to_string(result.requiredStorage)},
            {"availableStorage", std::to_string(result.availableStorage)}
        });
    });
}

// ============================================================================
// Refresh (T4.9) — delegates to rac_model_registry_refresh in commons.
// Discovery callbacks are left NULL here: rescan_local / prune_orphans need
// platform file-IO stubs that the RN bridge does not wire today; those flags
// are honoured at the C ABI layer (they just no-op without callbacks).
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::refreshModelRegistry(
    bool includeRemoteCatalog, bool rescanLocal, bool pruneOrphans) {
    return Promise<bool>::async([includeRemoteCatalog, rescanLocal,
                                 pruneOrphans]() -> bool {
        auto registryHandle = ModelRegistryBridge::shared().getHandle();
        if (!registryHandle) {
            LOGE("refreshModelRegistry: registry not initialized");
            return false;
        }

        rac_model_registry_refresh_opts_t opts{};
        opts.include_remote_catalog = includeRemoteCatalog ? RAC_TRUE : RAC_FALSE;
        opts.rescan_local = rescanLocal ? RAC_TRUE : RAC_FALSE;
        opts.prune_orphans = pruneOrphans ? RAC_TRUE : RAC_FALSE;
        opts.discovery_callbacks = nullptr;

        rac_result_t rc = rac_model_registry_refresh(registryHandle, opts);
        if (rc != RAC_SUCCESS) {
            LOGE("refreshModelRegistry: rc=%d", rc);
            return false;
        }
        return true;
    });
}

} // namespace margelo::nitro::runanywhere
