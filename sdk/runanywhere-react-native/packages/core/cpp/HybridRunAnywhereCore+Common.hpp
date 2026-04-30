/**
 * Shared private helpers for HybridRunAnywhereCore domain translation units.
 *
 * This header intentionally keeps internal helpers in an anonymous namespace so
 * each TU gets local copies without exposing implementation details.
 */
#pragma once

#include "HybridRunAnywhereCore.hpp"

// RACommons headers
#include "rac_dev_config.h"  // For rac_dev_config_get_build_token

// Core bridges - aligned with actual RACommons API
#include "bridges/InitBridge.hpp"
#include "bridges/DeviceBridge.hpp"
#include "bridges/AuthBridge.hpp"
#include "bridges/StorageBridge.hpp"
#include "bridges/ModelRegistryBridge.hpp"
#include "bridges/CompatibilityBridge.hpp"
#include "bridges/EventBridge.hpp"
#include "bridges/HTTPBridge.hpp"
#include "bridges/DownloadBridge.hpp"
#include "bridges/TelemetryBridge.hpp"
#include "bridges/ToolCallingBridge.hpp"
#include "bridges/RAGBridge.hpp"
#include "bridges/FileManagerBridge.hpp"

// RACommons C API headers for capability methods
// These are backend-agnostic - they work with any registered backend
#include "rac_core.h"
#include "rac_llm_component.h"
#include "rac_llm_stream.h"
#include "rac_llm_thinking.h"
#include "rac_llm_types.h"
#include "rac_llm_structured_output.h"
#include "rac_stt_component.h"
#include "rac_stt_types.h"
#include "rac_tts_component.h"
#include "rac_tts_types.h"
#include "rac_vad_component.h"
#include "rac_vad_types.h"
#include "rac_voice_agent.h"
#include "rac/solutions/rac_solution.h"
#include "rac_types.h"
#include "rac_model_assignment.h"
#include "rac_extraction.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_download.h"

#include <chrono>
#include <vector>
#include <mutex>
#include <atomic>
#include <memory>
#include <unordered_map>
#include <thread>
#include <sys/stat.h>
#include <dirent.h>
#include <cstdio>
#include <cstring>

// Platform-specific headers for memory usage
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/task.h>
#endif

// Platform-specific logging
#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "HybridRunAnywhereCore"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf("[HybridRunAnywhereCore] "); printf(__VA_ARGS__); printf("\n")
#define LOGW(...) printf("[HybridRunAnywhereCore WARN] "); printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf("[HybridRunAnywhereCore ERROR] "); printf(__VA_ARGS__); printf("\n")
#define LOGD(...) printf("[HybridRunAnywhereCore DEBUG] "); printf(__VA_ARGS__); printf("\n")
#endif

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// ============================================================================
// Base64 Utilities
// ============================================================================

namespace {

static const std::string base64_chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::vector<uint8_t> base64Decode(const std::string& encoded) {
    static const int8_t table[256] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1, 0,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    };
    std::vector<uint8_t> decoded;
    decoded.reserve((encoded.size() * 3) / 4);
    uint32_t buf = 0;
    int bits = 0;
    for (unsigned char c : encoded) {
        if (c == '=') break;
        int8_t v = table[c];
        if (v < 0) {
            if (c == '\n' || c == '\r' || c == ' ' || c == '\t') continue;
            return {};
        }
        buf = (buf << 6) | static_cast<uint32_t>(v);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            decoded.push_back(static_cast<uint8_t>((buf >> bits) & 0xFF));
        }
    }
    return decoded;
}

std::string base64Encode(const uint8_t* data, size_t len) {
    std::string encoded;
    if (!data || len == 0) return encoded;

    int val = 0, valb = -6;
    for (size_t i = 0; i < len; i++) {
        val = (val << 8) + data[i];
        valb += 8;
        while (valb >= 0) {
            encoded.push_back(base64_chars[(val >> valb) & 0x3F]);
            valb -= 6;
        }
    }
    if (valb > -6) {
        encoded.push_back(base64_chars[((val << 8) >> (valb + 8)) & 0x3F]);
    }
    while (encoded.size() % 4) {
        encoded.push_back('=');
    }
    return encoded;
}

