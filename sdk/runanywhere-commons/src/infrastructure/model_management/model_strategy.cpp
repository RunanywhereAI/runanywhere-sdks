/**
 * @file model_strategy.cpp
 * @brief Model Storage and Download Strategy Implementation
 *
 * Registry for backend-specific model handling strategies.
 * Strategies are registered per-framework during backend initialization.
 */

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_map>

#include "rac/core/rac_logger.h"
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
        RAC_LOG_DEBUG(LOG_CAT, "No storage strategy for framework %d", framework);
        return RAC_ERROR_NOT_FOUND;
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
        RAC_LOG_DEBUG(LOG_CAT, "No storage strategy for framework %d", framework);
        return RAC_ERROR_NOT_FOUND;
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
        return RAC_FALSE;
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
            strcpy(out_path, config->destination_folder);
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
        // No custom strategy - set basic result
        out_result->final_path = strdup(downloaded_path);
        out_result->downloaded_size = 0;  // Unknown
        out_result->was_extracted = RAC_FALSE;
        out_result->file_count = 1;
        return RAC_SUCCESS;
    }

    return strategy->post_process(config, downloaded_path, out_result, strategy->user_data);
}
