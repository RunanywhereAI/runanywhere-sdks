/**
 * HybridRunAnywhereCore+Voice.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 *
 * V2 bridge classification (CPP-09 — see docs/CPP_PROTO_OWNERSHIP.md
 * "Bridge Layer Audit"):
 *   - SDK-facing pass-through: every `*Proto` method (LLM gen/cancel,
 *     STT/TTS/VAD/VLM/diffusion/embeddings proto thunks, voice agent
 *     proto thunks, LoRA proto thunks). Each takes/returns ArrayBuffer
 *     bytes and calls the matching `rac_*_proto` C ABI through
 *     proto_compat::symbol or, on Apple, via static linking.
 *   - Bridge-internal helper: `getGlobalLLMHandle()` calls
 *     `rac_llm_component_create()` directly to maintain a single LLM
 *     handle shared across HybridRunAnywhereCore instances. Migration
 *     target: source the live LLM handle from
 *     `rac_model_lifecycle_load_proto` (which returns the handle on
 *     load) so this bridge no longer creates components on its own.
 *     Tracked under react-native gap.
 *   - Other helpers (`callLoraRequestProto`, `callLoraCatalogProto`,
 *     proto callbacks, VAD activity callback) are pure pass-through.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

#include <stdexcept>

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

static std::shared_ptr<ArrayBuffer> callLoraRequestProto(
    const std::vector<uint8_t>& bytes,
    const char* symbolName,
    const char* operation) {
    rac_handle_t handle = getGlobalLLMHandle();
    auto fn = proto_compat::symbol<proto_compat::LoRARequestProtoFn>(symbolName);
    if (!handle || !fn) {
        LOGE("%s: LLM handle or %s unavailable", operation, symbolName);
        return emptyVoiceProtoBuffer();
    }
    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(handle, data, bytes.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
        LOGE("%s: rc=%d", operation, rc);
        proto_compat::freeBuffer(&out);
        return emptyVoiceProtoBuffer();
    }
    return copyVoiceProtoBuffer(out, operation);
}

static std::shared_ptr<ArrayBuffer> callLoraCatalogProto(
    const std::vector<uint8_t>& bytes,
    const char* symbolName,
    const char* operation) {
    auto getRegistry = proto_compat::symbol<proto_compat::LoraRegistryGetFn>(
        "rac_get_lora_registry");
    auto fn = proto_compat::symbol<proto_compat::LoraCatalogProtoFn>(symbolName);
    if (!getRegistry || !fn) {
        throw std::runtime_error(
            std::string(operation) +
            " unavailable: missing rac_get_lora_registry or " + symbolName);
    }

    rac_lora_registry_handle_t registry = getRegistry();
    if (!registry) {
        throw std::runtime_error(
            std::string(operation) +
            " unavailable: rac_get_lora_registry returned null");
    }

    rac_proto_buffer_t out;
    proto_compat::initBuffer(&out);
    const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
    rac_result_t rc = fn(registry, data, bytes.size(), &out);
    if (rc != RAC_SUCCESS || out.status != RAC_SUCCESS) {
        rac_result_t status = out.status != RAC_SUCCESS ? out.status : rc;
        std::string message = out.error_message && out.error_message[0]
            ? std::string(out.error_message)
            : std::string(rac_error_message(status));
        proto_compat::freeBuffer(&out);
        throw std::runtime_error(std::string(operation) + " failed: " + message);
    }

    return copyVoiceProtoBuffer(out, operation);
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::getLLMHandle() {
    return Promise<double>::async([]() -> double {
        rac_handle_t handle = getGlobalLLMHandle();
        return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
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
        // BUG-RN-IOS-004: heap-allocate the std::function so its address is
        // stable for the entire C callback window, even if a future async
        // backend fires the callback after this outer lambda scope would
        // ordinarily destroy a stack-local. The unique_ptr owns the heap
        // storage for the duration of fn() (which is synchronous in the
        // current contract), guaranteeing protoBytesCallback's user_data
        // dereference is always valid. Matches the ownership pattern used
        // by the JNI bridge (see runanywhere_commons_jni.cpp).
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onEventBytes);
        rac_result_t rc = fn(data, bytes.size(), protoBytesCallback, callback.get());
        if (rc != RAC_SUCCESS) {
            LOGE("llmGenerateStreamProto: rc=%d", rc);
        }
        // callback unique_ptr is destroyed here AFTER fn() returns, freeing
        // the heap. Since fn() is synchronous in the current C ABI contract,
        // no more callback invocations are possible past this point.
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
HybridRunAnywhereCore::loraApplyProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_apply_proto",
            "loraApplyProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraRemoveProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_remove_proto",
            "loraRemoveProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraListProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_list_proto",
            "loraListProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraStateProto(const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_state_proto",
            "loraStateProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCompatibilityProto(
    const std::shared_ptr<ArrayBuffer>& configBytes) {
    auto bytes = copyVoiceArrayBufferBytes(configBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraRequestProto(
            bytes,
            "rac_lora_compatibility_proto",
            "loraCompatibilityProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraRegisterCatalogEntryProto(
    const std::shared_ptr<ArrayBuffer>& entryBytes) {
    auto bytes = copyVoiceArrayBufferBytes(entryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_register_proto",
            "loraRegisterCatalogEntryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogListProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_list_proto",
            "loraCatalogListProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogQueryProto(
    const std::shared_ptr<ArrayBuffer>& queryBytes) {
    auto bytes = copyVoiceArrayBufferBytes(queryBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_query_proto",
            "loraCatalogQueryProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogGetProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_get_proto",
            "loraCatalogGetProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::loraCatalogMarkDownloadCompletedProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    auto bytes = copyVoiceArrayBufferBytes(requestBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        return callLoraCatalogProto(
            bytes,
            "rac_lora_catalog_mark_download_completed_proto",
            "loraCatalogMarkDownloadCompletedProto");
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
        // BUG-RN-IOS-004 (adjacent): heap-allocate std::function so the
        // user_data pointer is stable for the duration of the C call.
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onPartialBytes);
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        const void* audioData = audio.empty() ? nullptr : audio.data();
        rac_result_t rc = fn(
            handle,
            audioData,
            audio.size(),
            optionsData,
            options.size(),
            protoBytesCallback,
            callback.get());
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
        // BUG-RN-IOS-004 (adjacent): heap-allocate std::function so the
        // user_data pointer is stable for the duration of the C call.
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onVoiceBytes);
        rac_result_t rc = fn(handle, protoBytesCallback, callback.get());
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
        // BUG-RN-IOS-004 (adjacent): heap-allocate std::function so the
        // user_data pointer is stable for the duration of the C call.
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onChunkBytes);
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(
            handle,
            text.c_str(),
            optionsData,
            options.size(),
            protoBytesCallback,
            callback.get());
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
// VLM Capability (Backend-Agnostic)
// Uses commons VLM service lifecycle plus rac_vlm_*_proto APIs.
// ============================================================================

static rac_handle_t g_vlm_service_handle = nullptr;
static std::mutex g_vlm_mutex;
static std::string g_vlm_model_id;

static rac_bool_t vlmProtoBytesCallback(const uint8_t* protoBytes,
                                        size_t protoSize,
                                        void* userData) {
    protoBytesCallback(protoBytes, protoSize, userData);
    return RAC_TRUE;
}

static void destroyGlobalVLMServiceLocked() {
    if (!g_vlm_service_handle) {
        return;
    }

    if (auto cleanup = proto_compat::symbol<proto_compat::VLMCleanupFn>("rac_vlm_cleanup")) {
        (void)cleanup(g_vlm_service_handle);
    }
    if (auto destroy = proto_compat::symbol<proto_compat::VLMDestroyFn>("rac_vlm_destroy")) {
        destroy(g_vlm_service_handle);
    } else {
        LOGE("destroyGlobalVLMServiceLocked: rac_vlm_destroy unavailable");
    }
    g_vlm_service_handle = nullptr;
    g_vlm_model_id.clear();
}

static bool loadGlobalVLMService(const std::string& primaryModelPath,
                                 const std::string& visionProjectorPath,
                                 const std::string& modelId) {
    auto create = proto_compat::symbol<proto_compat::VLMCreateFn>("rac_vlm_create");
    auto initialize =
        proto_compat::symbol<proto_compat::VLMInitializeFn>("rac_vlm_initialize");
    if (!create || !initialize) {
        LOGE("loadVLMModelFromArtifacts: rac_vlm_create/rac_vlm_initialize unavailable");
        return false;
    }

    std::lock_guard<std::mutex> lock(g_vlm_mutex);
    destroyGlobalVLMServiceLocked();

    rac_handle_t handle = nullptr;
    const std::string createKey = modelId.empty() ? primaryModelPath : modelId;
    rac_result_t rc = create(createKey.c_str(), &handle);
    if (rc != RAC_SUCCESS || !handle) {
        LOGE("loadVLMModelFromArtifacts: rac_vlm_create failed: %d", rc);
        return false;
    }

    rc = initialize(handle, primaryModelPath.c_str(), visionProjectorPath.c_str());
    if (rc != RAC_SUCCESS) {
        LOGE("loadVLMModelFromArtifacts: rac_vlm_initialize failed: %d", rc);
        if (auto destroy = proto_compat::symbol<proto_compat::VLMDestroyFn>("rac_vlm_destroy")) {
            destroy(handle);
        }
        return false;
    }

    g_vlm_service_handle = handle;
    g_vlm_model_id = createKey;
    return true;
}

static rac_handle_t getGlobalVLMServiceHandle() {
    std::lock_guard<std::mutex> lock(g_vlm_mutex);
    return g_vlm_service_handle;
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::loadVLMModelFromArtifacts(
    const std::string& primaryModelPath,
    const std::string& visionProjectorPath,
    const std::string& modelId) {
    return Promise<bool>::async([primaryModelPath, visionProjectorPath, modelId]() -> bool {
        if (primaryModelPath.empty()) {
            LOGE("loadVLMModelFromArtifacts: primaryModelPath is empty");
            return false;
        }
        if (visionProjectorPath.empty()) {
            LOGE("loadVLMModelFromArtifacts: visionProjectorPath is empty");
            return false;
        }
        return loadGlobalVLMService(primaryModelPath, visionProjectorPath, modelId);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::isVLMModelLoaded() {
    return Promise<bool>::async([]() -> bool {
        return getGlobalVLMServiceHandle() != nullptr;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::unloadVLMModel() {
    return Promise<bool>::async([]() -> bool {
        std::lock_guard<std::mutex> lock(g_vlm_mutex);
        const bool hadHandle = g_vlm_service_handle != nullptr;
        destroyGlobalVLMServiceLocked();
        return hadHandle;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vlmProcessProto(
    const std::shared_ptr<ArrayBuffer>& imageBytes,
    const std::shared_ptr<ArrayBuffer>& optionsBytes) {
    auto image = copyVoiceArrayBufferBytes(imageBytes);
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [image = std::move(image), options = std::move(options)]() {
        rac_handle_t handle = getGlobalVLMServiceHandle();
        auto fn = proto_compat::symbol<proto_compat::VLMProcessProtoFn>(
            "rac_vlm_process_proto");
        if (!handle || !fn) {
            LOGE("vlmProcessProto: VLM handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* imageData = image.empty() ? nullptr : image.data();
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(
            handle,
            imageData,
            image.size(),
            optionsData,
            options.size(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vlmProcessProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vlmProcessProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::vlmProcessStreamProto(
    const std::shared_ptr<ArrayBuffer>& imageBytes,
    const std::shared_ptr<ArrayBuffer>& optionsBytes,
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    auto image = copyVoiceArrayBufferBytes(imageBytes);
    auto options = copyVoiceArrayBufferBytes(optionsBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async(
        [image = std::move(image), options = std::move(options), onEventBytes]() {
        rac_handle_t handle = getGlobalVLMServiceHandle();
        auto fn = proto_compat::symbol<proto_compat::VLMProcessStreamProtoFn>(
            "rac_vlm_process_stream_proto");
        if (!handle || !fn) {
            LOGE("vlmProcessStreamProto: VLM handle or proto stream ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        // BUG-RN-IOS-004 (adjacent): heap-allocate std::function so the
        // user_data pointer is stable for the duration of the C call.
        auto callback = std::make_unique<
            std::function<void(const std::shared_ptr<ArrayBuffer>&)>>(onEventBytes);
        const uint8_t* imageData = image.empty() ? nullptr : image.data();
        const uint8_t* optionsData = options.empty() ? nullptr : options.data();
        rac_result_t rc = fn(
            handle,
            imageData,
            image.size(),
            optionsData,
            options.size(),
            vlmProtoBytesCallback,
            callback.get(),
            &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("vlmProcessStreamProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "vlmProcessStreamProto");
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::vlmCancelProto() {
    return Promise<bool>::async([]() -> bool {
        rac_handle_t handle = getGlobalVLMServiceHandle();
        auto fn = proto_compat::symbol<proto_compat::VLMCancelProtoFn>(
            "rac_vlm_cancel_proto");
        if (!handle || !fn) {
            LOGE("vlmCancelProto: VLM handle or cancel ABI unavailable");
            return false;
        }
        rac_result_t rc = fn(handle);
        if (rc != RAC_SUCCESS) {
            LOGE("vlmCancelProto: rc=%d", rc);
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

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentTranscribeProto(
    const std::shared_ptr<ArrayBuffer>& audioBytes) {
    auto bytes = copyVoiceArrayBufferBytes(audioBytes);
    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentTranscribeProtoFn>(
            "rac_voice_agent_transcribe_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentTranscribeProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = bytes.empty() ? nullptr : bytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, bytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentTranscribeProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentTranscribeProto");
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::voiceAgentSynthesizeSpeechProto(
    const std::string& text) {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([text]() {
        rac_voice_agent_handle_t handle = getGlobalVoiceAgentHandle();
        auto fn = proto_compat::symbol<proto_compat::VoiceAgentSynthesizeSpeechProtoFn>(
            "rac_voice_agent_synthesize_speech_proto");
        if (!handle || !fn) {
            LOGE("voiceAgentSynthesizeSpeechProto: handle or proto ABI unavailable");
            return emptyVoiceProtoBuffer();
        }
        // Encode a minimal VoiceAgentSynthesizeSpeechProtoRequest on the fly.
        // Proto structure at idl/voice_agent_service.proto:
        //   message VoiceAgentSynthesizeSpeechProtoRequest {
        //     string text = 1;
        //     string session_id = 2;
        //     TTSOptions options = 3;
        //   }
        // Field 1 (text) wire-tag = (1<<3)|2 = 0x0A.
        std::vector<uint8_t> requestBytes;
        if (!text.empty()) {
            requestBytes.push_back(0x0A); // tag=1, wire=length-delimited
            // Varint-encode the length.
            uint32_t len = static_cast<uint32_t>(text.size());
            while (len >= 0x80) {
                requestBytes.push_back(static_cast<uint8_t>((len & 0x7F) | 0x80));
                len >>= 7;
            }
            requestBytes.push_back(static_cast<uint8_t>(len & 0x7F));
            requestBytes.insert(requestBytes.end(), text.begin(), text.end());
        }
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        const uint8_t* data = requestBytes.empty() ? nullptr : requestBytes.data();
        rac_result_t rc = fn(static_cast<void*>(handle), data, requestBytes.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) {
            LOGE("voiceAgentSynthesizeSpeechProto: rc=%d", rc);
            proto_compat::freeBuffer(&out);
            return emptyVoiceProtoBuffer();
        }
        return copyVoiceProtoBuffer(out, "voiceAgentSynthesizeSpeechProto");
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