// ============================================================================
// ONNX Model Directory Resolution
// ============================================================================

// Mirrors TypeScript findModelPathAfterExtraction: given a directory path,
// return the directory that actually contains model files (.onnx, tokens.txt, etc.).
// Handles: file paths (returns parent dir), nested single-subdirectory archives,
// and already-correct paths.
std::string resolveOnnxModelDirectory(const std::string& path) {
    struct stat st;
    if (stat(path.c_str(), &st) != 0) return path;

    std::string dir = path;
    if (!S_ISDIR(st.st_mode)) {
        size_t slash = path.rfind('/');
        if (slash != std::string::npos) {
            dir = path.substr(0, slash);
            LOGI("resolveOnnxModelDirectory: file -> parent dir: %s", dir.c_str());
        } else {
            return path;
        }
    }

    // Check if this directory directly contains model files
    auto dirHasModelFiles = [](const std::string& d) -> bool {
        DIR* dp = opendir(d.c_str());
        if (!dp) return false;
        bool found = false;
        struct dirent* entry;
        while ((entry = readdir(dp)) != nullptr) {
            if (entry->d_type != DT_REG) continue;
            std::string name(entry->d_name);
            if (name.size() > 5 && name.substr(name.size() - 5) == ".onnx") { found = true; break; }
            if (name == "tokens.txt" || name == "vocab.txt") { found = true; break; }
        }
        closedir(dp);
        return found;
    };

    if (dirHasModelFiles(dir)) return dir;

    // Not found at top level — check for single nested subdirectory
    DIR* dp = opendir(dir.c_str());
    if (!dp) return dir;
    std::string singleSubdir;
    int subdirCount = 0;
    struct dirent* entry;
    while ((entry = readdir(dp)) != nullptr) {
        if (entry->d_type == DT_DIR && entry->d_name[0] != '.') {
            singleSubdir = dir + "/" + entry->d_name;
            subdirCount++;
        }
    }
    closedir(dp);

    if (subdirCount == 1 && dirHasModelFiles(singleSubdir)) {
        LOGI("resolveOnnxModelDirectory: resolved nested dir: %s", singleSubdir.c_str());
        return singleSubdir;
    }

    return dir;
}

// ============================================================================
// JSON Utilities
// ============================================================================

int extractIntValue(const std::string& json, const std::string& key, int defaultValue) {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.size()) return defaultValue;
    // Skip if this is a string value (starts with quote)
    if (json[pos] == '"') return defaultValue;
    // Try to parse as integer, return default on failure
    try {
        return std::stoi(json.substr(pos));
    } catch (...) {
        return defaultValue;
    }
}

double extractDoubleValue(const std::string& json, const std::string& key, double defaultValue) {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.size()) return defaultValue;
    // Skip if this is a string value (starts with quote)
    if (json[pos] == '"') return defaultValue;
    // Try to parse as double, return default on failure
    try {
        return std::stod(json.substr(pos));
    } catch (...) {
        return defaultValue;
    }
}

std::string extractStringValue(const std::string& json, const std::string& key, const std::string& defaultValue = "") {
    std::string searchKey = "\"" + key + "\":\"";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    size_t endPos = json.find("\"", pos);
    if (endPos == std::string::npos) return defaultValue;
    return json.substr(pos, endPos - pos);
}

bool extractBoolValue(const std::string& json, const std::string& key, bool defaultValue = false) {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = json.find(searchKey);
    if (pos == std::string::npos) return defaultValue;
    pos += searchKey.length();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
    if (pos >= json.size()) return defaultValue;
    if (json.substr(pos, 4) == "true") return true;
    if (json.substr(pos, 5) == "false") return false;
    return defaultValue;
}

