/**
 * @file model_strategy.cpp
 * @brief Model Storage and Download Strategy Implementation
 *
 * Registry for backend-specific model handling strategies.
 * Strategies are registered per-framework during backend initialization.
 */

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <limits>
#include <mutex>
#include <unordered_map>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/extraction/rac_extraction.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"

namespace {

const char* LOG_CAT = "ModelStrategy";

// Strategy registry - maps framework to strategies
struct StrategyRegistry {
    std::unordered_map<int, rac_storage_strategy_t> storage_strategies;
    std::unordered_map<int, rac_download_strategy_t> download_strategies;
    std::mutex mutex;
};

StrategyRegistry& get_registry() {
    static StrategyRegistry registry;
    return registry;
}

char* dup_c_string(const char* value) {
    if (!value) {
        return nullptr;
    }
    size_t len = strlen(value);
    char* out = static_cast<char*>(malloc(len + 1));
    if (!out) {
        return nullptr;
    }
    memcpy(out, value, len + 1);
    return out;
}

rac_result_t copy_string_to_buffer(const char* value, char* out_path, size_t path_size) {
    if (!value || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    size_t len = strlen(value);
    if (len >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    memcpy(out_path, value, len + 1);
    return RAC_SUCCESS;
}

rac_model_info_t make_resolution_model(const char* model_id, rac_inference_framework_t framework,
                                       rac_artifact_type_kind_t artifact_kind,
                                       rac_archive_type_t archive_type) {
    rac_model_info_t model{};
    model.id = const_cast<char*>(model_id);
    model.framework = framework;
    model.format = RAC_MODEL_FORMAT_UNKNOWN;
    model.artifact_info.kind = artifact_kind;
    model.artifact_info.archive_type = archive_type;
    model.artifact_info.archive_structure = RAC_ARCHIVE_STRUCTURE_UNKNOWN;
    return model;
}

rac_result_t resolve_default_model_path(rac_inference_framework_t framework, const char* model_id,
                                        const char* artifact_root,
                                        rac_model_path_resolution_t* out_resolution) {
    if (!artifact_root || !out_resolution) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    rac_model_info_t model = make_resolution_model(
        model_id, framework, RAC_ARTIFACT_KIND_MULTI_FILE, RAC_ARCHIVE_TYPE_NONE);
    return rac_model_paths_resolve_artifact(&model, artifact_root, nullptr, out_resolution);
}

rac_model_format_t detect_format_from_path(const char* path) {
    if (!path) {
        return RAC_MODEL_FORMAT_UNKNOWN;
    }
    std::filesystem::path fs_path(path);
    std::string ext = fs_path.extension().generic_string();
    if (!ext.empty() && ext[0] == '.') {
        ext.erase(ext.begin());
    }
    rac_model_format_t format = RAC_MODEL_FORMAT_UNKNOWN;
    if (rac_model_detect_format_from_extension(ext.c_str(), &format) == RAC_TRUE) {
        return format;
    }
    return RAC_MODEL_FORMAT_UNKNOWN;
}

}  // namespace

// =============================================================================
// RESOURCE CLEANUP
// =============================================================================

void rac_model_storage_details_free(rac_model_storage_details_t* details) {
    if (details && details->primary_file) {
        free(details->primary_file);
        details->primary_file = nullptr;
    }
}

void rac_download_result_free(rac_download_result_t* result) {
    if (result && result->final_path) {
        free(result->final_path);
        result->final_path = nullptr;
    }
}

// =============================================================================
// STRATEGY REGISTRATION
// =============================================================================

rac_result_t rac_storage_strategy_register(rac_inference_framework_t framework,
                                           const rac_storage_strategy_t* strategy) {
    if (!strategy) {
        RAC_LOG_ERROR(LOG_CAT, "Cannot register null storage strategy");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    auto& registry = get_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);

    int key = static_cast<int>(framework);
    registry.storage_strategies[key] = *strategy;

    RAC_LOG_INFO(LOG_CAT, "Registered storage strategy '%s' for framework %d",
                 strategy->name ? strategy->name : "unnamed", key);

    return RAC_SUCCESS;
}

rac_result_t rac_download_strategy_register(rac_inference_framework_t framework,
                                            const rac_download_strategy_t* strategy) {
    if (!strategy) {
        RAC_LOG_ERROR(LOG_CAT, "Cannot register null download strategy");
        return RAC_ERROR_INVALID_PARAMETER;
    }

    auto& registry = get_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);

    int key = static_cast<int>(framework);
    registry.download_strategies[key] = *strategy;

    RAC_LOG_INFO(LOG_CAT, "Registered download strategy '%s' for framework %d",
                 strategy->name ? strategy->name : "unnamed", key);

    return RAC_SUCCESS;
}

void rac_model_strategy_unregister(rac_inference_framework_t framework) {
    auto& registry = get_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);

