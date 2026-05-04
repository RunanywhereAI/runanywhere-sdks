/**
 * HybridRunAnywhereCore+Voice.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

std::vector<uint8_t> copyVoiceArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
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

std::shared_ptr<ArrayBuffer> emptyVoiceProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

std::shared_ptr<ArrayBuffer> copyVoiceProtoBuffer(rac_proto_buffer_t& protoBuffer,
                                                  const char* operation) {
    if (protoBuffer.status != RAC_SUCCESS) {
        if (protoBuffer.error_message) {
            LOGE("%s proto error: %s", operation, protoBuffer.error_message);
        }
        proto_compat::freeBuffer(&protoBuffer);
        return emptyVoiceProtoBuffer();
    }
    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyVoiceProtoBuffer();
    }
    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

void protoBytesCallback(const uint8_t* protoBytes, size_t protoSize, void* userData) {
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
        LOGE("proto callback dispatch failed");
    }
}

std::vector<float> copyVADSamples(const std::vector<uint8_t>& bytes) {
    std::vector<float> samples;
    if (bytes.empty()) {
        return samples;
    }
    if (bytes.size() % sizeof(float) == 0) {
        samples.resize(bytes.size() / sizeof(float));
        std::memcpy(samples.data(), bytes.data(), bytes.size());
        return samples;
    }
    if (bytes.size() % sizeof(int16_t) == 0) {
        size_t count = bytes.size() / sizeof(int16_t);
        samples.resize(count);
        const auto* pcm = reinterpret_cast<const int16_t*>(bytes.data());
        for (size_t i = 0; i < count; ++i) {
            samples[i] = static_cast<float>(pcm[i]) / 32768.0f;
        }
    }
    return samples;
}

std::mutex g_vadActivityCallbackMutex;
std::function<void(const std::shared_ptr<ArrayBuffer>&)> g_vadActivityCallback;

void vadActivityProtoCallback(const uint8_t* protoBytes, size_t protoSize, void*) {
    if (!protoBytes || protoSize == 0) {
        return;
    }
    std::function<void(const std::shared_ptr<ArrayBuffer>&)> callback;
    {
        std::lock_guard<std::mutex> lock(g_vadActivityCallbackMutex);
        callback = g_vadActivityCallback;
    }
    if (!callback) {
        return;
    }
    try {
        callback(ArrayBuffer::copy(protoBytes, protoSize));
    } catch (...) {
        LOGE("vad activity callback dispatch failed");
    }
}

} // namespace

// LLM/STT/TTS/VAD/Voice Agent
// ============================================================================
// LLM Capability (Backend-Agnostic)
// Calls rac_llm_component_* APIs - works with any registered backend
// Uses a global LLM component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global LLM component handle - shared across all instances
static rac_handle_t g_llm_component_handle = nullptr;
static std::mutex g_llm_mutex;

static rac_handle_t getGlobalLLMHandle() {
    std::lock_guard<std::mutex> lock(g_llm_mutex);
    if (g_llm_component_handle == nullptr) {
        rac_result_t result = rac_llm_component_create(&g_llm_component_handle);
        if (result != RAC_SUCCESS) {
            g_llm_component_handle = nullptr;
        }
    }
    return g_llm_component_handle;
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getLLMHandle() {
    return Promise<double>::async([]() -> double {
        rac_handle_t handle = getGlobalLLMHandle();
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTextModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, configJson]() -> bool {
        LOGI("Loading text model: %s", modelPath.c_str());

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            setLastError("Failed to create LLM component. Is an LLM backend registered?");
            throw std::runtime_error("LLM backend not registered. Install @runanywhere/llamacpp.");
        }

        // Load the model
        rac_result_t result = rac_llm_component_load_model(handle, modelPath.c_str(), modelPath.c_str(), modelPath.c_str());
        if (result != RAC_SUCCESS) {
            setLastError("Failed to load model: " + std::to_string(result));
            throw std::runtime_error("Failed to load text model: " + std::to_string(result));
        }

        LOGI("Text model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTextModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_llm_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTextModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTextModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        rac_llm_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_llm_mutex);
            g_llm_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, prompt, optionsJson]() -> std::string {
        LOGI("Generating text...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Parse options
        int maxTokens = 256;
        float temperature = 0.7f;
        std::string systemPrompt;
        if (optionsJson.has_value()) {
            maxTokens = extractIntValue(optionsJson.value(), "max_tokens", 256);
            temperature = static_cast<float>(extractDoubleValue(optionsJson.value(), "temperature", 0.7));
            systemPrompt = extractStringValue(optionsJson.value(), "system_prompt", "");
        }

        rac_llm_options_t options = {};
        options.max_tokens = maxTokens;
        options.temperature = temperature;
        options.top_p = 0.9f;
        options.system_prompt = systemPrompt.empty() ? nullptr : systemPrompt.c_str();

        rac_llm_result_t llmResult = {};
        rac_result_t result = rac_llm_component_generate(handle, prompt.c_str(), &options, &llmResult);

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Text generation failed: " + std::to_string(result));
        }

        std::string text = llmResult.text ? llmResult.text : "";
        int tokensUsed = llmResult.completion_tokens;
        double latencyMs = llmResult.total_time_ms;

        rac_llm_result_free(&llmResult);

        return buildJsonObject({
            {"text", jsonString(text)},
            {"tokensUsed", std::to_string(tokensUsed)},
            {"modelUsed", jsonString("llm")},
            {"latencyMs", std::to_string(latencyMs)}
        });
    });
}

// Streaming context for LLM callbacks
struct LLMStreamContext {
    std::function<void(const std::string&, bool)> callback;
    std::string accumulatedText;
    int tokenCount = 0;
    bool hasError = false;
    std::string errorMessage;
    rac_llm_result_t finalResult = {};
};

// Token callback for streaming
static rac_bool_t llmStreamTokenCallback(const char* token, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx || !token) return RAC_FALSE;

    std::string tokenStr(token);
    ctx->accumulatedText += tokenStr;
    ctx->tokenCount++;

    // Call the JS callback with partial text (not final)
    if (ctx->callback) {
        ctx->callback(tokenStr, false);
    }

    return RAC_TRUE; // Continue streaming
}

// Complete callback for streaming
static void llmStreamCompleteCallback(const rac_llm_result_t* result, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx) return;

    if (result) {
        ctx->finalResult = *result;
    }

    // Call callback with final signal
    if (ctx->callback) {
        ctx->callback("", true);
    }
}

// Error callback for streaming
static void llmStreamErrorCallback(rac_result_t errorCode, const char* errorMessage, void* userData) {
    auto* ctx = static_cast<LLMStreamContext*>(userData);
    if (!ctx) return;

    ctx->hasError = true;
    ctx->errorMessage = errorMessage ? std::string(errorMessage) : "Unknown streaming error";
    LOGE("LLM streaming error: %d - %s", errorCode, ctx->errorMessage.c_str());
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
    return Promise<std::string>::async([this, prompt, optionsJson, callback]() -> std::string {
        LOGI("Streaming text generation...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Parse options
        std::string systemPrompt = extractStringValue(optionsJson, "system_prompt", "");

        rac_llm_options_t options = {};
        options.max_tokens = extractIntValue(optionsJson, "max_tokens", 256);
        options.temperature = static_cast<float>(extractDoubleValue(optionsJson, "temperature", 0.7));
        options.top_p = 0.9f;
        options.system_prompt = systemPrompt.empty() ? nullptr : systemPrompt.c_str();

        // Create streaming context
        LLMStreamContext ctx;
        ctx.callback = callback;

        // Use proper streaming API
        rac_result_t result = rac_llm_component_generate_stream(
            handle,
            prompt.c_str(),
            &options,
            llmStreamTokenCallback,
            llmStreamCompleteCallback,
            llmStreamErrorCallback,
            &ctx
        );

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Streaming generation failed: " + std::to_string(result));
        }

        if (ctx.hasError) {
            throw std::runtime_error("Streaming error: " + ctx.errorMessage);
        }

        LOGI("Streaming complete: %zu chars, %d tokens", ctx.accumulatedText.size(), ctx.tokenCount);

        return buildJsonObject({
            {"text", jsonString(ctx.accumulatedText)},
            {"tokensUsed", std::to_string(ctx.tokenCount)}
        });
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelGeneration() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            return false;
        }
        rac_llm_component_cancel(handle);
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::generateStructured(
    const std::string& prompt,
    const std::string& schema,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, prompt, schema, optionsJson]() -> std::string {
        LOGI("Generating structured output...");

        rac_handle_t handle = getGlobalLLMHandle();
        if (!handle) {
            throw std::runtime_error("LLM component not available. Is an LLM backend registered?");
        }

        if (rac_llm_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No LLM model loaded. Call loadTextModel first.");
        }

        // Prepare the prompt with the schema embedded
        rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
        config.json_schema = schema.c_str();
        config.include_schema_in_prompt = RAC_TRUE;

        char* preparedPrompt = nullptr;
        rac_result_t prepResult = rac_structured_output_prepare_prompt(prompt.c_str(), &config, &preparedPrompt);
        if (prepResult != RAC_SUCCESS || !preparedPrompt) {
            throw std::runtime_error("Failed to prepare structured output prompt");
        }

        // Generate with the prepared prompt
        std::string systemPrompt;
        rac_llm_options_t options = {};
        if (optionsJson.has_value()) {
            options.max_tokens = extractIntValue(optionsJson.value(), "max_tokens", 512);
            options.temperature = static_cast<float>(extractDoubleValue(optionsJson.value(), "temperature", 0.7));
            systemPrompt = extractStringValue(optionsJson.value(), "system_prompt", "");
        } else {
            options.max_tokens = 512;
            options.temperature = 0.7f;
        }
        options.system_prompt = systemPrompt.empty() ? nullptr : systemPrompt.c_str();

        rac_llm_result_t llmResult = {};
        rac_result_t result = rac_llm_component_generate(handle, preparedPrompt, &options, &llmResult);

        free(preparedPrompt);

        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Text generation failed: " + std::to_string(result));
        }

        std::string generatedText;
        if (llmResult.text) {
            generatedText = std::string(llmResult.text);
        }
        rac_llm_result_free(&llmResult);

        // Extract JSON from the generated text
        char* extractedJson = nullptr;
        rac_result_t extractResult = rac_structured_output_extract_json(generatedText.c_str(), &extractedJson, nullptr);

        if (extractResult == RAC_SUCCESS && extractedJson) {
            std::string jsonOutput = std::string(extractedJson);
            free(extractedJson);
            LOGI("Extracted structured JSON: %s", jsonOutput.substr(0, 100).c_str());
            return jsonOutput;
        }

        // If extraction failed, return the raw text (let the caller handle it)
        LOGI("Could not extract JSON, returning raw: %s", generatedText.substr(0, 100).c_str());
        return generatedText;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::llmGenerateProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        auto fn = proto_compat::symbol<proto_compat::LLMGenerateProtoFn>(
            "rac_llm_generate_proto");
        if (!fn) {
            LOGE("llmGenerateProto: rac_llm_generate_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("llmGenerateProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "llmGenerateProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::llmGenerateStreamProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<void>::async([bytes = std::move(bytes), onEventBytes]() {
        auto fn = proto_compat::symbol<proto_compat::LLMGenerateStreamProtoFn>(
            "rac_llm_generate_stream_proto");
        if (!fn) {
            LOGE("llmGenerateStreamProto: rac_llm_generate_stream_proto unavailable");
            return;
        }
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        auto callback = onEventBytes;
        rac_result_t rc = fn(data, bytes.size(), protoBytesCallback, &callback);
        if (rc != RAC_SUCCESS) {
            LOGE("llmGenerateStreamProto: rc=%d", rc);
        }
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::llmCancelProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto fn = proto_compat::symbol<proto_compat::LLMCancelProtoFn>(
            "rac_llm_cancel_proto");
        if (!fn) {
            LOGE("llmCancelProto: rac_llm_cancel_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("llmCancelProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "llmCancelProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraLoadProto(const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_handle_t handle = getGlobalLLMHandle();
        auto fn = proto_compat::symbol<proto_compat::LoRAConfigProtoFn>(
            "rac_lora_load_proto");
        if (!handle || !fn) {
            LOGE("loraLoadProto: LLM handle or rac_lora_load_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("loraLoadProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "loraLoadProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraRemoveProto(const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_handle_t handle = getGlobalLLMHandle();
        auto fn = proto_compat::symbol<proto_compat::LoRAConfigProtoFn>(
            "rac_lora_remove_proto");
        if (!handle || !fn) {
            LOGE("loraRemoveProto: LLM handle or rac_lora_remove_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("loraRemoveProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "loraRemoveProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraClearProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        rac_handle_t handle = getGlobalLLMHandle();
        auto fn = proto_compat::symbol<proto_compat::LoRAClearProtoFn>(
            "rac_lora_clear_proto");
        if (!handle || !fn) {
            LOGE("loraClearProto: LLM handle or rac_lora_clear_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("loraClearProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "loraClearProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCompatibilityProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_handle_t handle = getGlobalLLMHandle();
        auto fn = proto_compat::symbol<proto_compat::LoRAConfigProtoFn>(
            "rac_lora_compatibility_proto");
        if (!handle || !fn) {
            LOGE("loraCompatibilityProto: LLM handle or rac_lora_compatibility_proto unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, bytes.data(), bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("loraCompatibilityProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "loraCompatibilityProto");
    });
}

// ============================================================================
// LLM Thinking (rac_llm_thinking.h) — v3 Phase A10 / GAP 08 #6
//
// Returns JSON so the TS side gets a single, schema-stable value per
// RPC (simpler than fighting Nitro's tuple-return syntax). The TS
// `LlmThinking` class (Phase A10 facade) does the trivial JSON.parse.
// ============================================================================

static std::string jsonEscape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::llmExtractThinking(
    const std::string& text) {
    return Promise<std::string>::async([text]() -> std::string {
        const char* out_response      = nullptr;
        size_t      out_response_len  = 0;
        const char* out_thinking      = nullptr;
        size_t      out_thinking_len  = 0;
        rac_result_t rc = rac_llm_extract_thinking(
            text.c_str(),
            &out_response, &out_response_len,
            &out_thinking, &out_thinking_len);
        if (rc != RAC_SUCCESS) {
            return std::string("{}");
        }
        std::string response = out_response
            ? std::string(out_response, out_response_len) : std::string();
        std::string result;
        result.reserve(response.size() + (out_thinking ? out_thinking_len : 0) + 32);
        result += "{\"response\":\"";
        result += jsonEscape(response);
        if (out_thinking) {
            std::string thinking(out_thinking, out_thinking_len);
            result += "\",\"thinking\":\"";
            result += jsonEscape(thinking);
            result += "\"}";
        } else {
            result += "\",\"thinking\":null}";
        }
        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::llmStripThinking(
    const std::string& text) {
    return Promise<std::string>::async([text]() -> std::string {
        const char* out_stripped     = nullptr;
        size_t      out_stripped_len = 0;
        rac_result_t rc = rac_llm_strip_thinking(
            text.c_str(), &out_stripped, &out_stripped_len);
        if (rc != RAC_SUCCESS || !out_stripped) {
            return std::string();
        }
        return std::string(out_stripped, out_stripped_len);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::llmSplitThinkingTokens(
    double totalCompletionTokens,
    const std::string& responseText,
    const std::string& thinkingText) {
    return Promise<std::string>::async([totalCompletionTokens, responseText,
                                        thinkingText]() -> std::string {
        int32_t thinking_tokens = 0;
        int32_t response_tokens = 0;
        rac_result_t rc = rac_llm_split_thinking_tokens(
            static_cast<int32_t>(totalCompletionTokens),
            responseText.empty() ? nullptr : responseText.c_str(),
            thinkingText.empty() ? nullptr : thinkingText.c_str(),
            &thinking_tokens, &response_tokens);
        if (rc != RAC_SUCCESS) {
            return std::string("{\"thinking\":0,\"response\":0}");
        }
        char buf[96];
        std::snprintf(buf, sizeof(buf),
                      "{\"thinking\":%d,\"response\":%d}",
                      thinking_tokens, response_tokens);
        return std::string(buf);
    });
}

// ============================================================================
// STT Capability (Backend-Agnostic)
// Calls rac_stt_component_* APIs - works with any registered backend
// Uses a global STT component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global STT component handle - shared across all instances
// This ensures model loading state persists even when HybridRunAnywhereCore instances are recreated
static rac_handle_t g_stt_component_handle = nullptr;
static std::mutex g_stt_mutex;

static rac_handle_t getGlobalSTTHandle() {
    std::lock_guard<std::mutex> lock(g_stt_mutex);
    if (g_stt_component_handle == nullptr) {
        rac_result_t result = rac_stt_component_create(&g_stt_component_handle);
        if (result != RAC_SUCCESS) {
            g_stt_component_handle = nullptr;
        }
    }
    return g_stt_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadSTTModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        try {
            LOGI("Loading STT model: %s", modelPath.c_str());

            if (modelPath.empty()) {
                setLastError("STT model path is empty. Download the model first.");
                return false;
            }

            std::string resolvedPath = resolveOnnxModelDirectory(modelPath);

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                setLastError("Failed to create STT component. Is an STT backend registered?");
                return false;
            }

            rac_result_t result = rac_stt_component_load_model(
                handle, resolvedPath.c_str(), resolvedPath.c_str(), modelType.c_str());
            if (result != RAC_SUCCESS) {
                setLastError("Failed to load STT model: " + std::to_string(result));
                return false;
            }

            LOGI("STT model loaded successfully");
            return true;
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("loadSTTModel exception: %s", msg.c_str());
            setLastError(msg);
            return false;
        } catch (...) {
            setLastError("STT model load failed (unknown error)");
            return false;
        }
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isSTTModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_stt_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isSTTModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadSTTModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalSTTHandle();
        if (!handle) {
            return false;
        }
        rac_stt_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_stt_mutex);
            g_stt_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribe(
    const std::string& audioBase64,
    double sampleRate,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, audioBase64, sampleRate, language]() -> std::string {
        try {
            LOGI("Transcribing audio (base64)...");

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                return "{\"error\":\"STT component not available. Is an STT backend registered?\"}";
            }

            if (rac_stt_component_is_loaded(handle) != RAC_TRUE) {
                return "{\"error\":\"No STT model loaded. Call loadSTTModel first.\"}";
            }

            // Decode base64 audio data
            std::vector<uint8_t> audioData = base64Decode(audioBase64);
            if (audioData.empty()) {
                return "{\"error\":\"Failed to decode base64 audio data\"}";
            }

            // Minimum ~0.05s at 16kHz 16-bit to avoid backend crash on tiny input
            if (audioData.size() < 1600) {
                return "{\"text\":\"\",\"confidence\":0.0}";
            }

            LOGI("Decoded %zu bytes of audio data", audioData.size());

            // Set up transcription options
            rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
            options.sample_rate = static_cast<int32_t>(sampleRate > 0 ? sampleRate : 16000);
            options.audio_format = RAC_AUDIO_FORMAT_PCM;
            if (language.has_value() && !language->empty()) {
                options.language = language->c_str();
            }

            // Transcribe
            rac_stt_result_t result = {};
            rac_result_t status = rac_stt_component_transcribe(
                handle,
                audioData.data(),
                audioData.size(),
                &options,
                &result
            );

            if (status != RAC_SUCCESS) {
                rac_stt_result_free(&result);
                return "{\"error\":\"Transcription failed with error code: " + std::to_string(status) + "\"}";
            }

            std::string transcribedText;
            if (result.text) {
                transcribedText = std::string(result.text);
            }
            float confidence = result.confidence;

            rac_stt_result_free(&result);

            LOGI("Transcription result: %s", transcribedText.c_str());
            return "{\"text\":" + jsonString(transcribedText) + ",\"confidence\":" + std::to_string(confidence) + "}";
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("Transcribe exception: %s", msg.c_str());
            return "{\"error\":" + jsonString(msg) + "}";
        } catch (...) {
            return "{\"error\":\"Transcription failed (unknown error)\"}";
        }
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
    return Promise<std::string>::async([this, filePath, language]() -> std::string {
        try {
            LOGI("Transcribing file: %s", filePath.c_str());

            rac_handle_t handle = getGlobalSTTHandle();
            if (!handle) {
                return "{\"error\":\"STT component not available. Is an STT backend registered?\"}";
            }

            if (rac_stt_component_is_loaded(handle) != RAC_TRUE) {
                return "{\"error\":\"No STT model loaded. Call loadSTTModel first.\"}";
            }

            // Open the file
            FILE* file = fopen(filePath.c_str(), "rb");
            if (!file) {
                return "{\"error\":\"Failed to open audio file. Check that the path is valid.\"}";
            }

            // Get file size
            fseek(file, 0, SEEK_END);
            long fileSize = ftell(file);
            fseek(file, 0, SEEK_SET);

            if (fileSize <= 0) {
                fclose(file);
                return "{\"error\":\"Audio file is empty\"}";
            }

            LOGI("File size: %ld bytes", fileSize);

            // Read the entire file into memory
            std::vector<uint8_t> fileData(static_cast<size_t>(fileSize));
            size_t bytesRead = fread(fileData.data(), 1, static_cast<size_t>(fileSize), file);
            fclose(file);

            if (bytesRead != static_cast<size_t>(fileSize)) {
                return "{\"error\":\"Failed to read audio file completely\"}";
            }

            // Parse WAV header to extract audio data
            const uint8_t* data = fileData.data();
            size_t dataSize = fileData.size();
            int32_t sampleRate = 16000;

            if (dataSize < 44) {
                return "{\"error\":\"File too small to be a valid WAV file\"}";
            }
            if (data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F') {
                return "{\"error\":\"Invalid WAV file: missing RIFF header\"}";
            }
            if (data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
                return "{\"error\":\"Invalid WAV file: missing WAVE format\"}";
            }

            size_t pos = 12;
            size_t audioDataOffset = 0;
            size_t audioDataSize = 0;

            while (pos + 8 < dataSize) {
                char chunkId[5] = {0};
                memcpy(chunkId, &data[pos], 4);
                uint32_t chunkSize;
                memcpy(&chunkSize, &data[pos + 4], sizeof(chunkSize));

                if (strcmp(chunkId, "fmt ") == 0) {
                    if (pos + 8 + chunkSize <= dataSize && chunkSize >= 16) {
                        memcpy(&sampleRate, &data[pos + 12], sizeof(sampleRate));
                        if (sampleRate <= 0 || sampleRate > 48000) sampleRate = 16000;
                        LOGI("WAV sample rate: %d Hz", sampleRate);
                    }
                } else if (strcmp(chunkId, "data") == 0) {
                    audioDataOffset = pos + 8;
                    audioDataSize = chunkSize;
                    LOGI("Found audio data: offset=%zu, size=%zu", audioDataOffset, audioDataSize);
                    break;
                }

                pos += 8 + chunkSize;
                if (chunkSize % 2 != 0) pos++;
            }

            if (audioDataSize == 0 || audioDataOffset + audioDataSize > dataSize) {
                return "{\"error\":\"Could not find valid audio data in WAV file\"}";
            }

            // Minimum ~0.1s at 16kHz 16-bit; avoid empty or tiny buffers
            if (audioDataSize < 3200) {
                return "{\"error\":\"Recording too short to transcribe\"}";
            }

            rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
            options.sample_rate = sampleRate;
            options.audio_format = RAC_AUDIO_FORMAT_PCM;
            if (language.has_value() && !language->empty()) {
                options.language = language->c_str();
            }

            LOGI("Transcribing %zu bytes of audio at %d Hz", audioDataSize, sampleRate);

            rac_stt_result_t result = {};
            rac_result_t status = rac_stt_component_transcribe(
                handle,
                &data[audioDataOffset],
                audioDataSize,
                &options,
                &result
            );

            if (status != RAC_SUCCESS) {
                rac_stt_result_free(&result);
                return "{\"error\":\"Transcription failed with error code: " + std::to_string(status) + "\"}";
            }

            std::string transcribedText;
            if (result.text) {
                transcribedText = std::string(result.text);
            }

            rac_stt_result_free(&result);
            LOGI("Transcription result: %s", transcribedText.c_str());
            return "{\"text\":" + jsonString(transcribedText) + ",\"confidence\":0}";
        } catch (const std::exception& e) {
            std::string msg = e.what();
            LOGI("TranscribeFile exception: %s", msg.c_str());
            return "{\"error\":" + jsonString(msg) + "}";
        } catch (...) {
            return "{\"error\":\"Transcription failed (unknown error)\"}";
        }
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::sttTranscribeProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes,
    const std::shared_ptr<ArrayBuffer>& optionsBytes) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [audio = std::move(audio), options = std::move(options)]() {
        rac_handle_t handle = getGlobalSTTHandle();
        auto fn = proto_compat::symbol<proto_compat::STTTranscribeProtoFn>(
            "rac_stt_component_transcribe_proto");
        if (!handle || !fn) {
            LOGE("sttTranscribeProto: STT handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        const void* audioData = audio.empty() ? nullptr : audio.data();
        rac_result_t rc = fn(
            handle,
            audioData,
            audio.size(),
            optionsData,
            options.size(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("sttTranscribeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "sttTranscribeProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::sttTranscribeStreamProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes,
    const std::shared_ptr<ArrayBuffer>& optionsBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onPartialBytes) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<void>::async(
        [audio = std::move(audio), options = std::move(options), onPartialBytes]() {
        rac_handle_t handle = getGlobalSTTHandle();
        auto fn = proto_compat::symbol<proto_compat::STTTranscribeStreamProtoFn>(
            "rac_stt_component_transcribe_stream_proto");
        if (!handle || !fn) {
            LOGE("sttTranscribeStreamProto: STT handle or proto ABI unavailable");
            return;
        }
        auto callback = onPartialBytes;
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        const void* audioData = audio.empty() ? nullptr : audio.data();
        rac_result_t rc = fn(
            handle,
            audioData,
            audio.size(),
            optionsData,
            options.size(),
            protoBytesCallback,
            &callback);
        if (rc != RAC_SUCCESS) {
            LOGE("sttTranscribeStreamProto: rc=%d", rc);
        }
    });
}

// ============================================================================
// TTS Capability (Backend-Agnostic)
// Calls rac_tts_component_* APIs - works with any registered backend
// Uses a global TTS component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global TTS component handle - shared across all instances
static rac_handle_t g_tts_component_handle = nullptr;
static std::mutex g_tts_mutex;

static rac_handle_t getGlobalTTSHandle() {
    std::lock_guard<std::mutex> lock(g_tts_mutex);
    if (g_tts_component_handle == nullptr) {
        rac_result_t result = rac_tts_component_create(&g_tts_component_handle);
        if (result != RAC_SUCCESS) {
            g_tts_component_handle = nullptr;
        }
    }
    return g_tts_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadTTSModel(
    const std::string& modelPath,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath, modelType]() -> bool {
        LOGI("Loading TTS model: path=%s, type=%s", modelPath.c_str(), modelType.c_str());

        std::string resolvedPath = resolveOnnxModelDirectory(modelPath);
        LOGI("TTS resolved path: %s", resolvedPath.c_str());

        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            setLastError("Failed to create TTS component. Is a TTS backend registered?");
            throw std::runtime_error("TTS backend not registered. Install @runanywhere/onnx.");
        }

        rac_tts_config_t config = RAC_TTS_CONFIG_DEFAULT;
        config.model_id = resolvedPath.c_str();
        rac_result_t result = rac_tts_component_configure(handle, &config);
        if (result != RAC_SUCCESS) {
            LOGE("TTS configure failed: %d", result);
            throw std::runtime_error("Failed to configure TTS: " + std::to_string(result));
        }

        std::string voiceId = resolvedPath;
        size_t lastSlash = voiceId.find_last_of('/');
        if (lastSlash != std::string::npos) {
            voiceId = voiceId.substr(lastSlash + 1);
        }

        LOGI("TTS loading voice: id=%s, path=%s", voiceId.c_str(), resolvedPath.c_str());
        result = rac_tts_component_load_voice(handle, resolvedPath.c_str(), voiceId.c_str(), modelType.c_str());
        if (result != RAC_SUCCESS) {
            const char* details = rac_error_get_details();
            std::string errorMsg = "Failed to load TTS voice: " + std::to_string(result);
            if (details && details[0] != '\0') {
                errorMsg += " (" + std::string(details) + ")";
            }
            LOGE("TTS load_voice failed: %d, details: %s", result, details ? details : "none");
            throw std::runtime_error(errorMsg);
        }

        bool isLoaded = rac_tts_component_is_loaded(handle) == RAC_TRUE;
        LOGI("TTS model loaded successfully, isLoaded=%s", isLoaded ? "true" : "false");

        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isTTSModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_tts_component_is_loaded(handle) == RAC_TRUE;
        LOGD("isTTSModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadTTSModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            return false;
        }
        rac_tts_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_tts_mutex);
            g_tts_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::synthesize(
    const std::string& text,
    const std::string& voiceId,
    double speedRate,
    double pitchShift) {
    return Promise<std::string>::async([this, text, voiceId, speedRate, pitchShift]() -> std::string {
        LOGI("Synthesizing speech: %s", text.substr(0, 50).c_str());

        rac_handle_t handle = getGlobalTTSHandle();
        if (!handle) {
            throw std::runtime_error("TTS component not available. Is a TTS backend registered?");
        }

        if (rac_tts_component_is_loaded(handle) != RAC_TRUE) {
            throw std::runtime_error("No TTS model loaded. Call loadTTSModel first.");
        }

        // Set up synthesis options
        rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
        if (!voiceId.empty()) {
            options.voice = voiceId.c_str();
        }
        options.rate = static_cast<float>(speedRate > 0 ? speedRate : 1.0);
        options.pitch = static_cast<float>(pitchShift > 0 ? pitchShift : 1.0);

        // Synthesize
        rac_tts_result_t result = {};
        rac_result_t status = rac_tts_component_synthesize(handle, text.c_str(), &options, &result);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("TTS synthesis failed with error code: " + std::to_string(status));
        }

        if (!result.audio_data || result.audio_size == 0) {
            rac_tts_result_free(&result);
            throw std::runtime_error("TTS synthesis returned no audio data");
        }

        LOGI("TTS synthesis complete: %zu bytes, %d Hz, %lld ms",
             result.audio_size, result.sample_rate, result.duration_ms);

        // Convert audio data to base64
        std::string audioBase64 = base64Encode(
            static_cast<const uint8_t*>(result.audio_data),
            result.audio_size
        );

        const std::string json =
            "{\"audioBase64\":\"" + audioBase64 + "\"," +
            "\"sampleRate\":" + std::to_string(result.sample_rate) + "," +
            "\"durationMs\":" + std::to_string(result.duration_ms) + "," +
            "\"audioSize\":" + std::to_string(result.audio_size) +
            "}";

        rac_tts_result_free(&result);

        return json;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getTTSVoices() {
    return Promise<std::string>::async([]() -> std::string {
        return "[]"; // Return empty array for now
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::cancelTTS() {
    return Promise<bool>::async([]() -> bool {
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::ttsListVoicesProto(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onVoiceBytes) {
    return Promise<bool>::async([onVoiceBytes]() -> bool {
        rac_handle_t handle = getGlobalTTSHandle();
        auto fn = proto_compat::symbol<proto_compat::TTSListVoicesProtoFn>(
            "rac_tts_component_list_voices_proto");
        if (!handle || !fn) {
            LOGE("ttsListVoicesProto: TTS handle or proto ABI unavailable");
            return false;
        }
        auto callback = onVoiceBytes;
        rac_result_t rc = fn(handle, protoBytesCallback, &callback);
        if (rc != RAC_SUCCESS) {
            LOGE("ttsListVoicesProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::ttsSynthesizeProto(
    const std::string& text,
    const std::shared_ptr<ArrayBuffer>& optionsBytes) {
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [text, options = std::move(options)]() {
        rac_handle_t handle = getGlobalTTSHandle();
        auto fn = proto_compat::symbol<proto_compat::TTSSynthesizeProtoFn>(
            "rac_tts_component_synthesize_proto");
        if (!handle || !fn) {
            LOGE("ttsSynthesizeProto: TTS handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(handle, text.c_str(), optionsData, options.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("ttsSynthesizeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "ttsSynthesizeProto");
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::ttsSynthesizeStreamProto(
    const std::string& text,
    const std::shared_ptr<ArrayBuffer>& optionsBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onChunkBytes) {
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<void>::async([text, options = std::move(options), onChunkBytes]() {
        rac_handle_t handle = getGlobalTTSHandle();
        auto fn = proto_compat::symbol<proto_compat::TTSSynthesizeStreamProtoFn>(
            "rac_tts_component_synthesize_stream_proto");
        if (!handle || !fn) {
            LOGE("ttsSynthesizeStreamProto: TTS handle or proto ABI unavailable");
            return;
        }
        auto callback = onChunkBytes;
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(
            handle,
            text.c_str(),
            optionsData,
            options.size(),
            protoBytesCallback,
            &callback);
        if (rc != RAC_SUCCESS) {
            LOGE("ttsSynthesizeStreamProto: rc=%d", rc);
        }
    });
}

// ============================================================================
// VAD Capability (Backend-Agnostic)
// Calls rac_vad_component_* APIs - works with any registered backend
// Uses a global VAD component handle shared across HybridRunAnywhereCore instances
// ============================================================================

// Global VAD component handle - shared across all instances
static rac_handle_t g_vad_component_handle = nullptr;
static std::mutex g_vad_mutex;

static rac_handle_t getGlobalVADHandle() {
    std::lock_guard<std::mutex> lock(g_vad_mutex);
    if (g_vad_component_handle == nullptr) {
        rac_result_t result = rac_vad_component_create(&g_vad_component_handle);
        if (result != RAC_SUCCESS) {
            g_vad_component_handle = nullptr;
        }
    }
    return g_vad_component_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadVADModel(
    const std::string& modelPath,
    const std::optional<std::string>& configJson) {
    return Promise<bool>::async([this, modelPath]() -> bool {
        LOGI("Loading VAD model: %s", modelPath.c_str());

        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            setLastError("Failed to create VAD component. Is a VAD backend registered?");
            throw std::runtime_error("VAD backend not registered. Install @runanywhere/onnx.");
        }

        rac_vad_config_t config = RAC_VAD_CONFIG_DEFAULT;
        config.model_id = modelPath.c_str();
        rac_result_t result = rac_vad_component_configure(handle, &config);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to configure VAD: " + std::to_string(result));
        }

        result = rac_vad_component_initialize(handle);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to initialize VAD: " + std::to_string(result));
        }

        LOGI("VAD model loaded successfully");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVADModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        bool isLoaded = rac_vad_component_is_initialized(handle) == RAC_TRUE;
        LOGD("isVADModelLoaded: handle=%p, isLoaded=%s", handle, isLoaded ? "true" : "false");
        return isLoaded;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadVADModel() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            return false;
        }
        rac_vad_component_cleanup(handle);
        // Reset global handle since model is unloaded
        {
            std::lock_guard<std::mutex> lock(g_vad_mutex);
            g_vad_component_handle = nullptr;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVAD(
    const std::string& audioBase64,
    const std::optional<std::string>& optionsJson) {
    return Promise<std::string>::async([this, audioBase64, optionsJson]() -> std::string {
        LOGI("Processing VAD...");

        rac_handle_t handle = getGlobalVADHandle();
        if (!handle) {
            throw std::runtime_error("VAD component not available. Is a VAD backend registered?");
        }

        // Decode base64 audio data
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode base64 audio data for VAD");
        }

        // Convert byte data to float samples
        // Assuming 16-bit PCM audio: 2 bytes per sample
        size_t numSamples = audioData.size() / sizeof(int16_t);
        std::vector<float> floatSamples(numSamples);

        const int16_t* pcmData = reinterpret_cast<const int16_t*>(audioData.data());
        for (size_t i = 0; i < numSamples; i++) {
            floatSamples[i] = static_cast<float>(pcmData[i]) / 32768.0f;
        }

        LOGI("VAD processing %zu samples", numSamples);

        // Process with VAD
        rac_bool_t isSpeech = RAC_FALSE;
        rac_result_t status = rac_vad_component_process(
            handle,
            floatSamples.data(),
            numSamples,
            &isSpeech
        );

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("VAD processing failed with error code: " + std::to_string(status));
        }

        return std::string("{\"isSpeech\":") +
            (isSpeech == RAC_TRUE ? "true" : "false") +
            ",\"samplesProcessed\":" + std::to_string(numSamples) +
            "}";
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::resetVAD() {
    return Promise<void>::async([]() -> void {
        rac_handle_t handle = getGlobalVADHandle();
        if (handle) {
            rac_vad_component_reset(handle);
        }
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::vadConfigureProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADConfigureProtoFn>(
            "rac_vad_component_configure_proto");
        if (!handle || !fn) {
            LOGE("vadConfigureProto: VAD handle or proto ABI unavailable");
            return false;
        }
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(handle, data, bytes.size());
        if (rc != RAC_SUCCESS) {
            LOGE("vadConfigureProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vadProcessProto(
    const std::shared_ptr<ArrayBuffer>& samplesBytes,
    const std::shared_ptr<ArrayBuffer>& optionsBytes) {
    auto sampleBytes = copyVoiceArrayBufferBytes(samplesBytes);
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [sampleBytes = std::move(sampleBytes), options = std::move(options)]() {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADProcessProtoFn>(
            "rac_vad_component_process_proto");
        if (!handle || !fn) {
            LOGE("vadProcessProto: VAD handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        auto samples = copyVADSamples(sampleBytes);
        if (samples.empty()) {
            LOGE("vadProcessProto: empty or unsupported audio buffer");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(
            handle,
            samples.data(),
            samples.size(),
            optionsData,
            options.size(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vadProcessProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vadProcessProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vadGetStatisticsProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADStatsProtoFn>(
            "rac_vad_component_get_statistics_proto");
        if (!handle || !fn) {
            LOGE("vadGetStatisticsProto: VAD handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(handle, &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vadGetStatisticsProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vadGetStatisticsProto");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::vadSetActivityCallbackProto(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onActivityBytes) {
    return Promise<bool>::async([onActivityBytes]() -> bool {
        rac_handle_t handle = getGlobalVADHandle();
        auto fn = proto_compat::symbol<proto_compat::VADSetActivityProtoCallbackFn>(
            "rac_vad_component_set_activity_proto_callback");
        if (!handle || !fn) {
            LOGE("vadSetActivityCallbackProto: VAD handle or proto ABI unavailable");
            return false;
        }
        {
            std::lock_guard<std::mutex> lock(g_vadActivityCallbackMutex);
            g_vadActivityCallback = onActivityBytes;
        }
        rac_result_t rc = fn(handle, vadActivityProtoCallback, nullptr);
        if (rc != RAC_SUCCESS) {
            LOGE("vadSetActivityCallbackProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

// ============================================================================
// Voice Agent Capability (Backend-Agnostic)
// Calls rac_voice_agent_* APIs - requires STT, LLM, TTS, and VAD backends
// Uses a global voice agent handle that composes the global component handles
// Mirrors Swift SDK's CppBridge.VoiceAgent.shared architecture
// ============================================================================

// Global Voice Agent handle - composes the global STT, LLM, TTS, VAD handles
static rac_voice_agent_handle_t g_voice_agent_handle = nullptr;
static std::mutex g_voice_agent_mutex;

static rac_voice_agent_handle_t getGlobalVoiceAgentHandle() {
    std::lock_guard<std::mutex> lock(g_voice_agent_mutex);
    if (g_voice_agent_handle == nullptr) {
        // Get component handles - required for voice agent
        rac_handle_t llmHandle = getGlobalLLMHandle();
        rac_handle_t sttHandle = getGlobalSTTHandle();
        rac_handle_t ttsHandle = getGlobalTTSHandle();
        rac_handle_t vadHandle = getGlobalVADHandle();

        if (!llmHandle || !sttHandle || !ttsHandle || !vadHandle) {
            // Cannot create voice agent without all components
            return nullptr;
        }

        rac_result_t result = rac_voice_agent_create(
            llmHandle, sttHandle, ttsHandle, vadHandle, &g_voice_agent_handle);
        if (result != RAC_SUCCESS) {
            g_voice_agent_handle = nullptr;
        }
    }
    return g_voice_agent_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgent(
    const std::string& configJson) {
    return Promise<bool>::async([this, configJson]() -> bool {
        LOGI("Initializing voice agent...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent requires STT, LLM, TTS, and VAD backends. "
                                     "Install @runanywhere/llamacpp and @runanywhere/onnx.");
        }

        // Initialize with default config (or parse configJson if needed)
        rac_result_t result = rac_voice_agent_initialize(handle, nullptr);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Failed to initialize voice agent: " + std::to_string(result));
        }

        LOGI("Voice agent initialized");
        return true;
    });
}

// v3.1: Expose the global voice-agent handle as a JS number. The
// VoiceAgent.subscribeProtoEvents(handle, ...) Nitro method casts it
// back to rac_voice_agent_handle_t on the C side. 0 means the handle
// isn't allocated yet (pre-initializeVoiceAgentWithLoadedModels).
std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getVoiceAgentHandle() {
    return Promise<double>::async([this]() -> double {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        // reinterpret_cast to uintptr_t then widen to double. JS numbers
        // are 64-bit double, safe for 53 bits of integer precision —
        // more than enough for a 64-bit process pointer on macOS/Linux
        // and 32-bit pointers on iOS/Android ABIs.
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::initializeVoiceAgentWithLoadedModels() {
    return Promise<bool>::async([this]() -> bool {
        LOGI("Initializing voice agent with loaded models...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent requires STT, LLM, TTS, and VAD backends. "
                                     "Install @runanywhere/llamacpp and @runanywhere/onnx.");
        }

        // Initialize using already-loaded models
        rac_result_t result = rac_voice_agent_initialize_with_loaded_models(handle);
        if (result != RAC_SUCCESS) {
            throw std::runtime_error("Voice agent requires all models to be loaded. Error: " + std::to_string(result));
        }

        LOGI("Voice agent initialized with loaded models");
        return true;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVoiceAgentReady() {
    return Promise<bool>::async([]() -> bool {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            return false;
        }

        rac_bool_t isReady = RAC_FALSE;
        rac_result_t result = rac_voice_agent_is_ready(handle, &isReady);
        if (result != RAC_SUCCESS) {
            return false;
        }

        LOGD("isVoiceAgentReady: %s", isReady == RAC_TRUE ? "true" : "false");
        return isReady == RAC_TRUE;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::getVoiceAgentComponentStates() {
    return Promise<std::string>::async([]() -> std::string {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();

        // Get component loaded states
        rac_bool_t sttLoaded = RAC_FALSE;
        rac_bool_t llmLoaded = RAC_FALSE;
        rac_bool_t ttsLoaded = RAC_FALSE;

        if (handle) {
            rac_voice_agent_is_stt_loaded(handle, &sttLoaded);
            rac_voice_agent_is_llm_loaded(handle, &llmLoaded);
            rac_voice_agent_is_tts_loaded(handle, &ttsLoaded);
        }

        // Get model IDs if loaded
        const char* sttModelId = handle ? rac_voice_agent_get_stt_model_id(handle) : nullptr;
        const char* llmModelId = handle ? rac_voice_agent_get_llm_model_id(handle) : nullptr;
        const char* ttsVoiceId = handle ? rac_voice_agent_get_tts_voice_id(handle) : nullptr;

        return buildJsonObject({
            {"stt", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", sttLoaded == RAC_TRUE ? "true" : "false"},
                {"modelId", sttModelId ? jsonString(sttModelId) : "null"}
            })},
            {"llm", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", llmLoaded == RAC_TRUE ? "true" : "false"},
                {"modelId", llmModelId ? jsonString(llmModelId) : "null"}
            })},
            {"tts", buildJsonObject({
                {"available", handle ? "true" : "false"},
                {"loaded", ttsLoaded == RAC_TRUE ? "true" : "false"},
                {"voiceId", ttsVoiceId ? jsonString(ttsVoiceId) : "null"}
            })}
        });
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::processVoiceTurn(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        LOGI("Processing voice turn...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        // Decode base64 audio
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode audio data");
        }

        rac_voice_agent_result_t result = {};
        rac_result_t status = rac_voice_agent_process_voice_turn(
            handle, audioData.data(), audioData.size(), &result);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Voice turn processing failed: " + std::to_string(status));
        }

        // Build result JSON
        std::string responseJson = buildJsonObject({
            {"speechDetected", result.speech_detected == RAC_TRUE ? "true" : "false"},
            {"transcription", result.transcription ? jsonString(result.transcription) : "\"\""},
            {"response", result.response ? jsonString(result.response) : "\"\""},
            {"audioSize", std::to_string(result.synthesized_audio_size)}
        });

        // Free result resources
        rac_voice_agent_result_free(&result);

        LOGI("Voice turn completed");
        return responseJson;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentTranscribe(
    const std::string& audioBase64) {
    return Promise<std::string>::async([this, audioBase64]() -> std::string {
        LOGI("Voice agent transcribing...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        // Decode base64 audio
        std::vector<uint8_t> audioData = base64Decode(audioBase64);
        if (audioData.empty()) {
            throw std::runtime_error("Failed to decode audio data");
        }

        char* transcription = nullptr;
        rac_result_t status = rac_voice_agent_transcribe(
            handle, audioData.data(), audioData.size(), &transcription);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Transcription failed: " + std::to_string(status));
        }

        std::string result = transcription ? transcription : "";
        if (transcription) {
            free(transcription);
        }

        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentGenerateResponse(
    const std::string& prompt) {
    return Promise<std::string>::async([this, prompt]() -> std::string {
        LOGI("Voice agent generating response...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        char* response = nullptr;
        rac_result_t status = rac_voice_agent_generate_response(handle, prompt.c_str(), &response);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Response generation failed: " + std::to_string(status));
        }

        std::string result = response ? response : "";
        if (response) {
            free(response);
        }

        return result;
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::voiceAgentSynthesizeSpeech(
    const std::string& text) {
    return Promise<std::string>::async([this, text]() -> std::string {
        LOGI("Voice agent synthesizing speech...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (!handle) {
            throw std::runtime_error("Voice agent not available");
        }

        void* audioData = nullptr;
        size_t audioSize = 0;
        rac_result_t status = rac_voice_agent_synthesize_speech(
            handle, text.c_str(), &audioData, &audioSize);

        if (status != RAC_SUCCESS) {
            throw std::runtime_error("Speech synthesis failed: " + std::to_string(status));
        }

        // Encode audio to base64
        std::string audioBase64 = base64Encode(static_cast<uint8_t*>(audioData), audioSize);

        if (audioData) {
            free(audioData);
        }

        return audioBase64;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::cleanupVoiceAgent() {
    return Promise<void>::async([]() -> void {
        LOGI("Cleaning up voice agent...");

        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        if (handle) {
            rac_voice_agent_cleanup(handle);
        }

        // Note: We don't destroy the voice agent handle here - it's reusable
        // The models can be unloaded separately via unloadSTTModel, etc.
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentInitializeProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentInitProtoFn>(
            "rac_voice_agent_initialize_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentInitializeProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentInitializeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentInitializeProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentComponentStatesProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentStatesProtoFn>(
            "rac_voice_agent_component_states_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentComponentStatesProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        rac_result_t rc = fn(static_cast<void*>(handle), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentComponentStatesProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentComponentStatesProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentProcessTurnProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes) {
    auto audio = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([audio = std::move(audio)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentProcessTurnProtoFn>(
            "rac_voice_agent_process_voice_turn_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentProcessTurnProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const void* data = audio.empty() ? nullptr : audio.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, audio.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentProcessTurnProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentProcessTurnProto");
    });
}

} // namespace margelo::nitro::runanywhere