// Convert TypeScript framework string to C++ enum
rac_inference_framework_t frameworkFromString(const std::string& framework) {
    if (framework == "LlamaCpp" || framework == "llamacpp") return RAC_FRAMEWORK_LLAMACPP;
    if (framework == "ONNX" || framework == "onnx") return RAC_FRAMEWORK_ONNX;
#ifdef __APPLE__
    if (framework == "CoreML" || framework == "coreml") return RAC_FRAMEWORK_COREML;
#endif
    if (framework == "FoundationModels") return RAC_FRAMEWORK_FOUNDATION_MODELS;
    if (framework == "SystemTTS") return RAC_FRAMEWORK_SYSTEM_TTS;
    if (framework == "Genie" || framework == "genie") return (rac_inference_framework_t)11; // RAC_FRAMEWORK_GENIE
    if (framework == "Sherpa" || framework == "sherpa") return (rac_inference_framework_t)12; // RAC_FRAMEWORK_SHERPA (B-RN-Sherpa-001)
    return RAC_FRAMEWORK_UNKNOWN;
}

// Convert TypeScript category string to C++ enum
rac_model_category_t categoryFromString(const std::string& category) {
    if (category == "Language" || category == "language") return RAC_MODEL_CATEGORY_LANGUAGE;
    // Handle both hyphen and underscore variants
    if (category == "SpeechRecognition" || category == "speech-recognition" || category == "speech_recognition") return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
    if (category == "SpeechSynthesis" || category == "speech-synthesis" || category == "speech_synthesis") return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
    if (category == "VoiceActivity" || category == "voice-activity" || category == "voice_activity") return RAC_MODEL_CATEGORY_AUDIO;
    if (category == "Vision" || category == "vision") return RAC_MODEL_CATEGORY_VISION;
    if (category == "ImageGeneration" || category == "image-generation" || category == "image_generation") return RAC_MODEL_CATEGORY_IMAGE_GENERATION;
    if (category == "Multimodal" || category == "multimodal") return RAC_MODEL_CATEGORY_MULTIMODAL;
    if (category == "Audio" || category == "audio") return RAC_MODEL_CATEGORY_AUDIO;
    if (category == "Embedding" || category == "embedding") return RAC_MODEL_CATEGORY_EMBEDDING;
    return RAC_MODEL_CATEGORY_UNKNOWN;
}

/**
 * Convert a numeric `ModelCategory` value received from TypeScript callers
 * into the C ABI's `rac_model_category_t`.
 *
 * G-DV27: TypeScript consumers pass the proto-canonical `ModelCategory` enum
 * (from `@runanywhere/proto-ts`) which uses a DIFFERENT numbering than the
 * RAC C ABI:
 *
 *   proto ModelCategory      RAC rac_model_category_t
 *   ----------------------   ---------------------------------
 *   UNSPECIFIED         = 0  LANGUAGE                     = 0
 *   LANGUAGE            = 1  SPEECH_RECOGNITION           = 1
 *   SPEECH_RECOGNITION  = 2  SPEECH_SYNTHESIS             = 2
 *   SPEECH_SYNTHESIS    = 3  VISION                       = 3
 *   VISION              = 4  IMAGE_GENERATION             = 4
 *   IMAGE_GENERATION    = 5  MULTIMODAL                   = 5
 *   MULTIMODAL          = 6  AUDIO                        = 6
 *   AUDIO               = 7  EMBEDDING                    = 7
 *   EMBEDDING           = 8  VOICE_ACTIVITY_DETECTION     = 8
 *   VAD                 = 9  UNKNOWN                      = 99
 *
 * A naive `static_cast<rac_model_category_t>(protoInt)` scrambles categories
 * by one position (LLM → SPEECH_RECOGNITION, TTS → VISION, etc.) — the
 * exact symptom reported by the iOS RN catalog badge bug.
 *
 * This translator is the single source of truth for that conversion.
 */
