/**
 * @file diffusion_json.cpp
 * @brief JSON convenience helpers for diffusion component
 *
 * Provides JSON parsing and serialization wrappers over the typed C API.
 */

#include "rac/features/diffusion/rac_diffusion_component.h"

#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

static const char* skip_ws(const char* p) {
    if (!p) return nullptr;
    while (*p && std::isspace(static_cast<unsigned char>(*p))) {
        ++p;
    }
    return p;
}

static const char* find_key(const char* json, const char* key) {
    if (!json || !key) return nullptr;
    std::string needle = "\"";
    needle += key;
    needle += "\"";
    const char* pos = std::strstr(json, needle.c_str());
    if (!pos) return nullptr;
    pos += needle.size();
    while (*pos && *pos != ':') {
        ++pos;
    }
    if (*pos != ':') return nullptr;
    pos = skip_ws(pos + 1);
    return pos;
}

static bool json_read_string(const char* json, const char* key, std::string* out) {
    if (!out) return false;
    const char* p = find_key(json, key);
    if (!p || *p != '"') return false;
    ++p;
    std::string result;
    while (*p) {
        if (*p == '\\') {
            ++p;
            if (!*p) break;
            switch (*p) {
                case '"': result.push_back('"'); break;
                case '\\': result.push_back('\\'); break;
                case 'n': result.push_back('\n'); break;
                case 'r': result.push_back('\r'); break;
                case 't': result.push_back('\t'); break;
                case 'b': result.push_back('\b'); break;
                case 'f': result.push_back('\f'); break;
                default: result.push_back(*p); break;
            }
            ++p;
            continue;
        }
        if (*p == '"') {
            *out = result;
            return true;
        }
        result.push_back(*p++);
    }
    return false;
}

static bool json_read_bool(const char* json, const char* key, bool* out) {
    if (!out) return false;
    const char* p = find_key(json, key);
    if (!p) return false;
    if (std::strncmp(p, "true", 4) == 0) {
        *out = true;
        return true;
    }
    if (std::strncmp(p, "false", 5) == 0) {
        *out = false;
        return true;
    }
    return false;
}

static bool json_read_number(const char* json, const char* key, double* out) {
    if (!out) return false;
    const char* p = find_key(json, key);
    if (!p) return false;
    char* end = nullptr;
    double val = std::strtod(p, &end);
    if (end == p) return false;
    *out = val;
    return true;
}

static bool json_read_int64(const char* json, const char* key, int64_t* out) {
    if (!out) return false;
    const char* p = find_key(json, key);
    if (!p) return false;
    char* end = nullptr;
    long long val = std::strtoll(p, &end, 10);
    if (end == p) return false;
    *out = static_cast<int64_t>(val);
    return true;
}

static rac_diffusion_scheduler_t parse_scheduler(const char* json,
                                                 rac_diffusion_scheduler_t fallback) {
    double num = 0.0;
    if (json_read_number(json, "scheduler", &num)) {
        return static_cast<rac_diffusion_scheduler_t>(static_cast<int>(num));
    }

    std::string val;
    if (!json_read_string(json, "scheduler", &val)) {
        return fallback;
    }

    if (val == "dpm++_2m_karras") return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS;
    if (val == "dpm++_2m") return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M;
    if (val == "dpm++_2m_sde") return RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_SDE;
    if (val == "ddim") return RAC_DIFFUSION_SCHEDULER_DDIM;
    if (val == "euler") return RAC_DIFFUSION_SCHEDULER_EULER;
    if (val == "euler_a") return RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL;
    if (val == "pndm") return RAC_DIFFUSION_SCHEDULER_PNDM;
    if (val == "lms") return RAC_DIFFUSION_SCHEDULER_LMS;
    return fallback;
}

static rac_diffusion_mode_t parse_mode(const char* json, rac_diffusion_mode_t fallback) {
    double num = 0.0;
    if (json_read_number(json, "mode", &num)) {
        return static_cast<rac_diffusion_mode_t>(static_cast<int>(num));
    }

    std::string val;
    if (!json_read_string(json, "mode", &val)) {
        return fallback;
    }

    if (val == "txt2img") return RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;
    if (val == "img2img") return RAC_DIFFUSION_MODE_IMAGE_TO_IMAGE;
    if (val == "inpainting") return RAC_DIFFUSION_MODE_INPAINTING;
    return fallback;
}

static rac_diffusion_model_variant_t parse_variant(const char* json,
                                                   rac_diffusion_model_variant_t fallback) {
    double num = 0.0;
    if (json_read_number(json, "model_variant", &num)) {
        return static_cast<rac_diffusion_model_variant_t>(static_cast<int>(num));
    }

    std::string val;
    if (!json_read_string(json, "model_variant", &val)) {
        return fallback;
    }

    if (val == "sd15") return RAC_DIFFUSION_MODEL_SD_1_5;
    if (val == "sd21") return RAC_DIFFUSION_MODEL_SD_2_1;
    if (val == "sdxl") return RAC_DIFFUSION_MODEL_SDXL;
    if (val == "sdxl_turbo") return RAC_DIFFUSION_MODEL_SDXL_TURBO;
    if (val == "sdxs") return RAC_DIFFUSION_MODEL_SDXS;
    if (val == "lcm") return RAC_DIFFUSION_MODEL_LCM;
    return fallback;
}

