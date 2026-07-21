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
#include <nlohmann/json.hpp>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

using json = nlohmann::json;

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

// ---------------------------------------------------------------------------
// nlohmann/json field accessors. Mirror the lenient behaviour of the former
// hand-rolled getters: return the first present, non-null key (numbers coerced
// to their text form) and fall back to the default for absent / null /
// wrong-type values. Parsing is strict — json::parse(..., allow_exceptions=
// false) rejects a malformed body; the proto fetch path tries the binary
// ModelInfoList / RefreshResult decoders before this JSON fallback runs.
// ---------------------------------------------------------------------------
static std::string json_first_string(const json& obj, std::initializer_list<const char*> keys) {
    for (const char* key : keys) {
        const auto it = obj.find(key);
        if (it == obj.end() || it->is_null())
            continue;
        if (it->is_string())
            return it->get<std::string>();
        if (it->is_number_integer())
            return std::to_string(it->get<int64_t>());
        if (it->is_number_unsigned())
            return std::to_string(it->get<uint64_t>());
        if (it->is_number_float())
            return std::to_string(it->get<double>());
        if (it->is_boolean())
            return it->get<bool>() ? "true" : "false";
    }
    return std::string();
}

static int64_t json_first_int(const json& obj, int64_t default_value,
                              std::initializer_list<const char*> keys) {
    for (const char* key : keys) {
        const auto it = obj.find(key);
        if (it == obj.end() || it->is_null())
            continue;
        if (it->is_number_integer() || it->is_number_unsigned())
            return it->get<int64_t>();
        if (it->is_number_float())
            return static_cast<int64_t>(it->get<double>());
        if (it->is_string()) {
            const std::string text = it->get<std::string>();
            char* end = nullptr;
            const long long parsed = std::strtoll(text.c_str(), &end, 10);
            if (end != text.c_str() && end != nullptr && *end == '\0')
                return static_cast<int64_t>(parsed);
        }
    }
    return default_value;
}

static bool json_first_bool(const json& obj, bool default_value,
                            std::initializer_list<const char*> keys) {
    for (const char* key : keys) {
        const auto it = obj.find(key);
        if (it == obj.end() || it->is_null())
            continue;
        if (it->is_boolean())
            return it->get<bool>();
        if (it->is_number_integer())
            return it->get<int64_t>() != 0;
        if (it->is_string()) {
            const std::string text = it->get<std::string>();
            return text == "true" || text == "1";
        }
    }
    return default_value;
}

