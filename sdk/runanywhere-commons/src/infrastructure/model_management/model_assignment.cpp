/**
 * @file model_assignment.cpp
 * @brief Model Assignment Manager Implementation
 */

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/network/rac_endpoints.h"

// Simple JSON parsing (we don't want heavy dependencies)
#include <sstream>
#include <string>

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

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static void clear_cache_internal() {
    for (auto* model : g_cached_models) {
        rac_model_info_free(model);
    }
    g_cached_models.clear();
    g_cache_valid = false;
}

static bool is_cache_valid() {
    if (!g_cache_valid)
        return false;

    auto now = std::chrono::steady_clock::now();
    auto elapsed =
        std::chrono::duration_cast<std::chrono::seconds>(now - g_last_fetch_time).count();
    return elapsed < g_cache_timeout_seconds;
}

// Simple JSON string extraction (finds "key": "value" or "key": number)
static std::string json_get_string(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    size_t pos = json.find(search);
    if (pos == std::string::npos)
        return "";

    pos = json.find(":", pos);
    if (pos == std::string::npos)
        return "";

    // Skip whitespace
    pos++;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t'))
        pos++;

    if (pos >= json.size())
        return "";

    // Check for string value
    if (json[pos] == '"') {
        size_t start = pos + 1;
        size_t end = json.find('"', start);
        if (end == std::string::npos)
            return "";
        return json.substr(start, end - start);
    }

    // Check for null
    if (json.substr(pos, 4) == "null")
        return "";

    // Number or boolean
    size_t end = json.find_first_of(",}]", pos);
    if (end == std::string::npos)
        return "";
    std::string val = json.substr(pos, end - pos);
    // Trim whitespace
    while (!val.empty() && (val.back() == ' ' || val.back() == '\t' || val.back() == '\n')) {
        val.pop_back();
    }
    return val;
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

// Parse models array from JSON response
static std::vector<rac_model_info_t*> parse_models_json(const char* json_str, size_t len) {
    std::vector<rac_model_info_t*> models;
    if (!json_str || len == 0)
        return models;

    std::string json(json_str, len);

    // Find "models" array
    size_t models_pos = json.find("\"models\"");
    if (models_pos == std::string::npos) {
        RAC_LOG_WARNING(LOG_CAT, "No 'models' array in response");
        return models;
    }

    // Find array start
    size_t arr_start = json.find('[', models_pos);
    if (arr_start == std::string::npos)
        return models;

    // Find each object in array
    size_t pos = arr_start + 1;
    while (pos < json.size()) {
        // Find next object start
        size_t obj_start = json.find('{', pos);
        if (obj_start == std::string::npos)
            break;

        // Find matching close brace (simple approach, may fail on nested objects)
        int depth = 1;
        size_t obj_end = obj_start + 1;
        while (obj_end < json.size() && depth > 0) {
            if (json[obj_end] == '{')
                depth++;
            else if (json[obj_end] == '}')
                depth--;
            obj_end++;
        }

        if (depth != 0)
            break;

        std::string obj = json.substr(obj_start, obj_end - obj_start);

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
        else if (format == "onnx")
            model->format = RAC_MODEL_FORMAT_ONNX;
        else if (format == "ort")
            model->format = RAC_MODEL_FORMAT_ORT;
        else if (format == "bin")
            model->format = RAC_MODEL_FORMAT_BIN;
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
            free(*out_models);
            *out_models = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    return RAC_SUCCESS;
}

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

rac_result_t rac_model_assignment_set_callbacks(const rac_assignment_callbacks_t* callbacks) {
    if (!callbacks)
        return RAC_ERROR_NULL_POINTER;

    rac_bool_t should_auto_fetch = RAC_FALSE;

    {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_callbacks = *callbacks;
        should_auto_fetch = callbacks->auto_fetch;
        RAC_LOG_DEBUG(LOG_CAT, "Model assignment callbacks set");
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
            RAC_LOG_WARNING(LOG_CAT, "Auto-fetch failed (non-fatal, models can be fetched later)");
        }

        // Free the returned models array (data is already cached internally)
        if (models) {
            rac_model_info_array_free(models, count);
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_assignment_fetch(rac_bool_t force_refresh, rac_model_info_t*** out_models,
                                        size_t* out_count) {
    std::lock_guard<std::mutex> lock(g_mutex);
    char msg[256];

    if (!out_models || !out_count)
        return RAC_ERROR_NULL_POINTER;

    // Check cache first
    if (!force_refresh && is_cache_valid()) {
        snprintf(msg, sizeof(msg), "Returning cached model assignments (%zu models)",
                 g_cached_models.size());
        RAC_LOG_DEBUG(LOG_CAT, msg);
        return copy_models_to_output(g_cached_models, out_models, out_count);
    }

    // Need to fetch from backend
    if (!g_callbacks.http_get || !g_callbacks.get_device_info) {
        RAC_LOG_ERROR(LOG_CAT, "Callbacks not set");
        return RAC_ERROR_INVALID_STATE;
    }

    // Get device info
    rac_assignment_device_info_t device_info = {};
    g_callbacks.get_device_info(&device_info, g_callbacks.user_data);

    // Get endpoint path
    const char* endpoint = rac_endpoint_model_assignments();

    snprintf(msg, sizeof(msg), "Fetching model assignments from: %s", endpoint);
    RAC_LOG_INFO(LOG_CAT, msg);

    // Make HTTP request
    rac_assignment_http_response_t response = {};
    rac_result_t result =
        g_callbacks.http_get(endpoint, RAC_TRUE, &response, g_callbacks.user_data);

    if (result != RAC_SUCCESS || response.result != RAC_SUCCESS) {
        snprintf(msg, sizeof(msg), "HTTP request failed: %s",
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

    // Save to registry
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry) {
        for (auto* model : models) {
            rac_model_registry_save(registry, model);
        }
        RAC_LOG_DEBUG(LOG_CAT, "Saved models to registry");
    }

    // Update cache
    clear_cache_internal();
    for (auto* model : models) {
        g_cached_models.push_back(rac_model_info_copy(model));
    }
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
