/**
 * @file rac_backend_onnx_register.cpp
 * @brief ONNX Runtime backend registration for generic ONNX model services.
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/backends/rac_embeddings_onnx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_strategy.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace {

const char* LOG_CAT = "ONNX";
const char* const MODULE_ID = "onnx";

// =============================================================================
// STORAGE AND DOWNLOAD STRATEGIES
// =============================================================================

rac_result_t onnx_storage_find_model_path(const char* model_id, const char* model_folder,
                                          char* out_path, size_t path_size, void* user_data) {
    (void)user_data;

    if (!model_id || !model_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    int written = snprintf(out_path, path_size, "%s/%s.onnx", model_folder, model_id);
    if (written < 0 || (size_t)written >= path_size) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    return RAC_SUCCESS;
}

rac_result_t onnx_storage_detect_model(const char* model_folder,
                                       rac_model_storage_details_t* out_details, void* user_data) {
    (void)user_data;

    if (!model_folder || !out_details) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    memset(out_details, 0, sizeof(rac_model_storage_details_t));
    out_details->format = RAC_MODEL_FORMAT_ONNX;
    out_details->is_directory_based = RAC_TRUE;
    out_details->is_valid = RAC_TRUE;
    out_details->total_size = 0;
    out_details->file_count = 1;
    out_details->primary_file = nullptr;

    return RAC_SUCCESS;
}

rac_bool_t onnx_storage_is_valid(const char* model_folder, void* user_data) {
    (void)user_data;
    return model_folder ? RAC_TRUE : RAC_FALSE;
}

void onnx_storage_get_patterns(const char*** out_patterns, size_t* out_count, void* user_data) {
    (void)user_data;

    static const char* patterns[] = {"*.onnx", "*.ort", "encoder*.onnx", "decoder*.onnx",
                                     "model.onnx"};
    *out_patterns = patterns;
    *out_count = sizeof(patterns) / sizeof(patterns[0]);
}

rac_result_t onnx_download_prepare(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;
    return (config && config->model_id && config->destination_folder) ? RAC_SUCCESS
                                                                      : RAC_ERROR_INVALID_PARAMETER;
}

rac_result_t onnx_download_get_dest(const rac_model_download_config_t* config, char* out_path,
                                    size_t path_size, void* user_data) {
    (void)user_data;

    if (!config || !config->destination_folder || !out_path || path_size == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    int written =
        snprintf(out_path, path_size, "%s/%s", config->destination_folder, config->model_id);
    return (written < 0 || (size_t)written >= path_size) ? RAC_ERROR_BUFFER_TOO_SMALL : RAC_SUCCESS;
}

rac_result_t onnx_download_post_process(const rac_model_download_config_t* config,
                                        const char* downloaded_path,
                                        rac_download_result_t* out_result, void* user_data) {
    (void)user_data;

    if (!config || !downloaded_path || !out_result) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    memset(out_result, 0, sizeof(rac_download_result_t));
    out_result->was_extracted =
        (config->archive_type != RAC_ARCHIVE_TYPE_NONE) ? RAC_TRUE : RAC_FALSE;
    out_result->final_path = strdup(downloaded_path);
    if (!out_result->final_path) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->file_count = 1;

    return RAC_SUCCESS;
}

void onnx_download_cleanup(const rac_model_download_config_t* config, void* user_data) {
    (void)user_data;
    (void)config;
}

static rac_storage_strategy_t g_onnx_storage_strategy = {onnx_storage_find_model_path,
                                                         onnx_storage_detect_model,
                                                         onnx_storage_is_valid,
                                                         onnx_storage_get_patterns,
                                                         nullptr,
                                                         "ONNXStorageStrategy"};

static rac_download_strategy_t g_onnx_download_strategy = {onnx_download_prepare,
                                                           onnx_download_get_dest,
                                                           onnx_download_post_process,
                                                           onnx_download_cleanup,
                                                           nullptr,
                                                           "ONNXDownloadStrategy"};

bool g_registered = false;

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_onnx_register(void) {
    if (g_registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    rac_module_info_t module_info = {};
    module_info.id = MODULE_ID;
    module_info.name = "ONNX Runtime";
    module_info.version = "1.0.0";
    module_info.description = "ONNX Runtime backend";
    module_info.capabilities = nullptr;
    module_info.num_capabilities = 0;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    rac_storage_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_storage_strategy);
    rac_download_strategy_register(RAC_FRAMEWORK_ONNX, &g_onnx_download_strategy);
    rac_backend_onnx_embeddings_register();

    g_registered = true;
    RAC_LOG_INFO(LOG_CAT, "ONNX backend registered (module + strategies + embeddings)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_onnx_unregister(void) {
    if (!g_registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_backend_onnx_embeddings_unregister();
    rac_model_strategy_unregister(RAC_FRAMEWORK_ONNX);
    rac_module_unregister(MODULE_ID);

    g_registered = false;
    return RAC_SUCCESS;
}

}  // extern "C"
