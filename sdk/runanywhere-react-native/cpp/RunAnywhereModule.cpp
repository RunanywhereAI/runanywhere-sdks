/**
 * RunAnywhereModule.cpp
 *
 * Pure C++ TurboModule implementation for RunAnywhere React Native SDK.
 * Directly calls runanywhere-core C API for all AI operations.
 */

#include "RunAnywhereModule.h"

#include <sstream>
#include <cstring>
#include <algorithm>

// Base64 encoding/decoding utilities
namespace {

static const std::string BASE64_CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(const unsigned char* data, size_t length) {
    std::string result;
    result.reserve(((length + 2) / 3) * 4);

    for (size_t i = 0; i < length; i += 3) {
        unsigned int n = static_cast<unsigned int>(data[i]) << 16;
        if (i + 1 < length) n |= static_cast<unsigned int>(data[i + 1]) << 8;
        if (i + 2 < length) n |= static_cast<unsigned int>(data[i + 2]);

        result.push_back(BASE64_CHARS[(n >> 18) & 0x3F]);
        result.push_back(BASE64_CHARS[(n >> 12) & 0x3F]);
        result.push_back((i + 1 < length) ? BASE64_CHARS[(n >> 6) & 0x3F] : '=');
        result.push_back((i + 2 < length) ? BASE64_CHARS[n & 0x3F] : '=');
    }

    return result;
}

std::vector<unsigned char> base64Decode(const std::string& encoded) {
    std::vector<unsigned char> result;
    result.reserve((encoded.size() / 4) * 3);

    std::vector<int> T(256, -1);
    for (int i = 0; i < 64; i++) {
        T[static_cast<unsigned char>(BASE64_CHARS[i])] = i;
    }

    int val = 0, valb = -8;
    for (unsigned char c : encoded) {
        if (T[c] == -1) break;
        val = (val << 6) + T[c];
        valb += 6;
        if (valb >= 0) {
            result.push_back(static_cast<unsigned char>((val >> valb) & 0xFF));
            valb -= 8;
        }
    }

    return result;
}

} // anonymous namespace

