/**
 * @file model_paths.cpp
 * @brief Model Path Utilities Implementation
 *
 * C port of Swift's ModelPathUtils from:
 * Sources/RunAnywhere/Infrastructure/ModelManagement/Utilities/ModelPathUtils.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

// =============================================================================
// STATIC STATE
// =============================================================================

static std::mutex g_paths_mutex{};
static std::string g_base_dir{};

// =============================================================================
// CONFIGURATION
// =============================================================================

rac_result_t rac_model_paths_set_base_dir(const char* base_dir) {
    if (!base_dir) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);
    g_base_dir = base_dir;

    // Remove trailing slash if present
    while (!g_base_dir.empty() && (g_base_dir.back() == '/' || g_base_dir.back() == '\\')) {
        g_base_dir.pop_back();
    }

    return RAC_SUCCESS;
}

const char* rac_model_paths_get_base_dir(void) {
    std::lock_guard<std::mutex> lock(g_paths_mutex);
    return g_base_dir.empty() ? nullptr : g_base_dir.c_str();
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static rac_result_t copy_string_to_buffer(const std::string& src, char* out_path,
                                          size_t path_size) {
    if (!out_path || path_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (src.length() >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    strncpy(out_path, src.c_str(), path_size - 1);
    out_path[path_size - 1] = '\0';
    return RAC_SUCCESS;
}

static std::vector<std::string> split_path(const std::string& path) {
    std::vector<std::string> components;
    size_t start = 0;
    size_t end = 0;

    while ((end = path.find_first_of("/\\", start)) != std::string::npos) {
        if (end > start) {
            components.push_back(path.substr(start, end - start));
        }
        start = end + 1;
    }

    if (start < path.length()) {
        components.push_back(path.substr(start));
    }

    return components;
}

// =============================================================================
// FORMAT AND FRAMEWORK UTILITIES
// =============================================================================

// NOTE: rac_model_format_extension is defined in model_types.cpp

const char* rac_framework_raw_value(rac_inference_framework_t framework) {
    // Mirrors Swift's InferenceFramework.rawValue
    switch (framework) {
        case RAC_FRAMEWORK_ONNX:
            return "ONNX";
        case RAC_FRAMEWORK_LLAMACPP:
            return "LlamaCpp";
        case RAC_FRAMEWORK_COREML:
            return "CoreML";
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return "FoundationModels";
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return "SystemTTS";
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return "FluidAudio";
        case RAC_FRAMEWORK_WHISPERKIT:
            return "WhisperKit";
        case RAC_FRAMEWORK_BUILTIN:
            return "BuiltIn";
        case RAC_FRAMEWORK_NONE:
            return "None";
        default:
            return "Unknown";
    }
}

// =============================================================================
// BASE DIRECTORIES
// =============================================================================

rac_result_t rac_model_paths_get_base_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getBaseDirectory()
    // Returns: {base_dir}/RunAnywhere/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere";
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_models_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelsDirectory()
    // Returns: {base_dir}/RunAnywhere/Models/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere/Models";
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// FRAMEWORK-SPECIFIC PATHS
// =============================================================================

rac_result_t rac_model_paths_get_framework_directory(rac_inference_framework_t framework,
                                                     char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getFrameworkDirectory(framework:)
    // Returns: {base_dir}/RunAnywhere/Models/{framework.rawValue}/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere/Models/" + rac_framework_raw_value(framework);
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_model_folder(const char* model_id,
                                              rac_inference_framework_t framework, char* out_path,
                                              size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelFolder(modelId:framework:)
    // Returns: {base_dir}/RunAnywhere/Models/{framework.rawValue}/{modelId}/

    if (!model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path =
        g_base_dir + "/RunAnywhere/Models/" + rac_framework_raw_value(framework) + "/" + model_id;
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// MODEL FILE PATHS
// =============================================================================

rac_result_t rac_model_paths_get_model_file_path(const char* model_id,
                                                 rac_inference_framework_t framework,
                                                 rac_model_format_t format, char* out_path,
                                                 size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelFilePath(modelId:framework:format:)
    // Returns:
    // {base_dir}/RunAnywhere/Models/{framework.rawValue}/{modelId}/{modelId}.{format.rawValue}

    if (!model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* extension = rac_model_format_extension(format);
    if (!extension) {
        // Unknown format - return just the model folder path
        // The caller should search for model files in this folder
        RAC_LOG_WARNING("ModelPaths", "Unknown model format (%d) for model '%s', returning folder path",
                        static_cast<int>(format), model_id);
        std::string path = g_base_dir + "/RunAnywhere/Models/" + rac_framework_raw_value(framework) +
                           "/" + model_id;
        return copy_string_to_buffer(path, out_path, path_size);
    }

    std::string path = g_base_dir + "/RunAnywhere/Models/" + rac_framework_raw_value(framework) +
                       "/" + model_id + "/" + model_id + "." + extension;
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_expected_model_path(const char* model_id,
                                                     rac_inference_framework_t framework,
                                                     rac_model_format_t format, char* out_path,
                                                     size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getExpectedModelPath(modelId:framework:format:)
    // For directory-based frameworks, returns the model folder
    // For single-file frameworks, returns the model file path

    if (!model_id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Check if framework uses directory-based models
    // (mirrors Swift's InferenceFramework.usesDirectoryBasedModels)
    if (rac_framework_uses_directory_based_models(framework) == RAC_TRUE) {
        return rac_model_paths_get_model_folder(model_id, framework, out_path, path_size);
    }

    return rac_model_paths_get_model_file_path(model_id, framework, format, out_path, path_size);
}

rac_result_t rac_model_paths_get_model_path(const rac_model_info_t* model_info, char* out_path,
                                            size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getModelPath(modelInfo:)

    if (!model_info || !model_info->id) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    return rac_model_paths_get_model_file_path(model_info->id, model_info->framework,
                                               model_info->format, out_path, path_size);
}

// =============================================================================
// OTHER DIRECTORIES
// =============================================================================

rac_result_t rac_model_paths_get_cache_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getCacheDirectory()
    // Returns: {base_dir}/RunAnywhere/Cache/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere/Cache";
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_temp_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getTempDirectory()
    // Returns: {base_dir}/RunAnywhere/Temp/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere/Temp";
    return copy_string_to_buffer(path, out_path, path_size);
}

rac_result_t rac_model_paths_get_downloads_directory(char* out_path, size_t path_size) {
    // Mirrors Swift's ModelPathUtils.getDownloadsDirectory()
    // Returns: {base_dir}/RunAnywhere/Downloads/

    std::lock_guard<std::mutex> lock(g_paths_mutex);

    if (g_base_dir.empty()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::string path = g_base_dir + "/RunAnywhere/Downloads";
    return copy_string_to_buffer(path, out_path, path_size);
}

// =============================================================================
// PATH ANALYSIS
// =============================================================================

rac_result_t rac_model_paths_extract_model_id(const char* path, char* out_model_id,
                                              size_t model_id_size) {
    // Mirrors Swift's ModelPathUtils.extractModelId(from:)

    if (!path) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<std::string> components = split_path(path);

    // Find "Models" component
    auto it = std::find(components.begin(), components.end(), "Models");
    if (it == components.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    auto modelsIndex = static_cast<size_t>(std::distance(components.begin(), it));

    // Check if there's a component after "Models"
    if (modelsIndex + 1 >= components.size()) {
        return RAC_ERROR_NOT_FOUND;
    }

    std::string nextComponent = components[modelsIndex + 1];

    // Check if next component is a framework name
    bool isFramework = false;
    const char* frameworks[] = {"ONNX",      "LlamaCpp",   "FoundationModels",
                                "SystemTTS", "FluidAudio", "BuiltIn",
                                "None",      "Unknown"};
    for (const char* fw : frameworks) {
        if (nextComponent == fw) {
            isFramework = true;
            break;
        }
    }

    std::string modelId;
    if (isFramework && modelsIndex + 2 < components.size()) {
        // Framework structure: Models/framework/modelId
        modelId = components[modelsIndex + 2];
    } else {
        // Direct model folder structure: Models/modelId
        modelId = nextComponent;
    }

    if (out_model_id && model_id_size > 0) {
        return copy_string_to_buffer(modelId, out_model_id, model_id_size);
    }

    return RAC_SUCCESS;
}

rac_result_t rac_model_paths_extract_framework(const char* path,
                                               rac_inference_framework_t* out_framework) {
    // Mirrors Swift's ModelPathUtils.extractFramework(from:)

    if (!path || !out_framework) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<std::string> components = split_path(path);

    // Find "Models" component
    auto it = std::find(components.begin(), components.end(), "Models");
    if (it == components.end()) {
        return RAC_ERROR_NOT_FOUND;
    }

    auto modelsIndex = static_cast<size_t>(std::distance(components.begin(), it));

    // Check if there's a component after "Models"
    if (modelsIndex + 1 >= components.size()) {
        return RAC_ERROR_NOT_FOUND;
    }

    std::string nextComponent = components[modelsIndex + 1];

    // Map to framework enum
    if (nextComponent == "ONNX") {
        *out_framework = RAC_FRAMEWORK_ONNX;
        return RAC_SUCCESS;
    } else if (nextComponent == "LlamaCpp") {
        *out_framework = RAC_FRAMEWORK_LLAMACPP;
        return RAC_SUCCESS;
    } else if (nextComponent == "FoundationModels") {
        *out_framework = RAC_FRAMEWORK_FOUNDATION_MODELS;
        return RAC_SUCCESS;
    } else if (nextComponent == "SystemTTS") {
        *out_framework = RAC_FRAMEWORK_SYSTEM_TTS;
        return RAC_SUCCESS;
    } else if (nextComponent == "FluidAudio") {
        *out_framework = RAC_FRAMEWORK_FLUID_AUDIO;
        return RAC_SUCCESS;
    } else if (nextComponent == "WhisperKit") {
        *out_framework = RAC_FRAMEWORK_WHISPERKIT;
        return RAC_SUCCESS;
    } else if (nextComponent == "BuiltIn") {
        *out_framework = RAC_FRAMEWORK_BUILTIN;
        return RAC_SUCCESS;
    } else if (nextComponent == "None") {
        *out_framework = RAC_FRAMEWORK_NONE;
        return RAC_SUCCESS;
    }

    return RAC_ERROR_NOT_FOUND;
}

rac_bool_t rac_model_paths_is_model_path(const char* path) {
    // Mirrors Swift's ModelPathUtils.isModelPath(_:)

    if (!path) {
        return RAC_FALSE;
    }

    // Simply check if "Models" appears in the path
    return (strstr(path, "Models") != nullptr) ? RAC_TRUE : RAC_FALSE;
}