rac_model_category_t categoryFromProtoInt(int protoValue) {
    switch (protoValue) {
        case 1:  return RAC_MODEL_CATEGORY_LANGUAGE;                  // proto LANGUAGE
        case 2:  return RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;        // proto SPEECH_RECOGNITION
        case 3:  return RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;          // proto SPEECH_SYNTHESIS
        case 4:  return RAC_MODEL_CATEGORY_VISION;                    // proto VISION
        case 5:  return RAC_MODEL_CATEGORY_IMAGE_GENERATION;          // proto IMAGE_GENERATION
        case 6:  return RAC_MODEL_CATEGORY_MULTIMODAL;                // proto MULTIMODAL
        case 7:  return RAC_MODEL_CATEGORY_AUDIO;                     // proto AUDIO
        case 8:  return RAC_MODEL_CATEGORY_EMBEDDING;                 // proto EMBEDDING
        case 9:  return RAC_MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;  // proto VAD
        case 0:  // proto UNSPECIFIED — treat as unknown
        default: return RAC_MODEL_CATEGORY_UNKNOWN;
    }
}

// Convert TypeScript format string to C++ enum
rac_model_format_t formatFromString(const std::string& format) {
    if (format == "GGUF" || format == "gguf") return RAC_MODEL_FORMAT_GGUF;
    if (format == "GGML" || format == "ggml") return RAC_MODEL_FORMAT_BIN;  // GGML -> BIN as fallback
    if (format == "ONNX" || format == "onnx") return RAC_MODEL_FORMAT_ONNX;
    if (format == "ORT" || format == "ort") return RAC_MODEL_FORMAT_ORT;
    if (format == "BIN" || format == "bin") return RAC_MODEL_FORMAT_BIN;
    return RAC_MODEL_FORMAT_UNKNOWN;
}

std::string jsonString(const std::string& value) {
    std::string escaped = "\"";
    for (char c : value) {
        if (c == '"') escaped += "\\\"";
        else if (c == '\\') escaped += "\\\\";
        else if (c == '\n') escaped += "\\n";
        else if (c == '\r') escaped += "\\r";
        else if (c == '\t') escaped += "\\t";
        else escaped += c;
    }
    escaped += "\"";
    return escaped;
}

std::string buildJsonObject(const std::vector<std::pair<std::string, std::string>>& keyValues) {
    std::string result = "{";
    for (size_t i = 0; i < keyValues.size(); i++) {
        if (i > 0) result += ",";
        result += "\"" + keyValues[i].first + "\":" + keyValues[i].second;
    }
    result += "}";
    return result;
}

// =============================================================================
// Native HTTP transport helpers (rac_http_client_* wrapper + cancel registry)
// =============================================================================

// Parse a JSON object of string → string headers. Deliberately minimal: we
// expect TypeScript callers to hand us a plain `{"Key":"Value",...}` object.
std::vector<std::pair<std::string, std::string>> parseHeadersJson(const std::string& headersJson) {
    std::vector<std::pair<std::string, std::string>> out;
    if (headersJson.empty()) return out;
    size_t i = 0;
    while (i < headersJson.size()) {
        size_t kStart = headersJson.find('"', i);
        if (kStart == std::string::npos) break;
        size_t kEnd = headersJson.find('"', kStart + 1);
        if (kEnd == std::string::npos) break;
        std::string key = headersJson.substr(kStart + 1, kEnd - kStart - 1);

        size_t colon = headersJson.find(':', kEnd + 1);
        if (colon == std::string::npos) break;
        size_t vStart = headersJson.find('"', colon + 1);
        if (vStart == std::string::npos) break;
        size_t vEnd = headersJson.find('"', vStart + 1);
        if (vEnd == std::string::npos) break;
        std::string value = headersJson.substr(vStart + 1, vEnd - vStart - 1);

        out.emplace_back(std::move(key), std::move(value));
        i = vEnd + 1;
    }
    return out;
}

struct NativeHttpResult {
    int32_t status = 0;
    std::string body;
    std::vector<std::pair<std::string, std::string>> headers;
};