namespace facebook::react {

// ============================================================================
// Constructor / Destructor
// ============================================================================

RunAnywhereModule::RunAnywhereModule(std::shared_ptr<CallInvoker> jsInvoker)
    : TurboModule("RunAnywhere", jsInvoker), jsInvoker_(std::move(jsInvoker)) {
    // Constructor - backend is created lazily via createBackend()
}

RunAnywhereModule::~RunAnywhereModule() {
    // Clean up all STT streams
    for (auto& [id, stream] : sttStreams_) {
        if (backend_ && stream) {
            ra_stt_destroy_stream(backend_, stream);
        }
    }
    sttStreams_.clear();

    // Destroy backend
    if (backend_) {
        ra_destroy(backend_);
        backend_ = nullptr;
    }
}

// ============================================================================
// TurboModule Interface
// ============================================================================

jsi::Value RunAnywhereModule::get(jsi::Runtime& rt, const jsi::PropNameID& name) {
    std::string propName = name.utf8(rt);

    // Backend Lifecycle
    if (propName == "createBackend") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                return jsi::Value(createBackend(rt, args[0].asString(rt).utf8(rt)));
            });
    }

    if (propName == "initialize") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[0].isNull() && !args[0].isUndefined()) {
                    config = args[0].asString(rt).utf8(rt);
                }
                return jsi::Value(initialize(rt, config));
            });
    }

    if (propName == "destroy") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                destroy(rt);
                return jsi::Value::undefined();
            });
    }

    if (propName == "isInitialized") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(isInitialized(rt));
            });
    }

    if (propName == "getBackendInfo") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::String::createFromUtf8(rt, getBackendInfo(rt));
            });
    }

    // Capability Query
    if (propName == "supportsCapability") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                return jsi::Value(supportsCapability(rt, static_cast<int>(args[0].asNumber())));
            });
    }

    if (propName == "getCapabilities") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                auto caps = getCapabilities(rt);
                jsi::Array result(rt, caps.size());
                for (size_t i = 0; i < caps.size(); i++) {
                    result.setValueAtIndex(rt, i, jsi::Value(caps[i]));
                }
                return result;
            });
    }

    if (propName == "getDeviceType") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(getDeviceType(rt));
            });
    }

    if (propName == "getMemoryUsage") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(getMemoryUsage(rt));
            });
    }

    // Text Generation
    if (propName == "loadTextModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 2,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[1].isNull() && !args[1].isUndefined()) {
                    config = args[1].asString(rt).utf8(rt);
                }
                return jsi::Value(loadTextModel(rt, args[0].asString(rt).utf8(rt), config));
            });
    }

    if (propName == "isTextModelLoaded") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(isTextModelLoaded(rt));
            });
    }

    if (propName == "unloadTextModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(unloadTextModel(rt));
            });
    }

    if (propName == "generate") {
        return jsi::Function::createFromHostFunction(
            rt, name, 4,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> systemPrompt;
                if (!args[1].isNull() && !args[1].isUndefined()) {
                    systemPrompt = args[1].asString(rt).utf8(rt);
                }
                return jsi::String::createFromUtf8(
                    rt,
                    generate(rt, args[0].asString(rt).utf8(rt), systemPrompt,
                             static_cast<int>(args[2].asNumber()), args[3].asNumber()));
            });
    }

    if (propName == "generateStream") {
        return jsi::Function::createFromHostFunction(
            rt, name, 4,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> systemPrompt;
                if (!args[1].isNull() && !args[1].isUndefined()) {
                    systemPrompt = args[1].asString(rt).utf8(rt);
                }
                generateStream(rt, args[0].asString(rt).utf8(rt), systemPrompt,
                               static_cast<int>(args[2].asNumber()), args[3].asNumber());
                return jsi::Value::undefined();
            });
    }

    if (propName == "cancelGeneration") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                cancelGeneration(rt);
                return jsi::Value::undefined();
            });
    }

    // STT Methods
    if (propName == "loadSTTModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 3,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[2].isNull() && !args[2].isUndefined()) {
                    config = args[2].asString(rt).utf8(rt);
                }
                return jsi::Value(loadSTTModel(rt, args[0].asString(rt).utf8(rt),
                                               args[1].asString(rt).utf8(rt), config));
            });
    }

    if (propName == "isSTTModelLoaded") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(isSTTModelLoaded(rt));
            });
    }

    if (propName == "unloadSTTModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::Value(unloadSTTModel(rt));
            });
    }

    if (propName == "transcribe") {
        return jsi::Function::createFromHostFunction(
            rt, name, 3,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> language;
                if (!args[2].isNull() && !args[2].isUndefined()) {
                    language = args[2].asString(rt).utf8(rt);
                }
                return jsi::String::createFromUtf8(
                    rt, transcribe(rt, args[0].asString(rt).utf8(rt),
                                   static_cast<int>(args[1].asNumber()), language));
            });
    }

    if (propName == "createSTTStream") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[0].isNull() && !args[0].isUndefined()) {
                    config = args[0].asString(rt).utf8(rt);
                }
                return jsi::Value(createSTTStream(rt, config));
            });
    }

    if (propName == "feedSTTAudio") {
        return jsi::Function::createFromHostFunction(
            rt, name, 3,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                return jsi::Value(feedSTTAudio(rt, static_cast<int>(args[0].asNumber()),
                                               args[1].asString(rt).utf8(rt),
                                               static_cast<int>(args[2].asNumber())));
            });
    }

    if (propName == "decodeSTT") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                return jsi::String::createFromUtf8(
                    rt, decodeSTT(rt, static_cast<int>(args[0].asNumber())));
            });
    }

    if (propName == "destroySTTStream") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                destroySTTStream(rt, static_cast<int>(args[0].asNumber()));
                return jsi::Value::undefined();
            });
    }

    // TTS Methods
    if (propName == "loadTTSModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 3,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[2].isNull() && !args[2].isUndefined()) {
                    config = args[2].asString(rt).utf8(rt);
                }
                return jsi::Value(loadTTSModel(rt, args[0].asString(rt).utf8(rt),
                                               args[1].asString(rt).utf8(rt), config));
            });
    }

    if (propName == "synthesize") {
        return jsi::Function::createFromHostFunction(
            rt, name, 4,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> voiceId;
                if (!args[1].isNull() && !args[1].isUndefined()) {
                    voiceId = args[1].asString(rt).utf8(rt);
                }
                return jsi::String::createFromUtf8(
                    rt, synthesize(rt, args[0].asString(rt).utf8(rt), voiceId,
                                   args[2].asNumber(), args[3].asNumber()));
            });
    }

    // VAD Methods
    if (propName == "loadVADModel") {
        return jsi::Function::createFromHostFunction(
            rt, name, 2,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                std::optional<std::string> config;
                if (!args[1].isNull() && !args[1].isUndefined()) {
                    config = args[1].asString(rt).utf8(rt);
                }
                return jsi::Value(loadVADModel(rt, args[0].asString(rt).utf8(rt), config));
            });
    }

    if (propName == "processVAD") {
        return jsi::Function::createFromHostFunction(
            rt, name, 2,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                return jsi::String::createFromUtf8(
                    rt, processVAD(rt, args[0].asString(rt).utf8(rt),
                                   static_cast<int>(args[1].asNumber())));
            });
    }

    // Utilities
    if (propName == "getLastError") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::String::createFromUtf8(rt, getLastError(rt));
            });
    }

    if (propName == "getVersion") {
        return jsi::Function::createFromHostFunction(
            rt, name, 0,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) {
                return jsi::String::createFromUtf8(rt, getVersion(rt));
            });
    }

    // Event Listeners
    if (propName == "addListener") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                addListener(rt, args[0].asString(rt).utf8(rt));
                return jsi::Value::undefined();
            });
    }

    if (propName == "removeListeners") {
        return jsi::Function::createFromHostFunction(
            rt, name, 1,
            [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, size_t) {
                removeListeners(rt, static_cast<int>(args[0].asNumber()));
                return jsi::Value::undefined();
            });
    }

    return jsi::Value::undefined();
}