    int key = static_cast<int>(framework);
    registry.storage_strategies.erase(key);
    registry.download_strategies.erase(key);

    RAC_LOG_INFO(LOG_CAT, "Unregistered strategies for framework %d", key);
}

// =============================================================================
// STRATEGY LOOKUP
// =============================================================================

const rac_storage_strategy_t* rac_storage_strategy_get(rac_inference_framework_t framework) {
    auto& registry = get_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);

    int key = static_cast<int>(framework);
    auto it = registry.storage_strategies.find(key);

    if (it != registry.storage_strategies.end()) {
        return &it->second;
    }

    return nullptr;
}

const rac_download_strategy_t* rac_download_strategy_get(rac_inference_framework_t framework) {
    auto& registry = get_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);

    int key = static_cast<int>(framework);
    auto it = registry.download_strategies.find(key);

    if (it != registry.download_strategies.end()) {
        return &it->second;
    }

    return nullptr;
}

// =============================================================================
// CONVENIENCE API - High-level operations
// =============================================================================

rac_result_t rac_model_strategy_find_path(rac_inference_framework_t framework, const char* model_id,
                                          const char* model_folder, char* out_path,
                                          size_t path_size) {
    if (!model_id || !model_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const rac_storage_strategy_t* strategy = rac_storage_strategy_get(framework);
    if (!strategy || !strategy->find_model_path) {
        rac_model_path_resolution_t resolution{};
        rac_result_t rc =
            resolve_default_model_path(framework, model_id, model_folder, &resolution);
        if (rc != RAC_SUCCESS) {
            RAC_LOG_DEBUG(LOG_CAT, "Default path resolution failed for framework %d: %d", framework,
                          rc);
            return rc;
        }
        rc = copy_string_to_buffer(resolution.primary_model_path, out_path, path_size);
        rac_model_path_resolution_free(&resolution);
        return rc;
    }

    return strategy->find_model_path(model_id, model_folder, out_path, path_size,
                                     strategy->user_data);
}

rac_result_t rac_model_strategy_detect(rac_inference_framework_t framework,
                                       const char* model_folder,
                                       rac_model_storage_details_t* out_details) {
    if (!model_folder || !out_details) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const rac_storage_strategy_t* strategy = rac_storage_strategy_get(framework);
    if (!strategy || !strategy->detect_model) {
        memset(out_details, 0, sizeof(*out_details));

        rac_model_path_resolution_t resolution{};
        rac_result_t rc = resolve_default_model_path(framework, nullptr, model_folder, &resolution);
        if (rc != RAC_SUCCESS) {
            RAC_LOG_DEBUG(LOG_CAT, "Default model detection failed for framework %d: %d", framework,
                          rc);
            return rc;
        }

        out_details->format = detect_format_from_path(resolution.primary_model_path);
        out_details->file_count =
            resolution.file_count > static_cast<size_t>(std::numeric_limits<int>::max())
                ? std::numeric_limits<int>::max()
                : static_cast<int>(resolution.file_count);
        out_details->is_directory_based = resolution.is_directory_based;
        out_details->is_valid = resolution.is_complete;
        out_details->total_size = 0;
        if (resolution.primary_model_path) {
            std::filesystem::path primary(resolution.primary_model_path);
            std::string name = primary.filename().generic_string();
            if (name.empty()) {
                name = resolution.primary_model_path;
            }
            out_details->primary_file = dup_c_string(name.c_str());
            if (!out_details->primary_file) {
                rac_model_path_resolution_free(&resolution);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
        }

        rac_model_path_resolution_free(&resolution);
        return RAC_SUCCESS;
    }

    return strategy->detect_model(model_folder, out_details, strategy->user_data);
}

rac_bool_t rac_model_strategy_is_valid(rac_inference_framework_t framework,
                                       const char* model_folder) {
    if (!model_folder) {
        return RAC_FALSE;
    }

    const rac_storage_strategy_t* strategy = rac_storage_strategy_get(framework);
    if (!strategy || !strategy->is_valid_storage) {
        rac_model_storage_details_t details{};
        rac_result_t rc = rac_model_strategy_detect(framework, model_folder, &details);
        rac_bool_t valid =
            (rc == RAC_SUCCESS && details.is_valid == RAC_TRUE) ? RAC_TRUE : RAC_FALSE;
        rac_model_storage_details_free(&details);
        return valid;
    }

    return strategy->is_valid_storage(model_folder, strategy->user_data);
}

rac_result_t rac_model_strategy_prepare_download(rac_inference_framework_t framework,
                                                 const rac_model_download_config_t* config) {
    if (!config) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const rac_download_strategy_t* strategy = rac_download_strategy_get(framework);
    if (!strategy || !strategy->prepare_download) {
        // No custom strategy - use default behavior
        RAC_LOG_DEBUG(LOG_CAT, "No download strategy for framework %d, using defaults", framework);
        return RAC_SUCCESS;
    }

    return strategy->prepare_download(config, strategy->user_data);
}

rac_result_t rac_model_strategy_get_download_dest(rac_inference_framework_t framework,
                                                  const rac_model_download_config_t* config,
                                                  char* out_path, size_t path_size) {
    if (!config || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const rac_download_strategy_t* strategy = rac_download_strategy_get(framework);
    if (!strategy || !strategy->get_destination_path) {
        // No custom strategy - use default path from config
        if (config->destination_folder) {
            size_t len = strlen(config->destination_folder);
            if (len >= path_size) {
                return RAC_ERROR_BUFFER_TOO_SMALL;
            }
            memcpy(out_path, config->destination_folder, len + 1);
            return RAC_SUCCESS;
        }
        return RAC_ERROR_INVALID_PARAMETER;
    }

    return strategy->get_destination_path(config, out_path, path_size, strategy->user_data);
}

rac_result_t rac_model_strategy_post_process(rac_inference_framework_t framework,
                                             const rac_model_download_config_t* config,
                                             const char* downloaded_path,
                                             rac_download_result_t* out_result) {
    if (!config || !downloaded_path || !out_result) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    const rac_download_strategy_t* strategy = rac_download_strategy_get(framework);
    if (!strategy || !strategy->post_process) {
        memset(out_result, 0, sizeof(*out_result));

        bool should_extract = config->archive_type != RAC_ARCHIVE_TYPE_NONE;
        std::string artifact_root = downloaded_path;
        if (should_extract) {
            if (!config->destination_folder) {
                return RAC_ERROR_INVALID_PARAMETER;
            }
            rac_extraction_options_t options = RAC_EXTRACTION_OPTIONS_DEFAULT;
            options.archive_type_hint = config->archive_type;
            rac_extraction_result_t extraction{};
            rac_result_t extract_rc =
                rac_extract_archive_native(downloaded_path, config->destination_folder, &options,
                                           nullptr, nullptr, &extraction);
            if (extract_rc != RAC_SUCCESS) {
                return extract_rc;
            }
            artifact_root = config->destination_folder;
        }

        rac_model_path_resolution_t resolution{};
        rac_model_info_t model = make_resolution_model(
            config->model_id, framework,
            should_extract ? RAC_ARTIFACT_KIND_ARCHIVE : RAC_ARTIFACT_KIND_SINGLE_FILE,
            config->archive_type);
        rac_result_t rc =
            rac_model_paths_resolve_artifact(&model, artifact_root.c_str(), nullptr, &resolution);
        if (rc != RAC_SUCCESS) {
            rac_model_path_resolution_free(&resolution);
            return rc;
        }

        const char* final_path =
            resolution.primary_model_path ? resolution.primary_model_path : artifact_root.c_str();
        out_result->final_path = dup_c_string(final_path);
        if (!out_result->final_path) {
            rac_model_path_resolution_free(&resolution);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        out_result->downloaded_size = config->expected_size;
        out_result->was_extracted = should_extract ? RAC_TRUE : RAC_FALSE;
        out_result->file_count =
            resolution.file_count > static_cast<size_t>(std::numeric_limits<int>::max())
                ? std::numeric_limits<int>::max()
                : static_cast<int>(resolution.file_count);
        rac_model_path_resolution_free(&resolution);
        return RAC_SUCCESS;
    }

    return strategy->post_process(config, downloaded_path, out_result, strategy->user_data);
}
