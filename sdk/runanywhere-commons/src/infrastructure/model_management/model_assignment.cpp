/**
 * @file model_assignment.cpp
 * @brief Model Assignment Manager Implementation
 */

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/network/rac_endpoints.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

static const char* LOG_CAT = "ModelAssignment";

// =============================================================================
// INTERNAL STATE
// =============================================================================

static rac_assignment_callbacks_t g_callbacks = {};
static std::mutex g_mutex;

// Cache
static std::vector<rac_model_info_t*> g_cached_models;
static std::chrono::steady_clock::time_point g_last_fetch_time;
static uint32_t g_cache_timeout_seconds = 3600;  // 1 hour default
static bool g_cache_valid = false;
#ifdef RAC_HAVE_PROTOBUF
static std::vector<std::string> g_cached_model_proto_bytes;
#endif

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static void clear_cache_internal() {
    for (auto* model : g_cached_models) {
        rac_model_info_free(model);
    }
    g_cached_models.clear();
#ifdef RAC_HAVE_PROTOBUF
    g_cached_model_proto_bytes.clear();
#endif
    g_cache_valid = false;
}

static bool is_cache_valid() {
    if (!g_cache_valid)
        return false;

    auto now = std::chrono::steady_clock::now();
    auto elapsed =
        std::chrono::duration_cast<std::chrono::seconds>(now - g_last_fetch_time).count();
    return std::cmp_less(elapsed, g_cache_timeout_seconds);
}

// JSON string extraction that honours escaped
// quotes and brace-depth tracking. The previous implementation walked
// to the next `"` without escape handling and looked at byte
// substrings (e.g. `find("null", pos)`), so a value containing `\"`,
// `},`, or `\\` could either be truncated mid-string or — worse —
// snap the field boundary so the wrong key/value pair got assigned.
// Reimplementation: scan once with an explicit in-string state machine.
static std::string json_get_string(const std::string& json, const std::string& key) {
    auto skip_ws = [&](size_t& i) {
        while (i < json.size() &&
               (json[i] == ' ' || json[i] == '\t' || json[i] == '\n' || json[i] == '\r')) {
            ++i;
        }
    };
    // Locate the key as a top-level (depth-aware) field name.
    bool in_string = false;
    bool escaped = false;
    int depth = 0;
    for (size_t i = 0; i < json.size(); ++i) {
        const char ch = json[i];
        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '"') {
                in_string = false;
            }
            continue;
        }
        if (ch == '"') {
            // Read the key string honouring escapes.
            size_t k = i + 1;
            std::string found_key;
            bool key_escaped = false;
            for (; k < json.size(); ++k) {
                const char kc = json[k];
                if (key_escaped) {
                    found_key.push_back(kc);
                    key_escaped = false;
                    continue;
                }
                if (kc == '\\') {
                    key_escaped = true;
                    continue;
                }
                if (kc == '"') {
                    break;
                }
                found_key.push_back(kc);
            }
            if (k >= json.size()) {
                return "";
            }
            i = k;
            // Match must be at depth 1 (inside the model object) — keys at
            // other depths belong to nested objects we should not pluck.
            if (depth != 1 || found_key != key) {
                continue;
            }
            // Walk to the ':' that starts the value.
            size_t colon = i + 1;
            skip_ws(colon);
            if (colon >= json.size() || json[colon] != ':') {
                return "";
            }
            size_t v = colon + 1;
            skip_ws(v);
            if (v >= json.size()) {
                return "";
            }
            // String value: read with escape handling.
            if (json[v] == '"') {
                std::string out;
                bool v_escaped = false;
                for (size_t p = v + 1; p < json.size(); ++p) {
                    const char vc = json[p];
                    if (v_escaped) {
                        // Minimal JSON escape support — the same one
                        // the proto path's `json_unescape_string` uses.
                        switch (vc) {
                            case '"':
                            case '\\':
                            case '/':
                                out.push_back(vc);
                                break;
                            case 'b':
                                out.push_back('\b');
                                break;
                            case 'f':
                                out.push_back('\f');
                                break;
                            case 'n':
                                out.push_back('\n');
                                break;
                            case 'r':
                                out.push_back('\r');
                                break;
                            case 't':
                                out.push_back('\t');
                                break;
                            default:
                                out.push_back(vc);
                                break;
                        }
                        v_escaped = false;
                        continue;
                    }
                    if (vc == '\\') {
                        v_escaped = true;
                        continue;
                    }
                    if (vc == '"') {
                        return out;
                    }
                    out.push_back(vc);
                }
                return "";
            }
            // null
            if (json.compare(v, 4, "null") == 0) {
                return "";
            }
            // Number / boolean — stop at the next top-level delimiter.
            size_t end = v;
            while (end < json.size() && json[end] != ',' && json[end] != '}' && json[end] != ']') {
                ++end;
            }
            std::string val = json.substr(v, end - v);
            while (!val.empty() && (val.back() == ' ' || val.back() == '\t' || val.back() == '\n' ||
                                    val.back() == '\r')) {
                val.pop_back();
            }
            return val;
        }
        if (ch == '{' || ch == '[') {
            ++depth;
        } else if (ch == '}' || ch == ']') {
            --depth;
        }
    }
    return "";
}

static int64_t json_get_int(const std::string& json, const std::string& key,
                            int64_t default_val = 0) {
    std::string val = json_get_string(json, key);
    if (val.empty())
        return default_val;
    return std::strtoll(val.c_str(), nullptr, 10);
}

static bool json_get_bool(const std::string& json, const std::string& key,
                          bool default_val = false) {
    std::string val = json_get_string(json, key);
    if (val.empty())
        return default_val;
    return val == "true";
}

// Walk from `pos` to the end of the next
// top-level JSON value (object/array/string/scalar), honouring strings
// and escapes. Returns the one-past-end index of the value, or npos
// when the JSON is truncated.
static size_t fast_json_value_end(const std::string& json, size_t start) {
    if (start >= json.size()) {
        return std::string::npos;
    }
    const char first = json[start];
    if (first == '"') {
        bool escaped = false;
        for (size_t i = start + 1; i < json.size(); ++i) {
            const char ch = json[i];
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '"') {
                return i + 1;
            }
        }
        return std::string::npos;
    }
    if (first == '{' || first == '[') {
        const char open = first;
        const char close = (first == '{') ? '}' : ']';
        int depth = 1;
        bool in_string = false;
        bool escaped = false;
        for (size_t i = start + 1; i < json.size(); ++i) {
            const char ch = json[i];
            if (in_string) {
                if (escaped) {
                    escaped = false;
                } else if (ch == '\\') {
                    escaped = true;
                } else if (ch == '"') {
                    in_string = false;
                }
                continue;
            }
            if (ch == '"') {
                in_string = true;
                continue;
            }
            if (ch == open) {
                ++depth;
            } else if (ch == close) {
                --depth;
                if (depth == 0) {
                    return i + 1;
                }
            }
        }
        return std::string::npos;
    }
    size_t end = start;
    while (end < json.size() && json[end] != ',' && json[end] != '}' && json[end] != ']') {
        ++end;
    }
    return end;
}