// Execute a blocking HTTP request via rac_http_client_*. Throws std::runtime_error
// on transport-level failure (DNS / TLS / timeout). 4xx/5xx responses are
// returned through NativeHttpResult so callers can decide how to handle them.
NativeHttpResult performNativeHttpRequest(
    const std::string& method,
    const std::string& url,
    const std::vector<std::pair<std::string, std::string>>& headers,
    const std::string& body,
    int32_t timeoutMs
) {
    rac_http_client_t* client = nullptr;
    rac_result_t createResult = rac_http_client_create(&client);
    if (createResult != RAC_SUCCESS || !client) {
        throw std::runtime_error("rac_http_client_create failed (rc=" +
                                 std::to_string(createResult) + ")");
    }

    std::vector<rac_http_header_kv_t> headerKVs;
    headerKVs.reserve(headers.size());
    for (const auto& h : headers) {
        headerKVs.push_back(rac_http_header_kv_t{h.first.c_str(), h.second.c_str()});
    }

    rac_http_request_t req{};
    req.method = method.c_str();
    req.url = url.c_str();
    req.headers = headerKVs.empty() ? nullptr : headerKVs.data();
    req.header_count = headerKVs.size();
    req.body_bytes = body.empty() ? nullptr : reinterpret_cast<const uint8_t*>(body.data());
    req.body_len = body.size();
    req.timeout_ms = timeoutMs > 0 ? timeoutMs : 30000;
    req.follow_redirects = RAC_TRUE;
    req.expected_checksum_hex = nullptr;

    rac_http_response_t resp{};
    rac_result_t sendResult = rac_http_request_send(client, &req, &resp);
    rac_http_client_destroy(client);

    if (sendResult != RAC_SUCCESS) {
        rac_http_response_free(&resp);
        throw std::runtime_error("rac_http_request_send failed (rc=" +
                                 std::to_string(sendResult) + ")");
    }

    NativeHttpResult out;
    out.status = resp.status;
    if (resp.body_bytes && resp.body_len > 0) {
        out.body.assign(reinterpret_cast<const char*>(resp.body_bytes), resp.body_len);
    }
    if (resp.headers) {
        out.headers.reserve(resp.header_count);
        for (size_t i = 0; i < resp.header_count; i++) {
            out.headers.emplace_back(
                resp.headers[i].name ? resp.headers[i].name : "",
                resp.headers[i].value ? resp.headers[i].value : ""
            );
        }
    }
    rac_http_response_free(&resp);
    return out;
}

// Serialize a response-headers vector to `{"k":"v",...}`.
std::string headersToJson(const std::vector<std::pair<std::string, std::string>>& headers) {
    std::string out = "{";
    for (size_t i = 0; i < headers.size(); i++) {
        if (i > 0) out += ",";
        out += jsonString(headers[i].first) + ":" + jsonString(headers[i].second);
    }
    out += "}";
    return out;
}

// -----------------------------------------------------------------------------
// Download cancel registry — maps cancel tokens to atomic cancel flags. The
// progress callback reads the flag and returns RAC_FALSE to abort the
// download. The registry is thread-safe.
// -----------------------------------------------------------------------------
struct DownloadCancelRegistry {
    std::mutex mutex;
    std::unordered_map<std::string, std::shared_ptr<std::atomic<bool>>> flags;

    std::shared_ptr<std::atomic<bool>> registerToken(const std::string& token) {
        auto flag = std::make_shared<std::atomic<bool>>(false);
        std::lock_guard<std::mutex> lk(mutex);
        flags[token] = flag;
        return flag;
    }

    bool cancel(const std::string& token) {
        std::lock_guard<std::mutex> lk(mutex);
        auto it = flags.find(token);
        if (it == flags.end()) return false;
        it->second->store(true);
        return true;
    }

    void release(const std::string& token) {
        std::lock_guard<std::mutex> lk(mutex);
        flags.erase(token);
    }
};

DownloadCancelRegistry& downloadCancelRegistry() {
    static DownloadCancelRegistry instance;
    return instance;
}

} // anonymous namespace

} // namespace margelo::nitro::runanywhere