// Parse a backend model-list JSON response into C-ABI model structs.
static std::vector<rac_model_info_t*> parse_models_json(const char* json_str, size_t len) {
    std::vector<rac_model_info_t*> models;
    if (!json_str || len == 0)
        return models;

    const json root = json::parse(std::string(json_str, len), nullptr, false);
    if (root.is_discarded() || !root.is_object())
        return models;
    const auto models_it = root.find("models");
    if (models_it == root.end() || !models_it->is_array()) {
        RAC_LOG_WARNING(LOG_CAT, "No 'models' array in response");
        return models;
    }

    for (const json& obj : *models_it) {
        if (!obj.is_object())
            continue;
        const std::string id = json_first_string(obj, {"id"});
        if (id.empty())
            continue;
        const std::string name = json_first_string(obj, {"name"});
        const std::string category = json_first_string(obj, {"category"});
        const std::string format = json_first_string(obj, {"format"});
        const std::string framework = json_first_string(obj, {"preferred_framework"});
        const std::string download_url = json_first_string(obj, {"download_url"});
        const std::string description = json_first_string(obj, {"description"});
        const int64_t size = json_first_int(obj, 0, {"size"});
        const int context_length = static_cast<int>(json_first_int(obj, 0, {"context_length"}));
        const bool supports_thinking = json_first_bool(obj, false, {"supports_thinking"});

        rac_model_info_t* model = rac_model_info_alloc();
        if (!model)
            continue;
        model->id = strdup(id.c_str());
        model->name = strdup(name.c_str());
        if (!model->id || !model->name) {
            rac_model_info_free(model);
            continue;
        }
        model->download_url = download_url.empty() ? nullptr : strdup(download_url.c_str());
        model->description = description.empty() ? nullptr : strdup(description.c_str());
        model->download_size = size;
        model->context_length = context_length;
        model->supports_thinking = supports_thinking ? RAC_TRUE : RAC_FALSE;
        model->source = RAC_MODEL_SOURCE_REMOTE;

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
        else if (category == "speaker-diarization" || category == "diarization")
            model->category = RAC_MODEL_CATEGORY_SPEAKER_DIARIZATION;
        else if (category == "semantic-segmentation" || category == "segmentation")
            model->category = RAC_MODEL_CATEGORY_SEMANTIC_SEGMENTATION;
        else if (category == "vocoder" || category == "vocode")
            model->category = RAC_MODEL_CATEGORY_VOCODER;
        else if (category == "multimodal")
            model->category = RAC_MODEL_CATEGORY_MULTIMODAL;
        else
            model->category = RAC_MODEL_CATEGORY_LANGUAGE;

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
        else if (framework == "qhexrt" || framework == "qhx" || framework == "qnn")
            model->framework = RAC_FRAMEWORK_QHEXRT;
        else if (framework == "sherpa" || framework == "sherpa_onnx" || framework == "sherpa-onnx")
            model->framework = RAC_FRAMEWORK_SHERPA;
        else
            model->framework = RAC_FRAMEWORK_UNKNOWN;

        models.push_back(model);
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

// =============================================================================
// DEFAULT HTTP TRANSPORT
// =============================================================================
// Used when the SDK did not register rac_assignment_callbacks_t.http_get but a
// platform rac_http_transport_ops_t vtable is available. Explicit callbacks
// always keep precedence (see assignment_http_get_locked).

// Backing storage for the response handed back through
// rac_assignment_http_response_t. Both public call sites hold g_mutex for the
// whole fetch-and-parse sequence, so a single file-static slot is race-free.
static std::string g_default_http_body;
static std::string g_default_http_error;

static rac_result_t assignment_default_http_failure(rac_assignment_http_response_t* out_response,
                                                    rac_result_t code, const char* message) {
    g_default_http_error =
        (message != nullptr && message[0] != '\0') ? message : rac_error_message(code);
    out_response->result = code;
    out_response->error_message = g_default_http_error.c_str();
    return code;
}

// Routes the assignment fetch through the registered HTTP transport, mirroring
// the phase2 control-plane pattern in sdk_init.cpp (default headers +
// X-Platform + apikey) plus the bearer token the per-SDK callbacks attach on
// the requires_auth path.
static rac_result_t assignment_default_http_get(const char* endpoint, rac_bool_t requires_auth,
                                                rac_assignment_http_response_t* out_response) {
    if (!endpoint || !out_response) {
        return RAC_ERROR_NULL_POINTER;
    }
    std::memset(out_response, 0, sizeof(*out_response));

    const char* base_url = rac_state_get_base_url();
    if (!base_url || base_url[0] == '\0') {
        return assignment_default_http_failure(out_response, RAC_ERROR_INVALID_CONFIGURATION,
                                               "model assignment base URL is not configured");
    }

    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        return assignment_default_http_failure(out_response, RAC_ERROR_INVALID_CONFIGURATION,
                                               "failed to build model assignment URL");
    }

    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    std::vector<rac_http_header_kv_t> headers;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS && defaults != nullptr) {
        headers.assign(defaults, defaults + default_count);
    }
    const rac_sdk_config_t* config = rac_sdk_get_config();
    const char* platform =
        (config != nullptr && config->platform != nullptr && config->platform[0] != '\0')
            ? config->platform
            : "unknown";
    headers.push_back({"X-Platform", platform});
    const char* api_key = rac_state_get_api_key();
    if (api_key != nullptr && api_key[0] != '\0') {
        headers.push_back({"apikey", api_key});
    }
    std::string bearer;
    if (requires_auth == RAC_TRUE) {
        const char* token = rac_auth_get_access_token();
        if (token != nullptr && token[0] != '\0') {
            bearer = std::string("Bearer ") + token;
            headers.push_back({"Authorization", bearer.c_str()});
        }
    }

    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS) {
        return assignment_default_http_failure(out_response, rc, nullptr);
    }

    rac_http_request_t request = {};
    request.method = "GET";
    request.url = url;
    request.headers = headers.empty() ? nullptr : headers.data();
    request.header_count = headers.size();
    request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
    // Assignment fetches carry apikey and bearer credentials. The configured
    // control-plane origin must answer directly; redirects fail closed.
    request.follow_redirects = RAC_FALSE;

    rac_http_response_t response = {};
    rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);
    if (rc != RAC_SUCCESS) {
        rac_http_response_free(&response);
        return assignment_default_http_failure(out_response, rc, nullptr);
    }

    if (response.body_bytes != nullptr && response.body_len > 0) {
        g_default_http_body.assign(reinterpret_cast<const char*>(response.body_bytes),
                                   response.body_len);
    } else {
        g_default_http_body.clear();
    }
    out_response->result = RAC_SUCCESS;
    out_response->status_code = response.status;
    out_response->response_body = g_default_http_body.c_str();
    out_response->response_length = g_default_http_body.size();
    rac_http_response_free(&response);
    return RAC_SUCCESS;
}