// Parse models array from JSON response
static std::vector<rac_model_info_t*> parse_models_json(const char* json_str, size_t len) {
    std::vector<rac_model_info_t*> models;
    if (!json_str || len == 0)
        return models;

    std::string json(json_str, len);

    // Find "models" array (the key may appear escaped inside a value;
    // require depth-0 match by walking the top-level structure first).
    size_t models_pos = json.find("\"models\"");
    if (models_pos == std::string::npos) {
        RAC_LOG_WARNING(LOG_CAT, "No 'models' array in response");
        return models;
    }

    // Find array start
    size_t arr_start = json.find('[', models_pos);
    if (arr_start == std::string::npos)
        return models;

    // Depth- and escape-aware scan over the
    // models array. The previous implementation only counted braces,
    // so a quote-balanced string containing `{` or `}` could pull the
    // wrong substring as an object.
    size_t pos = arr_start + 1;
    while (pos < json.size()) {
        // Skip whitespace and array separators between objects.
        while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' ||
                                     json[pos] == '\r' || json[pos] == ',')) {
            ++pos;
        }
        if (pos >= json.size() || json[pos] == ']') {
            break;
        }
        if (json[pos] != '{') {
            ++pos;
            continue;
        }

        size_t obj_end = fast_json_value_end(json, pos);
        if (obj_end == std::string::npos) {
            break;
        }

        std::string obj = json.substr(pos, obj_end - pos);

        // Parse model fields
        std::string id = json_get_string(obj, "id");
        std::string name = json_get_string(obj, "name");
        std::string category = json_get_string(obj, "category");
        std::string format = json_get_string(obj, "format");
        std::string framework = json_get_string(obj, "preferred_framework");
        std::string download_url = json_get_string(obj, "download_url");
        std::string description = json_get_string(obj, "description");
        int64_t size = json_get_int(obj, "size", 0);
        int context_length = static_cast<int>(json_get_int(obj, "context_length", 0));
        bool supports_thinking = json_get_bool(obj, "supports_thinking", false);

        if (id.empty()) {
            pos = obj_end;
            continue;
        }

        // Create model info
        rac_model_info_t* model = rac_model_info_alloc();
        if (!model)
            continue;

        model->id = strdup(id.c_str());
        model->name = strdup(name.c_str());
        if (!model->id || !model->name) {
            rac_model_info_free(model);
            pos = obj_end;
            continue;
        }
        model->download_url = download_url.empty() ? nullptr : strdup(download_url.c_str());
        model->description = description.empty() ? nullptr : strdup(description.c_str());
        model->download_size = size;
        model->context_length = context_length;
        model->supports_thinking = supports_thinking ? RAC_TRUE : RAC_FALSE;
        model->source = RAC_MODEL_SOURCE_REMOTE;

        // Parse category
        if (category == "language")
            model->category = RAC_MODEL_CATEGORY_LANGUAGE;
        else if (category == "speech" || category == "stt")
            model->category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION;
        else if (category == "tts")
            model->category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
        else if (category == "vision")
            model->category = RAC_MODEL_CATEGORY_VISION;
        else if (category == "audio")
            model->category = RAC_MODEL_CATEGORY_AUDIO;
        else if (category == "multimodal")
            model->category = RAC_MODEL_CATEGORY_MULTIMODAL;
        else
            model->category = RAC_MODEL_CATEGORY_LANGUAGE;

        // Parse format
        if (format == "gguf")
            model->format = RAC_MODEL_FORMAT_GGUF;
        else if (format == "ggml")
            model->format = RAC_MODEL_FORMAT_GGML;
        else if (format == "onnx")
            model->format = RAC_MODEL_FORMAT_ONNX;
        else if (format == "ort")
            model->format = RAC_MODEL_FORMAT_ORT;
        else if (format == "bin")
            model->format = RAC_MODEL_FORMAT_BIN;
        else if (format == "coreml" || format == "mlmodelc")
            model->format = RAC_MODEL_FORMAT_COREML;
        else if (format == "mlmodel")
            model->format = RAC_MODEL_FORMAT_MLMODEL;
        else if (format == "mlpackage")
            model->format = RAC_MODEL_FORMAT_MLPACKAGE;
        else if (format == "tflite")
            model->format = RAC_MODEL_FORMAT_TFLITE;
        else if (format == "safetensors")
            model->format = RAC_MODEL_FORMAT_SAFETENSORS;
        else if (format == "qnn_context" || format == "qnn-context")
            model->format = RAC_MODEL_FORMAT_QNN_CONTEXT;
        else if (format == "zip")
            model->format = RAC_MODEL_FORMAT_ZIP;
        else if (format == "folder" || format == "directory")
            model->format = RAC_MODEL_FORMAT_FOLDER;
        else if (format == "proprietary" || format == "builtin" || format == "built_in")
            model->format = RAC_MODEL_FORMAT_PROPRIETARY;
        else
            model->format = RAC_MODEL_FORMAT_UNKNOWN;

        // Parse framework
        if (framework == "llama.cpp" || framework == "llamacpp")
            model->framework = RAC_FRAMEWORK_LLAMACPP;
        else if (framework == "onnx" || framework == "onnxruntime")
            model->framework = RAC_FRAMEWORK_ONNX;
        else if (framework == "foundation_models" || framework == "platform-llm-default")
            model->framework = RAC_FRAMEWORK_FOUNDATION_MODELS;
        else if (framework == "system_tts" || framework == "platform-tts")
            model->framework = RAC_FRAMEWORK_SYSTEM_TTS;
        else if (framework == "coreml" || framework == "core_ml" || framework == "CoreML")
            model->framework = RAC_FRAMEWORK_COREML;
        else if (framework == "mlx" || framework == "MLX")
            model->framework = RAC_FRAMEWORK_MLX;
        else if (framework == "fluid_audio" || framework == "FluidAudio")
            model->framework = RAC_FRAMEWORK_FLUID_AUDIO;
        else if (framework == "genie" || framework == "qnn_genie" || framework == "Genie")
            model->framework = RAC_FRAMEWORK_GENIE;
        else if (framework == "sherpa" || framework == "sherpa_onnx" || framework == "sherpa-onnx")
            model->framework = RAC_FRAMEWORK_SHERPA;
        else
            model->framework = RAC_FRAMEWORK_UNKNOWN;

        models.push_back(model);
        pos = obj_end;
    }

    return models;
}