static rac_diffusion_tokenizer_source_t parse_tokenizer_source(
    const char* json, rac_diffusion_tokenizer_source_t fallback) {
    double num = 0.0;
    if (json_read_number(json, "tokenizer_source", &num)) {
        return static_cast<rac_diffusion_tokenizer_source_t>(static_cast<int>(num));
    }

    std::string val;
    if (!json_read_string(json, "tokenizer_source", &val)) {
        return fallback;
    }

    if (val == "sd15") return RAC_DIFFUSION_TOKENIZER_SD_1_5;
    if (val == "sd2") return RAC_DIFFUSION_TOKENIZER_SD_2_X;
    if (val == "sdxl") return RAC_DIFFUSION_TOKENIZER_SDXL;
    if (val == "custom") return RAC_DIFFUSION_TOKENIZER_CUSTOM;
    return fallback;
}

static rac_inference_framework_t parse_preferred_framework(
    const char* json, rac_inference_framework_t fallback) {
    double num = 0.0;
    if (json_read_number(json, "preferred_framework", &num)) {
        return static_cast<rac_inference_framework_t>(static_cast<int>(num));
    }

    std::string val;
    if (!json_read_string(json, "preferred_framework", &val)) {
        return fallback;
    }

    for (auto& c : val) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }

    if (val == "onnx") return RAC_FRAMEWORK_ONNX;
    if (val == "llamacpp" || val == "llama_cpp") return RAC_FRAMEWORK_LLAMACPP;
    if (val == "foundationmodels" || val == "foundation_models")
        return RAC_FRAMEWORK_FOUNDATION_MODELS;
    if (val == "systemtts" || val == "system_tts") return RAC_FRAMEWORK_SYSTEM_TTS;
    if (val == "fluidaudio" || val == "fluid_audio") return RAC_FRAMEWORK_FLUID_AUDIO;
    if (val == "builtin" || val == "built_in") return RAC_FRAMEWORK_BUILTIN;
    if (val == "none") return RAC_FRAMEWORK_NONE;
    if (val == "mlx") return RAC_FRAMEWORK_MLX;
    if (val == "coreml" || val == "core_ml") return RAC_FRAMEWORK_COREML;
    if (val == "unknown") return RAC_FRAMEWORK_UNKNOWN;

    return fallback;
}

static std::string base64_encode(const uint8_t* data, size_t len) {
    static const char table[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    std::string out;
    out.reserve(((len + 2) / 3) * 4);

    size_t i = 0;
    while (i < len) {
        size_t remaining = len - i;
        uint32_t octet_a = data[i++];
        uint32_t octet_b = remaining > 1 ? data[i++] : 0;
        uint32_t octet_c = remaining > 2 ? data[i++] : 0;

        uint32_t triple = (octet_a << 16) | (octet_b << 8) | octet_c;

        out.push_back(table[(triple >> 18) & 0x3F]);
        out.push_back(table[(triple >> 12) & 0x3F]);
        out.push_back(remaining > 1 ? table[(triple >> 6) & 0x3F] : '=');
        out.push_back(remaining > 2 ? table[triple & 0x3F] : '=');
    }

    return out;
}

static std::string json_escape(const std::string& input) {
    std::string out;
    out.reserve(input.size() + 16);
    for (char c : input) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += c; break;
        }
    }
    return out;
}

}  // namespace

