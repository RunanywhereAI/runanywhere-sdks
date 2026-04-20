// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_model.h"

#include "../model_registry/model_compatibility.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

namespace {

std::string to_lower(std::string_view s) {
    std::string out; out.reserve(s.size());
    for (char c : s) out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    return out;
}

bool ends_with(std::string_view s, std::string_view suffix) {
    if (s.size() < suffix.size()) return false;
    return s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Framework × category support. Mirrors the main-branch table.
struct CapKey { std::string fw, cat; };
const std::unordered_set<std::string>& support_set() {
    static const std::unordered_set<std::string> s = {
        "llamacpp|llm",       "llamacpp|embedding",
        "onnx|llm",           "onnx|stt",            "onnx|vad",
        "onnx|embedding",     "onnx|wakeword",
        "whisperkit|stt",     "whisperkit_coreml|stt",
        "metalrt|llm",        "metalrt|stt",         "metalrt|tts",
        "metalrt|vlm",
        "genie|llm",
        "foundation_models|llm",
        "coreml|llm",         "coreml|stt",          "coreml|diffusion",
        "coreml|vlm",
        "mlx|llm",            "mlx|vlm",
        "sherpa|stt",         "sherpa|tts",          "sherpa|vad",
        "whispercpp|stt",
    };
    return s;
}

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

}  // namespace

extern "C" {

uint8_t ra_framework_supports(const char* framework, const char* category) {
    if (!framework || !category) return 0;
    std::string key = to_lower(framework) + "|" + to_lower(category);
    return support_set().count(key) ? 1 : 0;
}

ra_status_t ra_framework_support_matrix_json(char** out_json) {
    if (!out_json) return RA_ERR_INVALID_ARGUMENT;
    std::ostringstream os;
    os << "[";
    bool first = true;
    for (const auto& k : support_set()) {
        if (!first) os << ",";
        first = false;
        const auto bar = k.find('|');
        os << "{\"framework\":\"" << k.substr(0, bar)
           << "\",\"category\":\"" << k.substr(bar + 1) << "\"}";
    }
    os << "]";
    *out_json = dup_cstr(os.str());
    return *out_json ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

ra_model_format_t ra_model_detect_format(const char* url_or_path) {
    if (!url_or_path) return RA_MODEL_FORMAT_UNKNOWN;
    const std::string lower = to_lower(url_or_path);
    if (ends_with(lower, ".gguf"))                return RA_MODEL_FORMAT_GGUF;
    if (ends_with(lower, ".onnx"))                return RA_MODEL_FORMAT_ONNX;
    if (ends_with(lower, ".mlmodelc"))            return RA_MODEL_FORMAT_COREML;
    if (ends_with(lower, ".mlpackage"))           return RA_MODEL_FORMAT_COREML;
    if (ends_with(lower, ".mlmodel"))             return RA_MODEL_FORMAT_COREML;
    if (ends_with(lower, ".safetensors"))         return RA_MODEL_FORMAT_SAFETENSORS;
    if (ends_with(lower, ".tflite"))              return RA_MODEL_FORMAT_TFLITE;
    if (ends_with(lower, ".pte"))                 return RA_MODEL_FORMAT_EXECUTORCH;
    if (ends_with(lower, ".pt") || ends_with(lower, ".pth"))
                                                   return RA_MODEL_FORMAT_PYTORCH;
    if (ends_with(lower, ".whisperkit"))          return RA_MODEL_FORMAT_WHISPER_KIT;
    if (ends_with(lower, ".mlx") || ends_with(lower, ".mlx-safetensors"))
                                                   return RA_MODEL_FORMAT_MLX_SAFETENSORS;
    if (ends_with(lower, ".bin"))                 return RA_MODEL_FORMAT_BIN;
    return RA_MODEL_FORMAT_UNKNOWN;
}

int32_t ra_model_detect_archive_format(const char* url_or_path) {
    if (!url_or_path) return 0;
    const std::string lower = to_lower(url_or_path);
    if (ends_with(lower, ".zip"))       return 1;
    if (ends_with(lower, ".tar.gz"))    return 2;
    if (ends_with(lower, ".tgz"))       return 2;
    if (ends_with(lower, ".tar.bz2"))   return 3;
    if (ends_with(lower, ".tar.xz"))    return 4;
    if (ends_with(lower, ".tar"))       return 5;
    return 0;
}

ra_model_category_t ra_model_infer_category(const char* model_id) {
    if (!model_id) return RA_MODEL_CATEGORY_UNKNOWN;
    const std::string id = to_lower(model_id);
    if (id.find("whisper") != std::string::npos ||
        id.find("parakeet") != std::string::npos ||
        id.find("distil-whisper") != std::string::npos) {
        return RA_MODEL_CATEGORY_STT;
    }
    if (id.find("silero") != std::string::npos ||
        id.find("-vad") != std::string::npos) {
        return RA_MODEL_CATEGORY_VAD;
    }
    if (id.find("stable-diffusion") != std::string::npos ||
        id.find("sdxl") != std::string::npos ||
        id.find("flux") != std::string::npos) {
        return RA_MODEL_CATEGORY_DIFFUSION;
    }
    if (id.find("rerank") != std::string::npos) {
        return RA_MODEL_CATEGORY_RERANK;
    }
    if (id.find("bge") != std::string::npos ||
        id.find("embed") != std::string::npos ||
        id.find("minilm") != std::string::npos) {
        return RA_MODEL_CATEGORY_EMBEDDING;
    }
    if (id.find("hey-") != std::string::npos ||
        id.find("wakeword") != std::string::npos ||
        id.find("porcupine") != std::string::npos) {
        return RA_MODEL_CATEGORY_WAKEWORD;
    }
    if (id.find("kokoro") != std::string::npos ||
        id.find("piper") != std::string::npos ||
        id.find("tts") != std::string::npos) {
        return RA_MODEL_CATEGORY_TTS;
    }
    if (id.find("vlm") != std::string::npos ||
        id.find("-vl-") != std::string::npos ||
        id.find("llava") != std::string::npos ||
        id.find("moondream") != std::string::npos) {
        return RA_MODEL_CATEGORY_VLM;
    }
    // Default assumption: language model.
    return RA_MODEL_CATEGORY_LLM;
}

uint8_t ra_artifact_is_archive(const char* url_or_path) {
    return ra_model_detect_archive_format(url_or_path) != 0 ? 1 : 0;
}

uint8_t ra_artifact_is_directory(const char* url_or_path) {
    if (!url_or_path) return 0;
    const std::string lower = to_lower(url_or_path);
    return (ends_with(lower, ".mlmodelc") || ends_with(lower, ".mlpackage"))
        ? 1 : 0;
}

ra_status_t ra_model_check_compat(const char* model_id,
                                    int64_t available_memory_bytes,
                                    int64_t available_storage_bytes,
                                    ra_model_compat_t* out_result) {
    if (!model_id || !out_result) return RA_ERR_INVALID_ARGUMENT;
    const auto r = ra::core::check_model_compatibility(
        model_id, available_memory_bytes, available_storage_bytes);
    out_result->is_compatible           = r.is_compatible ? 1 : 0;
    out_result->can_run                 = r.can_run       ? 1 : 0;
    out_result->can_fit                 = r.can_fit       ? 1 : 0;
    out_result->required_memory_bytes   = r.required_memory_bytes;
    out_result->available_memory_bytes  = r.available_memory_bytes;
    out_result->required_storage_bytes  = r.required_storage_bytes;
    out_result->available_storage_bytes = r.available_storage_bytes;
    return RA_OK;
}

void ra_model_string_free(char* str) {
    if (str) std::free(str);
}

}  // extern "C"