// Copy models array for output
static rac_result_t copy_models_to_output(const std::vector<rac_model_info_t*>& models,
                                          rac_model_info_t*** out_models, size_t* out_count) {
    if (!out_models || !out_count)
        return RAC_ERROR_NULL_POINTER;

    *out_count = models.size();
    if (models.empty()) {
        *out_models = nullptr;
        return RAC_SUCCESS;
    }

    *out_models =
        static_cast<rac_model_info_t**>(malloc(models.size() * sizeof(rac_model_info_t*)));
    if (!*out_models) {
        *out_count = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (size_t i = 0; i < models.size(); i++) {
        (*out_models)[i] = rac_model_info_copy(models[i]);
        if (!(*out_models)[i]) {
            // Cleanup on error
            for (size_t j = 0; j < i; j++) {
                rac_model_info_free((*out_models)[j]);
            }
            free(static_cast<void*>(*out_models));
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

// Pure C-enum predicate: a model format "needs inference" when it is the
// unspecified/unknown sentinel. Defined OUTSIDE the RAC_HAVE_PROTOBUF guard
// because it has no protobuf dependency and is also called from the public
// (always-compiled) refresh/fetch path below (the existing-vs-incoming
// format-preservation merge). Keeping it inside the protobuf guard made the
// no-protobuf build (e.g. WASM without a system libprotobuf) fail with "use
// of undeclared identifier 'c_format_needs_inference'".
static bool c_format_needs_inference(rac_model_format_t format) {
    return format == RAC_MODEL_FORMAT_UNSPECIFIED || format == RAC_MODEL_FORMAT_UNKNOWN;
}

#ifdef RAC_HAVE_PROTOBUF

using runanywhere::v1::InferenceFramework;
using runanywhere::v1::ModelCategory;
using runanywhere::v1::ModelFormat;
using runanywhere::v1::ModelInfo;
using runanywhere::v1::ModelInfoList;
using runanywhere::v1::ModelRegistryRefreshRequest;
using runanywhere::v1::ModelRegistryRefreshResult;
using runanywhere::v1::ModelRegistryStatus;

static rac_result_t assignment_proto_error(rac_proto_buffer_t* out_buffer, rac_result_t status,
                                           const char* message) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return rac_proto_buffer_set_error(out_buffer, status,
                                      message ? message : rac_error_message(status));
}

template <typename ProtoMessage>
static rac_result_t serialize_assignment_proto(const ProtoMessage& message,
                                               rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::string bytes;
    if (!message.SerializeToString(&bytes)) {
        return assignment_proto_error(out_buffer, RAC_ERROR_ENCODING_ERROR,
                                      "failed to serialize model assignment proto result");
    }
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                                 out_buffer);
}

static rac_result_t parse_assignment_refresh_request(const uint8_t* proto_bytes, size_t proto_size,
                                                     ModelRegistryRefreshRequest* out,
                                                     rac_proto_buffer_t* error_out) {
    if (!out) {
        return assignment_proto_error(error_out, RAC_ERROR_INVALID_ARGUMENT,
                                      "ModelRegistryRefreshRequest output is required");
    }

    rac_result_t validation = rac_proto_bytes_validate(proto_bytes, proto_size);
    if (validation != RAC_SUCCESS) {
        return assignment_proto_error(error_out, validation, "proto bytes are null or too large");
    }

    if (!out->ParseFromArray(rac_proto_bytes_data_or_empty(proto_bytes, proto_size),
                             static_cast<int>(proto_size))) {
        return assignment_proto_error(error_out, RAC_ERROR_INVALID_FORMAT,
                                      "failed to parse ModelRegistryRefreshRequest");
    }
    return RAC_SUCCESS;
}

static std::string lower_copy(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    for (unsigned char ch : input) {
        out.push_back(static_cast<char>(std::tolower(ch)));
    }
    return out;
}

static bool ends_with_copy(const std::string& value, const std::string& suffix) {
    return value.ends_with(suffix);
}

static ModelFormat infer_proto_format_from_path(const std::string& value) {
    const std::string lower = lower_copy(value);
    if (ends_with_copy(lower, ".gguf"))
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    if (ends_with_copy(lower, ".ggml"))
        return runanywhere::v1::MODEL_FORMAT_GGML;
    if (ends_with_copy(lower, ".onnx"))
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    if (ends_with_copy(lower, ".ort"))
        return runanywhere::v1::MODEL_FORMAT_ORT;
    if (ends_with_copy(lower, ".bin"))
        return runanywhere::v1::MODEL_FORMAT_BIN;
    if (ends_with_copy(lower, ".tflite"))
        return runanywhere::v1::MODEL_FORMAT_TFLITE;
    if (ends_with_copy(lower, ".safetensors"))
        return runanywhere::v1::MODEL_FORMAT_SAFETENSORS;
    if (ends_with_copy(lower, ".mlmodel"))
        return runanywhere::v1::MODEL_FORMAT_MLMODEL;
    if (ends_with_copy(lower, ".mlpackage"))
        return runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    if (ends_with_copy(lower, ".zip") || ends_with_copy(lower, ".tar.gz") ||
        ends_with_copy(lower, ".tar.bz2") || ends_with_copy(lower, ".tar.xz")) {
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    }
    return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

static bool proto_format_needs_inference(ModelFormat format) {
    return format == runanywhere::v1::MODEL_FORMAT_UNSPECIFIED ||
           format == runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

// NOTE: c_format_needs_inference (the pure C-enum variant) is intentionally
// defined ABOVE the #ifdef RAC_HAVE_PROTOBUF block — it is also used by the
// always-compiled public refresh path and must exist in no-protobuf builds.

static bool proto_framework_needs_inference(InferenceFramework framework) {
    return framework == runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED ||
           framework == runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
}

static InferenceFramework infer_proto_framework_from_format(ModelFormat format) {
    switch (format) {
        case runanywhere::v1::MODEL_FORMAT_GGUF:
        case runanywhere::v1::MODEL_FORMAT_GGML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case runanywhere::v1::MODEL_FORMAT_ONNX:
        case runanywhere::v1::MODEL_FORMAT_ORT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case runanywhere::v1::MODEL_FORMAT_COREML:
        case runanywhere::v1::MODEL_FORMAT_MLMODEL:
        case runanywhere::v1::MODEL_FORMAT_MLPACKAGE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        case runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
        case runanywhere::v1::MODEL_FORMAT_TFLITE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE;
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

static ModelCategory infer_proto_category_from_framework(InferenceFramework framework) {
    switch (framework) {
        case runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
        case runanywhere::v1::INFERENCE_FRAMEWORK_PIPER_TTS:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
        case runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
        case runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA:
            return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
        case runanywhere::v1::INFERENCE_FRAMEWORK_COREML:
        case runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE:
        case runanywhere::v1::INFERENCE_FRAMEWORK_MEDIAPIPE:
            return runanywhere::v1::MODEL_CATEGORY_VISION;
        case runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
        case runanywhere::v1::INFERENCE_FRAMEWORK_ONNX:
        case runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLX:
        case runanywhere::v1::INFERENCE_FRAMEWORK_METALRT:
        case runanywhere::v1::INFERENCE_FRAMEWORK_GENIE:
        case runanywhere::v1::INFERENCE_FRAMEWORK_EXECUTORCH:
        case runanywhere::v1::INFERENCE_FRAMEWORK_MLC:
        case runanywhere::v1::INFERENCE_FRAMEWORK_PICO_LLM:
        case runanywhere::v1::INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
            return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
        default:
            return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
    }
}

static InferenceFramework proto_framework_from_struct(rac_inference_framework_t framework) {
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case RAC_FRAMEWORK_LLAMACPP:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
        case RAC_FRAMEWORK_BUILTIN:
            return runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN;
        case RAC_FRAMEWORK_NONE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_NONE;
        case RAC_FRAMEWORK_MLX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
        case RAC_FRAMEWORK_COREML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        case RAC_FRAMEWORK_METALRT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_METALRT;
        case RAC_FRAMEWORK_GENIE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
        case RAC_FRAMEWORK_SHERPA:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
        case RAC_FRAMEWORK_UNKNOWN:
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

static ModelFormat proto_format_from_struct(rac_model_format_t format) {
    const int value = static_cast<int>(format);
    return runanywhere::v1::ModelFormat_IsValid(value) ? static_cast<ModelFormat>(value)
                                                       : runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

static ModelRegistryStatus effective_assignment_status(const ModelInfo& model) {
    if (model.has_registry_status()) {
        return model.registry_status();
    }
    if (!model.local_path().empty() || (model.has_is_downloaded() && model.is_downloaded())) {
        return runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED;
    }
    return runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED;
}

static bool assignment_model_is_downloaded(const ModelInfo& model) {
    if (!model.local_path().empty()) {
        return true;
    }
    if (model.has_is_downloaded()) {
        return model.is_downloaded();
    }
    const ModelRegistryStatus status = effective_assignment_status(model);
    return status == runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED ||
           status == runanywhere::v1::MODEL_REGISTRY_STATUS_LOADED;
}

static bool assignment_model_is_available(const ModelInfo& model) {
    if (model.has_is_available()) {
        return model.is_available();
    }
    return assignment_model_is_downloaded(model);
}

static void normalize_assignment_model(ModelInfo* model) {
    if (!model) {
        return;
    }

    if (model->id().empty() && !model->download_url().empty()) {
        char generated_id[256] = {};
        rac_model_generate_id(model->download_url().c_str(), generated_id, sizeof(generated_id));
        if (generated_id[0] != '\0') {
            model->set_id(generated_id);
        }
    }
    if (model->name().empty() && !model->id().empty()) {
        model->set_name(model->id());
    }

    if (proto_format_needs_inference(model->format())) {
        ModelFormat inferred = infer_proto_format_from_path(model->download_url());
        if (proto_format_needs_inference(inferred)) {
            inferred = infer_proto_format_from_path(model->id());
        }
        model->set_format(inferred);
    }

    if (proto_framework_needs_inference(model->framework())) {
        model->set_framework(infer_proto_framework_from_format(model->format()));
    }
    if ((!model->has_preferred_framework() ||
         proto_framework_needs_inference(model->preferred_framework())) &&
        !proto_framework_needs_inference(model->framework())) {
        model->set_preferred_framework(model->framework());
    }

    if (model->category() == runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED) {
        model->set_category(infer_proto_category_from_framework(model->framework()));
    }

    if (model->source() == runanywhere::v1::MODEL_SOURCE_UNSPECIFIED) {
        const bool built_in =
            (model->has_artifact_type() &&
             model->artifact_type() == runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN) ||
            model->artifact_case() == ModelInfo::kBuiltIn;
        model->set_source(built_in ? runanywhere::v1::MODEL_SOURCE_BUILT_IN
                                   : runanywhere::v1::MODEL_SOURCE_REMOTE);
    }

    if (model->download_size_bytes() < 0) {
        model->set_download_size_bytes(0);
    }

    if (model->description().empty() && model->has_metadata() &&
        !model->metadata().description().empty()) {
        model->set_description(model->metadata().description());
    }
    if (!model->description().empty() &&
        (!model->has_metadata() || model->metadata().description().empty())) {
        model->mutable_metadata()->set_description(model->description());
    }

    if (model->artifact_case() == ModelInfo::ARTIFACT_NOT_SET) {
        model->mutable_single_file();
    }
    if (!model->has_artifact_type() ||
        model->artifact_type() == runanywhere::v1::MODEL_ARTIFACT_TYPE_UNSPECIFIED) {
        switch (model->artifact_case()) {
            case ModelInfo::kArchive:
                model->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_ARCHIVE);
                break;
            case ModelInfo::kMultiFile:
                model->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_MULTI_FILE);
                break;
            case ModelInfo::kCustomStrategyId:
                model->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_CUSTOM);
                break;
            case ModelInfo::kBuiltIn:
                model->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_BUILT_IN);
                break;
            case ModelInfo::kSingleFile:
            case ModelInfo::ARTIFACT_NOT_SET:
            default:
                model->set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
                break;
        }
    }

    if (!model->has_compatibility()) {
        if (!proto_framework_needs_inference(model->framework())) {
            model->mutable_compatibility()->add_compatible_frameworks(model->framework());
        }
        if (!proto_format_needs_inference(model->format())) {
            model->mutable_compatibility()->add_compatible_formats(model->format());
        }
    }

    const bool downloaded = assignment_model_is_downloaded(*model);
    if (!model->has_is_downloaded()) {
        model->set_is_downloaded(downloaded);
    }
    if (!model->has_is_available()) {
        model->set_is_available(downloaded);
    }
    if (!model->has_registry_status()) {
        model->set_registry_status(downloaded ? runanywhere::v1::MODEL_REGISTRY_STATUS_DOWNLOADED
                                              : runanywhere::v1::MODEL_REGISTRY_STATUS_REGISTERED);
    }
}

static void overlay_existing_registry_model(ModelInfo* model, rac_model_registry_handle_t registry,
                                            int32_t* updated_count) {
    if (!model || !registry || model->id().empty()) {
        return;
    }

    rac_model_info_t* existing = nullptr;
    if (rac_model_registry_get(registry, model->id().c_str(), &existing) != RAC_SUCCESS ||
        !existing) {
        return;
    }

    if (updated_count) {
        ++(*updated_count);
    }

    if (proto_framework_needs_inference(model->framework()) &&
        existing->framework != RAC_FRAMEWORK_UNKNOWN) {
        model->set_framework(proto_framework_from_struct(existing->framework));
    }
    if ((!model->has_preferred_framework() ||
         proto_framework_needs_inference(model->preferred_framework())) &&
        existing->framework != RAC_FRAMEWORK_UNKNOWN) {
        model->set_preferred_framework(proto_framework_from_struct(existing->framework));
    }
    if (proto_format_needs_inference(model->format()) &&
        !c_format_needs_inference(existing->format)) {
        model->set_format(proto_format_from_struct(existing->format));
    }
    if (model->local_path().empty() && existing->local_path && existing->local_path[0] != '\0') {
        model->set_local_path(existing->local_path);
    }

    rac_model_info_free(existing);
    normalize_assignment_model(model);
}

static void free_model_vector(std::vector<rac_model_info_t*>* models) {
    if (!models) {
        return;
    }
    for (rac_model_info_t* model : *models) {
        rac_model_info_free(model);
    }
    models->clear();
}

static rac_result_t rebuild_cached_proto_bytes_from_registry_locked() {
    g_cached_model_proto_bytes.clear();
    if (g_cached_models.empty()) {
        return RAC_SUCCESS;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return RAC_SUCCESS;
    }

    for (const rac_model_info_t* model : g_cached_models) {
        if (!model || !model->id) {
            continue;
        }
        uint8_t* bytes = nullptr;
        size_t size = 0;
        if (rac_model_registry_get_proto(registry, model->id, &bytes, &size) == RAC_SUCCESS &&
            bytes) {
            g_cached_model_proto_bytes.emplace_back(reinterpret_cast<const char*>(bytes), size);
            rac_model_registry_proto_free(bytes);
        }
    }
    return RAC_SUCCESS;
}

static std::vector<ModelInfo> cached_proto_models_locked() {
    if (g_cached_model_proto_bytes.empty() && !g_cached_models.empty()) {
        rebuild_cached_proto_bytes_from_registry_locked();
    }

    std::vector<ModelInfo> models;
    models.reserve(g_cached_model_proto_bytes.size());
    for (const std::string& bytes : g_cached_model_proto_bytes) {
        ModelInfo model;
        if (model.ParseFromArray(bytes.data(), static_cast<int>(bytes.size()))) {
            normalize_assignment_model(&model);
            models.push_back(std::move(model));
        }
    }
    return models;
}

static rac_result_t update_assignment_cache_from_proto_locked(const std::vector<ModelInfo>& models,
                                                              int32_t* updated_count) {
    std::vector<std::string> next_proto_cache;
    std::vector<rac_model_info_t*> next_struct_cache;
    next_proto_cache.reserve(models.size());
    next_struct_cache.reserve(models.size());

    rac_model_registry_handle_t registry = rac_get_model_registry();
    int32_t local_updated_count = 0;

    for (const ModelInfo& input : models) {
        ModelInfo model(input);
        normalize_assignment_model(&model);
        if (model.id().empty()) {
            continue;
        }
        overlay_existing_registry_model(&model, registry, &local_updated_count);

        std::string bytes;
        if (!model.SerializeToString(&bytes)) {
            free_model_vector(&next_struct_cache);
            return RAC_ERROR_ENCODING_ERROR;
        }
        next_proto_cache.push_back(bytes);

        if (registry) {
            rac_result_t rc = rac_model_registry_register_proto(
                registry, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
            if (rc != RAC_SUCCESS) {
                free_model_vector(&next_struct_cache);
                return rc;
            }

            rac_model_info_t* struct_model = nullptr;
            if (rac_model_registry_get(registry, model.id().c_str(), &struct_model) ==
                    RAC_SUCCESS &&
                struct_model) {
                next_struct_cache.push_back(struct_model);
            }
        }
    }

    clear_cache_internal();
    g_cached_model_proto_bytes = std::move(next_proto_cache);
    g_cached_models = std::move(next_struct_cache);
    g_last_fetch_time = std::chrono::steady_clock::now();
    g_cache_valid = true;
    if (updated_count) {
        *updated_count = local_updated_count;
    }
    return RAC_SUCCESS;
}

static std::string trim_copy(const std::string& value) {
    size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])) != 0) {
        ++start;
    }
    size_t end = value.size();
    while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
        --end;
    }
    return value.substr(start, end - start);
}