extern "C" {

rac_result_t rac_diffusion_component_configure_json(rac_handle_t handle, const char* config_json) {
    if (!handle || !config_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_diffusion_config_t config = RAC_DIFFUSION_CONFIG_DEFAULT;
    config.model_variant = parse_variant(config_json, config.model_variant);

    bool bool_val = false;
    if (json_read_bool(config_json, "enable_safety_checker", &bool_val)) {
        config.enable_safety_checker = bool_val ? RAC_TRUE : RAC_FALSE;
    }
    if (json_read_bool(config_json, "reduce_memory", &bool_val)) {
        config.reduce_memory = bool_val ? RAC_TRUE : RAC_FALSE;
    }

    config.preferred_framework = static_cast<int32_t>(
        parse_preferred_framework(config_json,
                                  static_cast<rac_inference_framework_t>(config.preferred_framework)));

    config.tokenizer.source = parse_tokenizer_source(config_json, config.tokenizer.source);

    std::string model_id;
    if (json_read_string(config_json, "model_id", &model_id) && !model_id.empty()) {
        config.model_id = model_id.c_str();
    }

    std::string custom_url;
    if (json_read_string(config_json, "tokenizer_custom_url", &custom_url) &&
        !custom_url.empty()) {
        config.tokenizer.custom_base_url = custom_url.c_str();
    }

    return rac_diffusion_component_configure(handle, &config);
}

rac_result_t rac_diffusion_component_generate_json(
    rac_handle_t handle, const char* options_json, const uint8_t* input_image_data,
    size_t input_image_size, const uint8_t* mask_data, size_t mask_size, char** out_json) {
    if (!handle || !options_json || !out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;

    std::string prompt;
    if (!json_read_string(options_json, "prompt", &prompt) || prompt.empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    options.prompt = prompt.c_str();

    std::string negative_prompt;
    if (json_read_string(options_json, "negative_prompt", &negative_prompt)) {
        options.negative_prompt = negative_prompt.c_str();
    }

    double num = 0.0;
    if (json_read_number(options_json, "width", &num)) {
        options.width = static_cast<int32_t>(num);
    }
    if (json_read_number(options_json, "height", &num)) {
        options.height = static_cast<int32_t>(num);
    }
    if (json_read_number(options_json, "steps", &num)) {
        options.steps = static_cast<int32_t>(num);
    }
    if (json_read_number(options_json, "guidance_scale", &num)) {
        options.guidance_scale = static_cast<float>(num);
    }
    int64_t seed = 0;
    if (json_read_int64(options_json, "seed", &seed)) {
        options.seed = seed;
    }

    options.scheduler = parse_scheduler(options_json, options.scheduler);
    options.mode = parse_mode(options_json, options.mode);

    if (json_read_number(options_json, "denoise_strength", &num)) {
        options.denoise_strength = static_cast<float>(num);
    }

    bool bool_val = false;
    if (json_read_bool(options_json, "report_intermediate_images", &bool_val)) {
        options.report_intermediate_images = bool_val ? RAC_TRUE : RAC_FALSE;
    }
    if (json_read_number(options_json, "progress_stride", &num)) {
        options.progress_stride = static_cast<int32_t>(num);
    }

    if (input_image_data && input_image_size > 0) {
        options.input_image_data = input_image_data;
        options.input_image_size = input_image_size;
    }
    if (json_read_number(options_json, "input_image_width", &num)) {
        options.input_image_width = static_cast<int32_t>(num);
    }
    if (json_read_number(options_json, "input_image_height", &num)) {
        options.input_image_height = static_cast<int32_t>(num);
    }
    if (mask_data && mask_size > 0) {
        options.mask_data = mask_data;
        options.mask_size = mask_size;
    }

    rac_diffusion_result_t result = {};
    rac_result_t status = rac_diffusion_component_generate(handle, &options, &result);
    if (status != RAC_SUCCESS) {
        rac_diffusion_result_free(&result);
        return status;
    }

    std::string json = "{";
    if (result.image_data && result.image_size > 0) {
        std::string b64 = base64_encode(result.image_data, result.image_size);
        json += "\"image_data\":\"" + b64 + "\",";
        json += "\"image_base64\":\"" + b64 + "\",";
    } else {
        json += "\"image_data\":\"\",";
        json += "\"image_base64\":\"\",";
    }
    json += "\"width\":" + std::to_string(result.width) + ",";
    json += "\"height\":" + std::to_string(result.height) + ",";
    json += "\"seed_used\":" + std::to_string(static_cast<long long>(result.seed_used)) + ",";
    json += "\"generation_time_ms\":" +
            std::to_string(static_cast<long long>(result.generation_time_ms)) + ",";
    json += "\"safety_flagged\":" + std::string(result.safety_flagged ? "true" : "false");
    json += "}";

    *out_json = rac_strdup(json.c_str());
    rac_diffusion_result_free(&result);

    return (*out_json != nullptr) ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t rac_diffusion_component_get_info_json(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_diffusion_info_t info = {};
    rac_result_t status = rac_diffusion_component_get_info(handle, &info);
    if (status != RAC_SUCCESS) {
        return status;
    }

    std::string json = "{";
    json += "\"is_ready\":" + std::string(info.is_ready ? "true" : "false") + ",";
    json += "\"current_model\":\"" +
            std::string(info.current_model ? json_escape(info.current_model) : "") + "\",";
    json += "\"model_variant\":" + std::to_string(static_cast<int>(info.model_variant)) + ",";
    json += "\"supports_text_to_image\":" +
            std::string(info.supports_text_to_image ? "true" : "false") + ",";
    json += "\"supports_image_to_image\":" +
            std::string(info.supports_image_to_image ? "true" : "false") + ",";
    json += "\"supports_inpainting\":" +
            std::string(info.supports_inpainting ? "true" : "false") + ",";
    json += "\"safety_checker_enabled\":" +
            std::string(info.safety_checker_enabled ? "true" : "false") + ",";
    json += "\"max_width\":" + std::to_string(info.max_width) + ",";
    json += "\"max_height\":" + std::to_string(info.max_height);
    json += "}";

    *out_json = rac_strdup(json.c_str());
    return (*out_json != nullptr) ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

}  // extern "C"