// True when an assignment fetch can reach the backend: either via an explicit
// per-SDK callback or via the built-in transport-backed default.
static bool assignment_transport_available_locked() {
    return g_callbacks.http_get != nullptr || rac_http_transport_is_registered() == RAC_TRUE;
}

static rac_result_t assignment_http_get_locked(const char* endpoint, rac_bool_t requires_auth,
                                               rac_assignment_http_response_t* out_response) {
    if (g_callbacks.http_get != nullptr) {
        return g_callbacks.http_get(endpoint, requires_auth, out_response, g_callbacks.user_data);
    }
    return assignment_default_http_get(endpoint, requires_auth, out_response);
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
            return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
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
        case runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT:
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
        case RAC_FRAMEWORK_QHEXRT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
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
            case 10:
                return runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION;
            case 11:
                return runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION;
            case 12:
                return runanywhere::v1::MODEL_CATEGORY_VOCODER;
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
    if (lower == "diarization" || lower == "speaker_diarization" ||
        lower == "speaker-diarization") {
        return runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION;
    }
    if (lower == "segmentation" || lower == "semantic_segmentation" ||
        lower == "semantic-segmentation") {
        return runanywhere::v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION;
    }
    if (lower == "vocoder" || lower == "vocode") {
        return runanywhere::v1::MODEL_CATEGORY_VOCODER;
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
            // Value 9 and values 10-11 retired — fall through to UNKNOWN.
            case 12:
                return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
            case 13:
                return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
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
    if (lower == "qhexrt" || lower == "qhx" || lower == "qnn") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
    }
    if (lower == "sherpa" || lower == "sherpa_onnx" || lower == "sherpa-onnx") {
        return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
    }
    if (lower == "tflite")
        return runanywhere::v1::INFERENCE_FRAMEWORK_TFLITE;
    return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
}