static size_t json_string_end(const std::string& json, size_t quote_pos) {
    if (quote_pos >= json.size() || json[quote_pos] != '"') {
        return std::string::npos;
    }
    bool escaped = false;
    for (size_t i = quote_pos + 1; i < json.size(); ++i) {
        const char ch = json[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == '"') {
            return i;
        }
    }
    return std::string::npos;
}

static size_t json_value_end(const std::string& json, size_t value_start) {
    if (value_start >= json.size()) {
        return std::string::npos;
    }
    const char first = json[value_start];
    if (first == '"') {
        size_t end = json_string_end(json, value_start);
        return end == std::string::npos ? end : end + 1;
    }
    if (first == '{' || first == '[') {
        const char open = first;
        const char close = first == '{' ? '}' : ']';
        int depth = 1;
        bool in_string = false;
        bool escaped = false;
        for (size_t i = value_start + 1; i < json.size(); ++i) {
            const char ch = json[i];
            if (in_string) {
                if (escaped) {
                    escaped = false;
                } else if (ch == '\\') {
                    escaped = true;
                } else if (ch == '"') {
                    in_string = false;
                }
                continue;
            }
            if (ch == '"') {
                in_string = true;
                continue;
            }
            if (ch == open) {
                ++depth;
            } else if (ch == close) {
                --depth;
                if (depth == 0) {
                    return i + 1;
                }
            }
        }
        return std::string::npos;
    }

    size_t end = value_start;
    while (end < json.size() && json[end] != ',' && json[end] != '}' && json[end] != ']') {
        ++end;
    }
    return end;
}