std::vector<jsi::PropNameID> RunAnywhereModule::getPropertyNames(jsi::Runtime& rt) {
    std::vector<jsi::PropNameID> props;
    props.reserve(35);

    // Backend Lifecycle
    props.push_back(jsi::PropNameID::forUtf8(rt, "createBackend"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "initialize"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "destroy"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "isInitialized"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getBackendInfo"));
    // Capability Query
    props.push_back(jsi::PropNameID::forUtf8(rt, "supportsCapability"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getCapabilities"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getDeviceType"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getMemoryUsage"));
    // Text Generation
    props.push_back(jsi::PropNameID::forUtf8(rt, "loadTextModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "isTextModelLoaded"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "unloadTextModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "generate"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "generateStream"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "cancelGeneration"));
    // STT
    props.push_back(jsi::PropNameID::forUtf8(rt, "loadSTTModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "isSTTModelLoaded"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "unloadSTTModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "transcribe"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "createSTTStream"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "feedSTTAudio"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "decodeSTT"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "destroySTTStream"));
    // TTS
    props.push_back(jsi::PropNameID::forUtf8(rt, "loadTTSModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "synthesize"));
    // VAD
    props.push_back(jsi::PropNameID::forUtf8(rt, "loadVADModel"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "processVAD"));
    // Utilities
    props.push_back(jsi::PropNameID::forUtf8(rt, "getLastError"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "getVersion"));
    // Events
    props.push_back(jsi::PropNameID::forUtf8(rt, "addListener"));
    props.push_back(jsi::PropNameID::forUtf8(rt, "removeListeners"));

    return props;
}

// ============================================================================
// Backend Lifecycle Implementation
// ============================================================================

bool RunAnywhereModule::createBackend(jsi::Runtime& rt, const std::string& name) {
    if (backend_) {
        ra_destroy(backend_);
        backend_ = nullptr;
    }

    backend_ = ra_create_backend(name.c_str());
    return backend_ != nullptr;
}

bool RunAnywhereModule::initialize(jsi::Runtime& rt,
                                    const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_initialize(
        backend_,
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

void RunAnywhereModule::destroy(jsi::Runtime& rt) {
    // Clean up streams first
    for (auto& [id, stream] : sttStreams_) {
        if (backend_ && stream) {
            ra_stt_destroy_stream(backend_, stream);
        }
    }
    sttStreams_.clear();

    if (backend_) {
        ra_destroy(backend_);
        backend_ = nullptr;
    }
}

bool RunAnywhereModule::isInitialized(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_is_initialized(backend_);
}

std::string RunAnywhereModule::getBackendInfo(jsi::Runtime& rt) {
    if (!backend_) return "{}";

    char* info = ra_get_backend_info(backend_);
    if (!info) return "{}";

    std::string result(info);
    ra_free_string(info);
    return result;
}

// ============================================================================
// Capability Query Implementation
// ============================================================================

bool RunAnywhereModule::supportsCapability(jsi::Runtime& rt, int capability) {
    if (!backend_) return false;
    return ra_supports_capability(backend_, static_cast<ra_capability_type>(capability));
}

std::vector<int> RunAnywhereModule::getCapabilities(jsi::Runtime& rt) {
    std::vector<int> result;
    if (!backend_) return result;

    ra_capability_type caps[10];
    int count = ra_get_capabilities(backend_, caps, 10);

    for (int i = 0; i < count; i++) {
        result.push_back(static_cast<int>(caps[i]));
    }
    return result;
}

int RunAnywhereModule::getDeviceType(jsi::Runtime& rt) {
    if (!backend_) return 99; // RA_DEVICE_UNKNOWN
    return static_cast<int>(ra_get_device(backend_));
}

double RunAnywhereModule::getMemoryUsage(jsi::Runtime& rt) {
    if (!backend_) return 0;
    return static_cast<double>(ra_get_memory_usage(backend_));
}

// ============================================================================
// Text Generation Implementation
// ============================================================================

bool RunAnywhereModule::loadTextModel(jsi::Runtime& rt, const std::string& path,
                                       const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_text_load_model(
        backend_,
        path.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isTextModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_text_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadTextModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_text_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::generate(jsi::Runtime& rt, const std::string& prompt,
                                         const std::optional<std::string>& systemPrompt,
                                         int maxTokens, double temperature) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    char* resultJson = nullptr;
    ra_result_code result = ra_text_generate(
        backend_,
        prompt.c_str(),
        systemPrompt.has_value() ? systemPrompt->c_str() : nullptr,
        maxTokens,
        static_cast<float>(temperature),
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        std::ostringstream oss;
        oss << "{\"error\": \"" << (ra_get_last_error() ? ra_get_last_error() : "Generation failed") << "\"}";
        return oss.str();
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

// Streaming callback context
struct StreamContext {
    jsi::Runtime* runtime;
    RunAnywhereModule* module;
};

static bool textStreamCallback(const char* token, void* userData) {
    // Note: This is called from a native thread, so we need to be careful
    // In a real implementation, we'd use jsInvoker_ to safely call JS
    // For now, we'll store tokens and emit them on the JS thread
    return true;
}

void RunAnywhereModule::generateStream(jsi::Runtime& rt, const std::string& prompt,
                                        const std::optional<std::string>& systemPrompt,
                                        int maxTokens, double temperature) {
    if (!backend_) {
        emitEvent(rt, "onGenerationError", "{\"error\": \"Backend not initialized\"}");
        return;
    }

    // Start streaming on background thread
    // For now, emit a placeholder event
    emitEvent(rt, "onGenerationStart", "{}");

    StreamContext ctx{&rt, this};

    ra_result_code result = ra_text_generate_stream(
        backend_,
        prompt.c_str(),
        systemPrompt.has_value() ? systemPrompt->c_str() : nullptr,
        maxTokens,
        static_cast<float>(temperature),
        textStreamCallback,
        &ctx);

    if (result != RA_SUCCESS) {
        emitEvent(rt, "onGenerationError",
                  std::string("{\"error\": \"") + (ra_get_last_error() ? ra_get_last_error() : "Unknown error") + "\"}");
    } else {
        emitEvent(rt, "onGenerationComplete", "{}");
    }
}

void RunAnywhereModule::cancelGeneration(jsi::Runtime& rt) {
    if (backend_) {
        ra_text_cancel(backend_);
    }
}

// ============================================================================
// Speech-to-Text Implementation
// ============================================================================

bool RunAnywhereModule::loadSTTModel(jsi::Runtime& rt, const std::string& path,
                                      const std::string& modelType,
                                      const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_stt_load_model(
        backend_,
        path.c_str(),
        modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isSTTModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_stt_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadSTTModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_stt_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::transcribe(jsi::Runtime& rt, const std::string& audioBase64,
                                           int sampleRate,
                                           const std::optional<std::string>& language) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    // Decode base64 audio
    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) {
        return "{\"error\": \"Failed to decode audio\"}";
    }

    char* resultJson = nullptr;
    ra_result_code result = ra_stt_transcribe(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        language.has_value() ? language->c_str() : nullptr,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        return "{\"error\": \"Transcription failed\"}";
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

bool RunAnywhereModule::supportsSTTStreaming(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_stt_supports_streaming(backend_);
}

int RunAnywhereModule::createSTTStream(jsi::Runtime& rt,
                                        const std::optional<std::string>& configJson) {
    if (!backend_) return -1;

    ra_stream_handle stream = ra_stt_create_stream(
        backend_,
        configJson.has_value() ? configJson->c_str() : nullptr);

    if (!stream) return -1;

    int id = nextStreamId_++;
    sttStreams_[id] = stream;
    return id;
}

bool RunAnywhereModule::feedSTTAudio(jsi::Runtime& rt, int streamHandle,
                                      const std::string& audioBase64, int sampleRate) {
    if (!backend_) return false;

    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return false;

    ra_result_code result = ra_stt_feed_audio(
        backend_, it->second, samples.data(), samples.size(), sampleRate);

    return result == RA_SUCCESS;
}

std::string RunAnywhereModule::decodeSTT(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return "{}";

    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return "{}";

    char* resultJson = nullptr;
    ra_result_code result = ra_stt_decode(backend_, it->second, &resultJson);

    if (result != RA_SUCCESS || !resultJson) return "{}";

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

bool RunAnywhereModule::isSTTReady(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return false;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;
    return ra_stt_is_ready(backend_, it->second);
}

bool RunAnywhereModule::isSTTEndpoint(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return false;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;
    return ra_stt_is_endpoint(backend_, it->second);
}

void RunAnywhereModule::finishSTTInput(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;
    ra_stt_input_finished(backend_, it->second);
}

void RunAnywhereModule::resetSTTStream(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;
    ra_stt_reset_stream(backend_, it->second);
}

void RunAnywhereModule::destroySTTStream(jsi::Runtime& rt, int streamHandle) {
    if (!backend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;

    ra_stt_destroy_stream(backend_, it->second);
    sttStreams_.erase(it);
}

// ============================================================================
// Text-to-Speech Implementation
// ============================================================================

bool RunAnywhereModule::loadTTSModel(jsi::Runtime& rt, const std::string& path,
                                      const std::string& modelType,
                                      const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_tts_load_model(
        backend_,
        path.c_str(),
        modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isTTSModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_tts_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadTTSModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_tts_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::synthesize(jsi::Runtime& rt, const std::string& text,
                                           const std::optional<std::string>& voiceId,
                                           double speedRate, double pitchShift) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    float* audioSamples = nullptr;
    size_t numSamples = 0;
    int sampleRate = 0;

    ra_result_code result = ra_tts_synthesize(
        backend_,
        text.c_str(),
        voiceId.has_value() ? voiceId->c_str() : nullptr,
        static_cast<float>(speedRate),
        static_cast<float>(pitchShift),
        &audioSamples,
        &numSamples,
        &sampleRate);

    if (result != RA_SUCCESS || !audioSamples) {
        return "{\"error\": \"Synthesis failed\"}";
    }

    // Encode audio to base64
    std::string audioBase64 = encodeBase64Audio(audioSamples, numSamples);
    ra_free_audio(audioSamples);

    std::ostringstream oss;
    oss << "{\"audio\": \"" << audioBase64 << "\", \"sampleRate\": " << sampleRate
        << ", \"numSamples\": " << numSamples << "}";
    return oss.str();
}

bool RunAnywhereModule::supportsTTSStreaming(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_tts_supports_streaming(backend_);
}

void RunAnywhereModule::synthesizeStream(jsi::Runtime& rt, const std::string& text,
                                          const std::optional<std::string>& voiceId,
                                          double speedRate, double pitchShift) {
    // TODO: Implement streaming TTS with callbacks
    emitEvent(rt, "onTTSError", "{\"error\": \"Streaming TTS not yet implemented\"}");
}

std::string RunAnywhereModule::getTTSVoices(jsi::Runtime& rt) {
    if (!backend_) return "[]";

    char* voices = ra_tts_get_voices(backend_);
    if (!voices) return "[]";

    std::string result(voices);
    ra_free_string(voices);
    return result;
}

void RunAnywhereModule::cancelTTS(jsi::Runtime& rt) {
    if (backend_) {
        ra_tts_cancel(backend_);
    }
}

// ============================================================================
// VAD Implementation
// ============================================================================

bool RunAnywhereModule::loadVADModel(jsi::Runtime& rt, const std::string& path,
                                      const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_vad_load_model(
        backend_,
        path.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isVADModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_vad_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadVADModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_vad_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::processVAD(jsi::Runtime& rt, const std::string& audioBase64,
                                           int sampleRate) {
    if (!backend_) return "{\"isSpeech\": false, \"probability\": 0}";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) {
        return "{\"isSpeech\": false, \"probability\": 0}";
    }

    bool isSpeech = false;
    float probability = 0.0f;

    ra_result_code result = ra_vad_process(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        &isSpeech,
        &probability);

    if (result != RA_SUCCESS) {
        return "{\"isSpeech\": false, \"probability\": 0}";
    }

    std::ostringstream oss;
    oss << "{\"isSpeech\": " << (isSpeech ? "true" : "false")
        << ", \"probability\": " << probability << "}";
    return oss.str();
}

std::string RunAnywhereModule::detectVADSegments(jsi::Runtime& rt,
                                                  const std::string& audioBase64,
                                                  int sampleRate) {
    if (!backend_) return "[]";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return "[]";

    char* resultJson = nullptr;
    ra_result_code result = ra_vad_detect_segments(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) return "[]";

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

void RunAnywhereModule::resetVAD(jsi::Runtime& rt) {
    if (backend_) {
        ra_vad_reset(backend_);
    }
}

// ============================================================================
// Embeddings Implementation (Stubs - to be completed)
// ============================================================================

bool RunAnywhereModule::loadEmbeddingsModel(jsi::Runtime& rt, const std::string& path,
                                             const std::optional<std::string>& configJson) {
    if (!backend_) return false;
    return ra_embed_load_model(backend_, path.c_str(),
                               configJson.has_value() ? configJson->c_str() : nullptr) == RA_SUCCESS;
}

bool RunAnywhereModule::isEmbeddingsModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_embed_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadEmbeddingsModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_embed_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::embedText(jsi::Runtime& rt, const std::string& text) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    float* embedding = nullptr;
    int dimensions = 0;

    ra_result_code result = ra_embed_text(backend_, text.c_str(), &embedding, &dimensions);

    if (result != RA_SUCCESS || !embedding) {
        return "{\"error\": \"Embedding failed\"}";
    }

    // Build JSON array
    std::ostringstream oss;
    oss << "{\"embedding\": [";
    for (int i = 0; i < dimensions; i++) {
        if (i > 0) oss << ",";
        oss << embedding[i];
    }
    oss << "], \"dimensions\": " << dimensions << "}";

    ra_free_embedding(embedding);
    return oss.str();
}

std::string RunAnywhereModule::embedBatch(jsi::Runtime& rt,
                                           const std::vector<std::string>& texts) {
    // TODO: Implement batch embeddings
    return "{\"error\": \"Batch embedding not yet implemented\"}";
}

int RunAnywhereModule::getEmbeddingDimensions(jsi::Runtime& rt) {
    if (!backend_) return 0;
    return ra_embed_get_dimensions(backend_);
}

// ============================================================================
// Diarization Implementation (Stubs - to be completed)
// ============================================================================

bool RunAnywhereModule::loadDiarizationModel(jsi::Runtime& rt, const std::string& path,
                                              const std::optional<std::string>& configJson) {
    if (!backend_) return false;
    return ra_diarize_load_model(backend_, path.c_str(),
                                 configJson.has_value() ? configJson->c_str() : nullptr) == RA_SUCCESS;
}

bool RunAnywhereModule::isDiarizationModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_diarize_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadDiarizationModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_diarize_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::diarize(jsi::Runtime& rt, const std::string& audioBase64,
                                        int sampleRate, int minSpeakers, int maxSpeakers) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return "{\"error\": \"Failed to decode audio\"}";

    char* resultJson = nullptr;
    ra_result_code result = ra_diarize(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        minSpeakers,
        maxSpeakers,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        return "{\"error\": \"Diarization failed\"}";
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

void RunAnywhereModule::cancelDiarization(jsi::Runtime& rt) {
    if (backend_) {
        ra_diarize_cancel(backend_);
    }
}

// ============================================================================
// Utility Implementation
// ============================================================================

std::string RunAnywhereModule::getLastError(jsi::Runtime& rt) {
    const char* error = ra_get_last_error();
    return error ? std::string(error) : "";
}

std::string RunAnywhereModule::getVersion(jsi::Runtime& rt) {
    const char* version = ra_get_version();
    return version ? std::string(version) : "unknown";
}

bool RunAnywhereModule::extractArchive(jsi::Runtime& rt, const std::string& archivePath,
                                        const std::string& destDir) {
    return ra_extract_archive(archivePath.c_str(), destDir.c_str()) == RA_SUCCESS;
}

// ============================================================================
// Event System Implementation
// ============================================================================

void RunAnywhereModule::addListener(jsi::Runtime& rt, const std::string& eventName) {
    listenerCount_++;
}

void RunAnywhereModule::removeListeners(jsi::Runtime& rt, int count) {
    listenerCount_ = std::max(0, listenerCount_ - count);
}

void RunAnywhereModule::emitEvent(jsi::Runtime& rt, const std::string& eventName,
                                   const std::string& eventData) {
    if (listenerCount_ <= 0) return;

    // Use jsInvoker to safely call into JavaScript
    if (jsInvoker_) {
        jsInvoker_->invokeAsync([this, &rt, eventName, eventData]() {
            // This will be called on the JS thread
            // In a full implementation, we'd use RCTDeviceEventEmitter here
        });
    }
}

// ============================================================================
// Helper Methods
// ============================================================================

std::vector<float> RunAnywhereModule::decodeBase64Audio(const std::string& base64) {
    std::vector<unsigned char> decoded = base64Decode(base64);
    if (decoded.empty()) return {};

    // Assume float32 audio samples
    size_t numSamples = decoded.size() / sizeof(float);
    std::vector<float> samples(numSamples);
    std::memcpy(samples.data(), decoded.data(), decoded.size());
    return samples;
}

std::string RunAnywhereModule::encodeBase64Audio(const float* samples, size_t count) {
    const unsigned char* data = reinterpret_cast<const unsigned char*>(samples);
    return base64Encode(data, count * sizeof(float));
}

ra_stream_handle RunAnywhereModule::getStreamHandle(int id) {
    auto it = sttStreams_.find(id);
    return (it != sttStreams_.end()) ? it->second : nullptr;
}

} // namespace facebook::react