// Parse a backend assignment JSON response into proto ModelInfo messages.
// Accepts either a top-level array or a {"models": [...]} envelope.
static bool parse_assignment_json_models(const char* data, size_t len,
                                         std::vector<ModelInfo>* out_models) {
    if (!out_models || !data || len == 0)
        return false;

    const json root = json::parse(std::string(data, len), nullptr, false);
    if (root.is_discarded())
        return false;
    const json* array = nullptr;
    if (root.is_array()) {
        array = &root;
    } else if (root.is_object()) {
        const auto it = root.find("models");
        if (it != root.end() && it->is_array())
            array = &*it;
    }
    if (array == nullptr)
        return false;

    out_models->clear();
    out_models->reserve(array->size());
    for (const json& object : *array) {
        if (!object.is_object())
            continue;
        ModelInfo model;
        model.set_id(json_first_string(object, {"id", "model_id", "modelId"}));
        model.set_name(json_first_string(object, {"name", "display_name", "displayName"}));
        model.set_download_url(json_first_string(object, {"download_url", "downloadUrl", "url"}));
        const std::string top_level_description = json_first_string(object, {"description"});
        if (!top_level_description.empty()) {
            model.mutable_metadata()->set_description(top_level_description);
        }
        model.set_download_size_bytes(
            json_first_int(object, 0, {"download_size_bytes", "download_size", "downloadSize"}));
        model.set_context_length(
            static_cast<int32_t>(json_first_int(object, 0, {"context_length", "contextLength"})));
        model.set_supports_thinking(
            json_first_bool(object, false, {"supports_thinking", "supportsThinking"}));
        model.set_supports_lora(json_first_bool(object, false, {"supports_lora", "supportsLora"}));

        const std::string category = json_first_string(object, {"category"});
        if (!category.empty())
            model.set_category(category_from_assignment_token(category));
        const std::string format = json_first_string(object, {"format"});
        if (!format.empty())
            model.set_format(format_from_assignment_token(format));
        const std::string framework =
            json_first_string(object, {"preferred_framework", "preferredFramework", "framework"});
        if (!framework.empty())
            model.set_framework(framework_from_assignment_token(framework));

        const int64_t memory = json_first_int(
            object, 0, {"memory_required_bytes", "memory_required", "memoryRequired"});
        if (memory > 0)
            model.set_memory_required_bytes(memory);
        const std::string checksum =
            json_first_string(object, {"checksum_sha256", "checksum", "sha256"});
        if (!checksum.empty())
            model.set_checksum_sha256(checksum);

        const auto metadata_it = object.find("metadata");
        const bool has_metadata = metadata_it != object.end() && metadata_it->is_object();
        const json& tag_source = has_metadata ? *metadata_it : object;
        if (has_metadata) {
            const std::string desc = json_first_string(*metadata_it, {"description"});
            if (!desc.empty())
                model.mutable_metadata()->set_description(desc);
            const std::string author = json_first_string(*metadata_it, {"author"});
            if (!author.empty())
                model.mutable_metadata()->set_author(author);
            const std::string license = json_first_string(*metadata_it, {"license"});
            if (!license.empty())
                model.mutable_metadata()->set_license(license);
            const std::string version = json_first_string(*metadata_it, {"version"});
            if (!version.empty())
                model.mutable_metadata()->set_version(version);
        }
        const auto tags_it = tag_source.find("tags");
        if (tags_it != tag_source.end() && tags_it->is_array()) {
            for (const json& tag : *tags_it) {
                if (!tag.is_string())
                    continue;
                const std::string tag_value = tag.get<std::string>();
                if (!tag_value.empty())
                    model.mutable_metadata()->add_tags(tag_value);
            }
        }

        normalize_assignment_model(&model);
        if (!model.id().empty())
            out_models->push_back(std::move(model));
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
    if (!assignment_transport_available_locked()) {
        RAC_LOG_WARNING(
            LOG_CAT,
            "No assignment callback or HTTP transport - returning cached or empty assignment list");
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
    rac_assignment_http_response_t response = {};
    rac_result_t result = assignment_http_get_locked(endpoint, RAC_TRUE, &response);

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
                    // Transfer ownership of the heap members to `model` and null
                    // them on `existing`: `model` outlives this block (copied into
                    // the cache, freed at the end of the fetch), so a shallow
                    // alias here + rac_model_info_free(existing) below left
                    // dangling pointers that were re-freed later — use-after-free
                    // crash (bionic tagged-pointer SIGABRT) on second launch.
                    model->artifact_info = existing->artifact_info;
                    existing->artifact_info.expected_files = nullptr;
                    existing->artifact_info.file_descriptors = nullptr;
                    existing->artifact_info.file_descriptor_count = 0;
                    existing->artifact_info.strategy_id = nullptr;
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

    if (!assignment_transport_available_locked()) {
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
    rac_result_t transport_rc = assignment_http_get_locked(endpoint, RAC_TRUE, &response);

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