static std::string json_unescape_string(const std::string& quoted_or_raw) {
    std::string value = trim_copy(quoted_or_raw);
    if (value.size() < 2 || value.front() != '"' || value.back() != '"') {
        return value == "null" ? std::string() : value;
    }

    std::string out;
    out.reserve(value.size() - 2);
    bool escaped = false;
    for (size_t i = 1; i + 1 < value.size(); ++i) {
        const char ch = value[i];
        if (!escaped) {
            if (ch == '\\') {
                escaped = true;
            } else {
                out.push_back(ch);
            }
            continue;
        }

        switch (ch) {
            case '"':
            case '\\':
            case '/':
                out.push_back(ch);
                break;
            case 'b':
                out.push_back('\b');
                break;
            case 'f':
                out.push_back('\f');
                break;
            case 'n':
                out.push_back('\n');
                break;
            case 'r':
                out.push_back('\r');
                break;
            case 't':
                out.push_back('\t');
                break;
            default:
                out.push_back(ch);
                break;
        }
        escaped = false;
    }
    return out;
}

static bool assignment_json_value(const std::string& json, const char* key,
                                  std::string* out_value) {
    if (!key || !out_value) {
        return false;
    }

    bool in_string = false;
    bool escaped = false;
    for (size_t i = 0; i < json.size(); ++i) {
        const char ch = json[i];
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == '"') {
                in_string = false;
            }
            continue;
        }
        if (ch != '"') {
            continue;
        }

        const size_t key_end = json_string_end(json, i);
        if (key_end == std::string::npos) {
            return false;
        }
        const std::string found_key = json_unescape_string(json.substr(i, key_end - i + 1));
        i = key_end;
        if (found_key != key) {
            continue;
        }

        size_t colon = i + 1;
        while (colon < json.size() && std::isspace(static_cast<unsigned char>(json[colon])) != 0) {
            ++colon;
        }
        if (colon >= json.size() || json[colon] != ':') {
            continue;
        }
        size_t value_start = colon + 1;
        while (value_start < json.size() &&
               std::isspace(static_cast<unsigned char>(json[value_start])) != 0) {
            ++value_start;
        }
        const size_t value_end = json_value_end(json, value_start);
        if (value_end == std::string::npos) {
            return false;
        }
        *out_value = json.substr(value_start, value_end - value_start);
        return true;
    }
    return false;
}

static std::string assignment_json_string_any(const std::string& json, const char* key_a,
                                              const char* key_b = nullptr,
                                              const char* key_c = nullptr) {
    std::string value;
    if ((key_a && assignment_json_value(json, key_a, &value)) ||
        (key_b && assignment_json_value(json, key_b, &value)) ||
        (key_c && assignment_json_value(json, key_c, &value))) {
        return json_unescape_string(value);
    }
    return "";
}

static int64_t assignment_json_int_any(const std::string& json, int64_t default_value,
                                       const char* key_a, const char* key_b = nullptr,
                                       const char* key_c = nullptr) {
    const std::string value = assignment_json_string_any(json, key_a, key_b, key_c);
    if (value.empty()) {
        return default_value;
    }
    char* end = nullptr;
    const long long parsed = std::strtoll(value.c_str(), &end, 10);
    return end == value.c_str() ? default_value : static_cast<int64_t>(parsed);
}

static bool assignment_json_bool_any(const std::string& json, bool default_value, const char* key_a,
                                     const char* key_b = nullptr) {
    const std::string value = lower_copy(assignment_json_string_any(json, key_a, key_b));
    if (value.empty()) {
        return default_value;
    }
    return value == "true" || value == "1";
}

static bool parse_int_token(const std::string& token, int64_t* out) {
    if (!out || token.empty()) {
        return false;
    }
    char* end = nullptr;
    const long long parsed = std::strtoll(token.c_str(), &end, 10);
    if (end == token.c_str() || (end && *end != '\0')) {
        return false;
    }
    *out = static_cast<int64_t>(parsed);
    return true;
}

static ModelCategory category_from_assignment_token(const std::string& token) {
    const std::string lower = lower_copy(token);
    int64_t numeric = 0;
    if (parse_int_token(lower, &numeric)) {
        switch (numeric) {
            case 0:
                return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
            case 1:
                return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
            case 2:
                return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
            case 3:
                return runanywhere::v1::MODEL_CATEGORY_VISION;
            case 4:
                return runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION;
            case 5:
                return runanywhere::v1::MODEL_CATEGORY_MULTIMODAL;
            case 6:
                return runanywhere::v1::MODEL_CATEGORY_AUDIO;
            case 7:
                return runanywhere::v1::MODEL_CATEGORY_EMBEDDING;
            case 8:
            case 9:
                return runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
            default:
                return runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
        }
    }
    if (lower == "language" || lower == "llm" || lower == "chat") {
        return runanywhere::v1::MODEL_CATEGORY_LANGUAGE;
    }
    if (lower == "speech" || lower == "stt" || lower == "asr" || lower == "speech_recognition" ||
        lower == "speech-recognition") {
        return runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION;
    }
    if (lower == "tts" || lower == "speech_synthesis" || lower == "speech-synthesis") {
        return runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS;
    }
    if (lower == "vision")
        return runanywhere::v1::MODEL_CATEGORY_VISION;
    if (lower == "image_generation" || lower == "image-generation") {
        return runanywhere::v1::MODEL_CATEGORY_IMAGE_GENERATION;
    }
    if (lower == "multimodal" || lower == "multi_modal") {
        return runanywhere::v1::MODEL_CATEGORY_MULTIMODAL;
    }
    if (lower == "audio")
        return runanywhere::v1::MODEL_CATEGORY_AUDIO;
    if (lower == "embedding" || lower == "embeddings") {
        return runanywhere::v1::MODEL_CATEGORY_EMBEDDING;
    }
    if (lower == "vad" || lower == "voice_activity_detection" ||
        lower == "voice-activity-detection") {
        return runanywhere::v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
    }
    return runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
}

static ModelFormat format_from_assignment_token(const std::string& token) {
    const std::string lower = lower_copy(token);
    int64_t numeric = 0;
    if (parse_int_token(lower, &numeric)) {
        return numeric >= std::numeric_limits<int>::min() &&
                       numeric <= std::numeric_limits<int>::max() &&
                       runanywhere::v1::ModelFormat_IsValid(static_cast<int>(numeric))
                   ? static_cast<ModelFormat>(numeric)
                   : runanywhere::v1::MODEL_FORMAT_UNKNOWN;
    }
    if (lower == "unspecified")
        return runanywhere::v1::MODEL_FORMAT_UNSPECIFIED;
    if (lower == "gguf")
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    if (lower == "ggml")
        return runanywhere::v1::MODEL_FORMAT_GGML;
    if (lower == "onnx")
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    if (lower == "ort")
        return runanywhere::v1::MODEL_FORMAT_ORT;
    if (lower == "bin")
        return runanywhere::v1::MODEL_FORMAT_BIN;
    if (lower == "coreml" || lower == "core_ml" || lower == "mlmodelc") {
        return runanywhere::v1::MODEL_FORMAT_COREML;
    }
    if (lower == "mlmodel")
        return runanywhere::v1::MODEL_FORMAT_MLMODEL;
    if (lower == "mlpackage")
        return runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    if (lower == "qnn_context" || lower == "qnn-context") {
        return runanywhere::v1::MODEL_FORMAT_QNN_CONTEXT;
    }
    if (lower == "tflite")
        return runanywhere::v1::MODEL_FORMAT_TFLITE;
    if (lower == "safetensors")
        return runanywhere::v1::MODEL_FORMAT_SAFETENSORS;
    if (lower == "zip")
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    if (lower == "folder" || lower == "directory")
        return runanywhere::v1::MODEL_FORMAT_FOLDER;
    if (lower == "proprietary" || lower == "builtin" || lower == "built_in") {
        return runanywhere::v1::MODEL_FORMAT_PROPRIETARY;
    }
    if (lower == "unknown")
        return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
    return runanywhere::v1::MODEL_FORMAT_UNKNOWN;
}

static InferenceFramework framework_from_assignment_token(const std::string& token) {
    const std::string lower = lower_copy(token);
    int64_t numeric = 0;
    if (parse_int_token(lower, &numeric)) {
        switch (numeric) {
            case 0:
                return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
            case 1:
                return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
            case 2:
                return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
            case 3:
                return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
            case 4:
                return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
            case 5:
                return runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN;
            case 6:
                return runanywhere::v1::INFERENCE_FRAMEWORK_NONE;
            case 7:
                return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
            case 8:
                return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
            // Value 9 (WHISPERKIT_COREML) retired — falls through to UNKNOWN.
            case 10:
                return runanywhere::v1::INFERENCE_FRAMEWORK_METALRT;
            case 11:
                return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
            case 12:
                return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
            default:
                return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
        }
    }
    if (lower == "llama.cpp" || lower == "llamacpp" || lower == "llama_cpp" ||
        lower == "llama-cpp") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
    }
    if (lower == "onnx" || lower == "onnxruntime" || lower == "onnx_runtime") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
    }
    if (lower == "foundation_models" || lower == "foundation-models" ||
        lower == "platform-llm-default") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
    }
    if (lower == "system_tts" || lower == "system-tts" || lower == "platform-tts") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
    }
    if (lower == "coreml" || lower == "core_ml") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
    }
    if (lower == "mlx")
        return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
    if (lower == "fluid_audio" || lower == "fluid-audio") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
    }
    if (lower == "genie" || lower == "qnn_genie" || lower == "qnn-genie") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
    }
    if (lower == "sherpa" || lower == "sherpa_onnx" || lower == "sherpa-onnx") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
    }
    if (lower == "tflite")
        return runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE;
    return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
}

static std::vector<std::string> json_top_level_objects(const std::string& array_json) {
    std::vector<std::string> objects;
    const std::string array = trim_copy(array_json);
    if (array.empty() || array.front() != '[') {
        return objects;
    }

    size_t pos = 1;
    while (pos < array.size()) {
        while (pos < array.size() &&
               (std::isspace(static_cast<unsigned char>(array[pos])) != 0 || array[pos] == ',')) {
            ++pos;
        }
        if (pos >= array.size() || array[pos] == ']') {
            break;
        }
        if (array[pos] != '{') {
            ++pos;
            continue;
        }
        const size_t end = json_value_end(array, pos);
        if (end == std::string::npos) {
            break;
        }
        objects.push_back(array.substr(pos, end - pos));
        pos = end;
    }
    return objects;
}

static void add_json_string_array_to_metadata(const std::string& object, const char* key,
                                              ModelInfo* model) {
    std::string array_value;
    if (!assignment_json_value(object, key, &array_value)) {
        return;
    }
    for (const std::string& item : json_top_level_objects(array_value)) {
        (void)item;
    }

    const std::string array = trim_copy(array_value);
    if (array.empty() || array.front() != '[') {
        return;
    }
    size_t pos = 1;
    while (pos < array.size()) {
        while (pos < array.size() &&
               (std::isspace(static_cast<unsigned char>(array[pos])) != 0 || array[pos] == ',')) {
            ++pos;
        }
        if (pos >= array.size() || array[pos] == ']') {
            break;
        }
        const size_t end = json_value_end(array, pos);
        if (end == std::string::npos) {
            break;
        }
        const std::string tag = json_unescape_string(array.substr(pos, end - pos));
        if (!tag.empty()) {
            model->mutable_metadata()->add_tags(tag);
        }
        pos = end;
    }
}

static bool parse_assignment_json_models(const char* data, size_t len,
                                         std::vector<ModelInfo>* out_models) {
    if (!out_models || !data || len == 0) {
        return false;
    }

    const std::string json(data, len);
    std::string models_array;
    const std::string trimmed = trim_copy(json);
    if (!trimmed.empty() && trimmed.front() == '[') {
        models_array = trimmed;
    } else if (!assignment_json_value(json, "models", &models_array)) {
        return false;
    }

    std::vector<std::string> objects = json_top_level_objects(models_array);
    out_models->clear();
    out_models->reserve(objects.size());
    for (const std::string& object : objects) {
        ModelInfo model;
        model.set_id(assignment_json_string_any(object, "id", "model_id", "modelId"));
        model.set_name(assignment_json_string_any(object, "name", "display_name", "displayName"));
        model.set_download_url(
            assignment_json_string_any(object, "download_url", "downloadUrl", "url"));
        model.set_description(assignment_json_string_any(object, "description"));
        model.set_download_size_bytes(assignment_json_int_any(object, 0, "download_size_bytes",
                                                              "download_size", "downloadSize"));
        model.set_context_length(static_cast<int32_t>(
            assignment_json_int_any(object, 0, "context_length", "contextLength")));
        model.set_supports_thinking(
            assignment_json_bool_any(object, false, "supports_thinking", "supportsThinking"));
        model.set_supports_lora(
            assignment_json_bool_any(object, false, "supports_lora", "supportsLora"));

        const std::string category = assignment_json_string_any(object, "category");
        if (!category.empty()) {
            model.set_category(category_from_assignment_token(category));
        }
        const std::string format = assignment_json_string_any(object, "format");
        if (!format.empty()) {
            model.set_format(format_from_assignment_token(format));
        }
        const std::string framework = assignment_json_string_any(object, "preferred_framework",
                                                                 "preferredFramework", "framework");
        if (!framework.empty()) {
            model.set_framework(framework_from_assignment_token(framework));
        }
        const int64_t memory = assignment_json_int_any(object, 0, "memory_required_bytes",
                                                       "memory_required", "memoryRequired");
        if (memory > 0) {
            model.set_memory_required_bytes(memory);
        }
        const std::string checksum =
            assignment_json_string_any(object, "checksum_sha256", "checksum", "sha256");
        if (!checksum.empty()) {
            model.set_checksum_sha256(checksum);
        }

        std::string metadata_object;
        if (assignment_json_value(object, "metadata", &metadata_object)) {
            const std::string metadata_description =
                assignment_json_string_any(metadata_object, "description");
            if (!metadata_description.empty()) {
                model.mutable_metadata()->set_description(metadata_description);
            }
            const std::string author = assignment_json_string_any(metadata_object, "author");
            if (!author.empty()) {
                model.mutable_metadata()->set_author(author);
            }
            const std::string license = assignment_json_string_any(metadata_object, "license");
            if (!license.empty()) {
                model.mutable_metadata()->set_license(license);
            }
            const std::string version = assignment_json_string_any(metadata_object, "version");
            if (!version.empty()) {
                model.mutable_metadata()->set_version(version);
            }
            add_json_string_array_to_metadata(metadata_object, "tags", &model);
        } else {
            add_json_string_array_to_metadata(object, "tags", &model);
        }

        normalize_assignment_model(&model);
        if (!model.id().empty()) {
            out_models->push_back(std::move(model));
        }
    }
    return true;
}

static rac_result_t parse_assignment_response_models(const char* data, size_t len,
                                                     std::vector<ModelInfo>* out_models,
                                                     std::string* error_message) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_models->clear();

    if (len == 0) {
        return RAC_SUCCESS;
    }
    if (!data) {
        if (error_message) {
            *error_message = "assignment response body is null";
        }
        return RAC_ERROR_INVALID_RESPONSE;
    }
    if (len > static_cast<size_t>(std::numeric_limits<int>::max())) {
        if (error_message) {
            *error_message = "assignment response body is too large";
        }
        return RAC_ERROR_INVALID_RESPONSE;
    }

    ModelRegistryRefreshResult refresh;
    if (refresh.ParseFromArray(data, static_cast<int>(len)) &&
        (refresh.success() || refresh.models().models_size() > 0 ||
         refresh.registered_count() > 0 || refresh.updated_count() > 0 ||
         refresh.warnings_size() > 0 || !refresh.error_message().empty())) {
        if (!refresh.success() && !refresh.error_message().empty()) {
            if (error_message) {
                *error_message = refresh.error_message();
            }
            return RAC_ERROR_INVALID_RESPONSE;
        }
        out_models->reserve(static_cast<size_t>(refresh.models().models_size()));
        for (const ModelInfo& model : refresh.models().models()) {
            ModelInfo copy(model);
            normalize_assignment_model(&copy);
            if (!copy.id().empty()) {
                out_models->push_back(std::move(copy));
            }
        }
        return RAC_SUCCESS;
    }

    ModelInfoList list;
    if (list.ParseFromArray(data, static_cast<int>(len)) && list.models_size() > 0) {
        out_models->reserve(static_cast<size_t>(list.models_size()));
        for (const ModelInfo& model : list.models()) {
            ModelInfo copy(model);
            normalize_assignment_model(&copy);
            if (!copy.id().empty()) {
                out_models->push_back(std::move(copy));
            }
        }
        return RAC_SUCCESS;
    }

    if (parse_assignment_json_models(data, len, out_models)) {
        return RAC_SUCCESS;
    }

    if (error_message) {
        *error_message = "failed to parse assignment response as ModelInfoList or JSON";
    }
    return RAC_ERROR_INVALID_FORMAT;
}

struct AssignmentCounts {
    int32_t total = 0;
    int32_t downloaded = 0;
    int32_t available = 0;
    int32_t errors = 0;
};

static AssignmentCounts count_assignment_models(const std::vector<ModelInfo>& models) {
    AssignmentCounts counts;
    counts.total = static_cast<int32_t>(models.size());
    for (const ModelInfo& model : models) {
        if (assignment_model_is_downloaded(model)) {
            ++counts.downloaded;
        }
        if (assignment_model_is_available(model)) {
            ++counts.available;
        }
        if (effective_assignment_status(model) == runanywhere::v1::MODEL_REGISTRY_STATUS_ERROR) {
            ++counts.errors;
        }
    }
    return counts;
}

static void populate_assignment_refresh_result(ModelRegistryRefreshResult* result,
                                               std::vector<ModelInfo> models, bool success,
                                               int32_t updated_count,
                                               const std::vector<std::string>& warnings,
                                               const std::string& error_message) {
    if (!result) {
        return;
    }
    for (ModelInfo& model : models) {
        normalize_assignment_model(&model);
    }
    const AssignmentCounts counts = count_assignment_models(models);
    result->set_success(success);
    result->set_registered_count(counts.total);
    result->set_updated_count(updated_count);
    result->set_discovered_count(0);
    result->set_pruned_count(0);
    result->set_refreshed_at_unix_ms(rac_get_current_time_ms());
    result->set_downloaded_count(counts.downloaded);
    result->set_available_count(counts.available);
    result->set_error_count(counts.errors);
    if (!error_message.empty()) {
        result->set_error_message(error_message);
    }
    for (const std::string& warning : warnings) {
        result->add_warnings(warning);
    }
    for (ModelInfo& model : models) {
        result->mutable_models()->add_models()->Swap(&model);
    }
}

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

rac_result_t rac_model_assignment_set_callbacks(const rac_assignment_callbacks_t* callbacks) {
    RAC_LOG_INFO(LOG_CAT, "rac_model_assignment_set_callbacks called");

    if (!callbacks) {
        RAC_LOG_ERROR(LOG_CAT, "callbacks is NULL");
        return RAC_ERROR_NULL_POINTER;
    }

    rac_bool_t should_auto_fetch = RAC_FALSE;

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_callbacks = *callbacks;
        should_auto_fetch = callbacks->auto_fetch;

        char msg[128];
        snprintf(msg, sizeof(msg), "Model assignment callbacks set (http_get=%p, auto_fetch=%d)",
                 (void*)callbacks->http_get, callbacks->auto_fetch);
        RAC_LOG_INFO(LOG_CAT, msg);
    }

    // Auto-fetch if requested (outside lock to avoid deadlock with fetch)
    if (should_auto_fetch == RAC_TRUE) {
        RAC_LOG_INFO(LOG_CAT, "Auto-fetching model assignments...");
        rac_model_info_t** models = nullptr;
        size_t count = 0;
        rac_result_t fetch_result = rac_model_assignment_fetch(RAC_FALSE, &models, &count);

        if (fetch_result == RAC_SUCCESS) {
            char msg[128];
            snprintf(msg, sizeof(msg), "Auto-fetch completed: %zu models", count);
            RAC_LOG_INFO(LOG_CAT, msg);
        } else {
            char msg[128];
            snprintf(msg, sizeof(msg), "Auto-fetch failed with code: %d", fetch_result);
            RAC_LOG_WARNING(LOG_CAT, msg);
        }

        // Free the returned models array (data is already cached internally)
        if (models) {
            rac_model_info_array_free(models, count);
        }
    } else {
        RAC_LOG_INFO(LOG_CAT, "Auto-fetch disabled, models will be fetched on demand");
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_assignment_fetch(rac_bool_t force_refresh, rac_model_info_t*** out_models,
                                        size_t* out_count) {
    RAC_LOG_INFO(LOG_CAT, ">>> rac_model_assignment_fetch called");

    std::lock_guard<std::mutex> lock(g_mutex);
    char msg[256];

    if (!out_models || !out_count) {
        RAC_LOG_ERROR(LOG_CAT, "out_models or out_count is NULL");
        return RAC_ERROR_NULL_POINTER;
    }

    snprintf(msg, sizeof(msg), "force_refresh=%d, cache_valid=%d, cached_count=%zu", force_refresh,
             is_cache_valid() ? 1 : 0, g_cached_models.size());
    RAC_LOG_INFO(LOG_CAT, msg);

    // Check cache first
    if (force_refresh == RAC_FALSE && is_cache_valid()) {
        snprintf(msg, sizeof(msg), "Returning cached model assignments (%zu models)",
                 g_cached_models.size());
        RAC_LOG_INFO(LOG_CAT, msg);
        return copy_models_to_output(g_cached_models, out_models, out_count);
    }

    // Need to fetch from backend
    if (!g_callbacks.http_get) {
        RAC_LOG_WARNING(LOG_CAT,
                        "HTTP callback not set - returning cached or empty assignment list");
        if (!g_cached_models.empty()) {
            return copy_models_to_output(g_cached_models, out_models, out_count);
        }
        *out_models = nullptr;
        *out_count = 0;
        return RAC_SUCCESS;
    }

    // Get endpoint path (no query params - backend uses JWT token for filtering)
    const char* endpoint = rac_endpoint_model_assignments();

    snprintf(msg, sizeof(msg), ">>> Making HTTP GET to: %s", endpoint);
    RAC_LOG_INFO(LOG_CAT, msg);

    // Make HTTP request
    RAC_LOG_INFO(LOG_CAT, ">>> Calling http_get callback...");
    rac_assignment_http_response_t response = {};
    rac_result_t result =
        g_callbacks.http_get(endpoint, RAC_TRUE, &response, g_callbacks.user_data);

    snprintf(msg, sizeof(msg),
             "<<< http_get returned: result=%d, response.result=%d, status=%d, body_len=%zu",
             result, response.result, response.status_code, response.response_length);
    RAC_LOG_INFO(LOG_CAT, msg);

    if (result != RAC_SUCCESS || response.result != RAC_SUCCESS) {
        snprintf(msg, sizeof(msg), "HTTP request failed: result=%d, response.result=%d, error=%s",
                 result, response.result,
                 response.error_message ? response.error_message : "unknown error");
        RAC_LOG_ERROR(LOG_CAT, msg);

        // Return cached data as fallback
        if (!g_cached_models.empty()) {
            RAC_LOG_INFO(LOG_CAT, "Using cached models as fallback");
            return copy_models_to_output(g_cached_models, out_models, out_count);
        }

        return result != RAC_SUCCESS ? result : response.result;
    }

    if (response.status_code != 200) {
        snprintf(msg, sizeof(msg), "HTTP %d: %s", response.status_code,
                 response.error_message ? response.error_message : "request failed");
        RAC_LOG_ERROR(LOG_CAT, msg);

        // Return cached data as fallback
        if (!g_cached_models.empty()) {
            RAC_LOG_INFO(LOG_CAT, "Using cached models as fallback");
            return copy_models_to_output(g_cached_models, out_models, out_count);
        }

        return RAC_ERROR_HTTP_REQUEST_FAILED;
    }

    // Parse response
    std::vector<rac_model_info_t*> models =
        parse_models_json(response.response_body, response.response_length);
    snprintf(msg, sizeof(msg), "Parsed %zu model assignments", models.size());
    RAC_LOG_INFO(LOG_CAT, msg);

    // Save to registry - but preserve local metadata (like framework) if backend has less info
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry) {
        for (auto* model : models) {
            // Check if model already exists in registry with more specific info
            rac_model_info_t* existing = nullptr;
            if (rac_model_registry_get(registry, model->id, &existing) == RAC_SUCCESS && existing) {
                // Preserve framework if existing has a known framework and new doesn't
                if (existing->framework != RAC_FRAMEWORK_UNKNOWN &&
                    model->framework == RAC_FRAMEWORK_UNKNOWN) {
                    model->framework = existing->framework;
                    RAC_LOG_DEBUG(LOG_CAT, "Preserved local framework for model: %s", model->id);
                }
                // Preserve format if existing has a known format and new doesn't
                if (!c_format_needs_inference(existing->format) &&
                    c_format_needs_inference(model->format)) {
                    model->format = existing->format;
                    RAC_LOG_DEBUG(LOG_CAT, "Preserved local format for model: %s", model->id);
                }
                // Preserve local_path if existing has one and new doesn't
                if (existing->local_path && !model->local_path) {
                    model->local_path = strdup(existing->local_path);
                }
                // Preserve artifact_info if existing has more specific type
                if (existing->artifact_info.kind != RAC_ARTIFACT_KIND_SINGLE_FILE &&
                    model->artifact_info.kind == RAC_ARTIFACT_KIND_SINGLE_FILE) {
                    model->artifact_info = existing->artifact_info;
                    // Note: This is a shallow copy — existing must stay alive until
                    // after rac_model_registry_save deep-copies the data.
                }
                rac_model_registry_save(registry, model);
                rac_model_info_free(existing);
            } else {
                rac_model_registry_save(registry, model);
            }
        }
        RAC_LOG_DEBUG(LOG_CAT, "Saved models to registry");
    }

    // Update cache
    clear_cache_internal();
    for (auto* model : models) {
        g_cached_models.push_back(rac_model_info_copy(model));
    }
#ifdef RAC_HAVE_PROTOBUF
    rebuild_cached_proto_bytes_from_registry_locked();
#endif
    g_last_fetch_time = std::chrono::steady_clock::now();
    g_cache_valid = true;

    // Copy to output (models vector will be freed, so we use cached copies)
    result = copy_models_to_output(g_cached_models, out_models, out_count);

    // Cleanup temporary models
    for (auto* model : models) {
        rac_model_info_free(model);
    }

    snprintf(msg, sizeof(msg), "Successfully fetched %zu model assignments", *out_count);
    RAC_LOG_INFO(LOG_CAT, msg);

    return result;
}

rac_result_t rac_model_assignment_refresh_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    ModelRegistryRefreshRequest request;
    rac_result_t parse_rc = parse_assignment_refresh_request(
        request_proto_bytes, request_proto_size, &request, out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    std::lock_guard<std::mutex> lock(g_mutex);

    std::vector<std::string> warnings;
    std::vector<ModelInfo> models;
    std::string error_message;
    int32_t updated_count = 0;
    bool success = true;

    const bool include_remote = request.include_remote_catalog();
    const bool force_refresh = request.force_refresh();

    if (!include_remote) {
        models = cached_proto_models_locked();
        if (!request.catalog_uri().empty()) {
            warnings.emplace_back("catalog_uri ignored because include_remote_catalog is false");
        }
        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models),
                                           /*success=*/true,
                                           /*updated_count=*/0, warnings, "");
        return serialize_assignment_proto(result, out_result);
    }

    if (!force_refresh && is_cache_valid()) {
        models = cached_proto_models_locked();
        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models),
                                           /*success=*/true,
                                           /*updated_count=*/0, warnings, "");
        return serialize_assignment_proto(result, out_result);
    }

    if (!g_callbacks.http_get) {
        warnings.emplace_back(
            "model assignment transport is not configured; remote catalog was not fetched");
        models = cached_proto_models_locked();
        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models),
                                           /*success=*/true,
                                           /*updated_count=*/0, warnings, "");
        return serialize_assignment_proto(result, out_result);
    }

    const std::string catalog_uri = request.catalog_uri();
    const char* endpoint =
        catalog_uri.empty() ? rac_endpoint_model_assignments() : catalog_uri.c_str();

    rac_assignment_http_response_t response = {};
    rac_result_t transport_rc =
        g_callbacks.http_get(endpoint, RAC_TRUE, &response, g_callbacks.user_data);

    if (transport_rc != RAC_SUCCESS || response.result != RAC_SUCCESS) {
        const rac_result_t error_code =
            transport_rc != RAC_SUCCESS ? transport_rc : response.result;
        error_message = response.error_message && response.error_message[0] != '\0'
                            ? response.error_message
                            : rac_error_message(error_code);
        if (!g_cached_models.empty() || !g_cached_model_proto_bytes.empty()) {
            warnings.emplace_back("remote assignment refresh failed; returning cached assignments");
            warnings.push_back(error_message);
            models = cached_proto_models_locked();
            error_message.clear();
            success = true;
        } else {
            success = false;
        }

        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models), success,
                                           /*updated_count=*/0, warnings, error_message);
        return serialize_assignment_proto(result, out_result);
    }

    if (response.status_code < 200 || response.status_code >= 300) {
        std::ostringstream oss;
        oss << "assignment refresh HTTP " << response.status_code;
        if (response.error_message && response.error_message[0] != '\0') {
            oss << ": " << response.error_message;
        }
        error_message = oss.str();
        if (!g_cached_models.empty() || !g_cached_model_proto_bytes.empty()) {
            warnings.emplace_back("remote assignment refresh returned HTTP error; returning cache");
            warnings.push_back(error_message);
            models = cached_proto_models_locked();
            error_message.clear();
            success = true;
        } else {
            success = false;
        }

        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models), success,
                                           /*updated_count=*/0, warnings, error_message);
        return serialize_assignment_proto(result, out_result);
    }

    rac_result_t parse_models_rc = parse_assignment_response_models(
        response.response_body, response.response_length, &models, &error_message);
    if (parse_models_rc != RAC_SUCCESS) {
        if (!g_cached_models.empty() || !g_cached_model_proto_bytes.empty()) {
            warnings.emplace_back("remote assignment response was invalid; returning cache");
            warnings.push_back(error_message);
            models = cached_proto_models_locked();
            error_message.clear();
            success = true;
        } else {
            success = false;
        }

        ModelRegistryRefreshResult result;
        populate_assignment_refresh_result(&result, std::move(models), success,
                                           /*updated_count=*/0, warnings, error_message);
        return serialize_assignment_proto(result, out_result);
    }

    rac_result_t cache_rc = update_assignment_cache_from_proto_locked(models, &updated_count);
    if (cache_rc != RAC_SUCCESS) {
        return assignment_proto_error(out_result, cache_rc,
                                      "failed to update model assignment cache");
    }

    models = cached_proto_models_locked();
    ModelRegistryRefreshResult result;
    populate_assignment_refresh_result(&result, std::move(models),
                                       /*success=*/true, updated_count, warnings, "");
    return serialize_assignment_proto(result, out_result);
#endif
}

rac_result_t rac_model_assignment_get_by_framework(rac_inference_framework_t framework,
                                                   rac_model_info_t*** out_models,
                                                   size_t* out_count) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!out_models || !out_count)
        return RAC_ERROR_NULL_POINTER;

    std::vector<rac_model_info_t*> filtered;
    for (auto* model : g_cached_models) {
        if (model->framework == framework) {
            filtered.push_back(model);
        }
    }

    return copy_models_to_output(filtered, out_models, out_count);
}

rac_result_t rac_model_assignment_get_by_category(rac_model_category_t category,
                                                  rac_model_info_t*** out_models,
                                                  size_t* out_count) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!out_models || !out_count)
        return RAC_ERROR_NULL_POINTER;

    std::vector<rac_model_info_t*> filtered;
    for (auto* model : g_cached_models) {
        if (model->category == category) {
            filtered.push_back(model);
        }
    }

    return copy_models_to_output(filtered, out_models, out_count);
}

void rac_model_assignment_clear_cache(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_cache_internal();
    RAC_LOG_DEBUG(LOG_CAT, "Model assignment cache cleared");
}

void rac_model_assignment_set_cache_timeout(uint32_t timeout_seconds) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_cache_timeout_seconds = timeout_seconds;
    char msg[64];
    snprintf(msg, sizeof(msg), "Cache timeout set to %u seconds", timeout_seconds);
    RAC_LOG_DEBUG(LOG_CAT, msg);
}
