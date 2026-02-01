/**
 * @file qnn_stubs.cpp
 * @brief Stub implementations for QNN API functions - QNN is COMPLETELY DISABLED
 *
 * QNN IS DISABLED FOR NNAPI TESTING.
 * This file provides stub implementations for ALL QNN API functions.
 * These stubs are ALWAYS compiled (no conditional guards) to ensure
 * no QNN symbols cause linker errors or crashes.
 */

#include <cstring>
#include <cstdio>

// Do NOT include QNN headers - they may reference QNN symbols
// #include "rac/backends/rac_qnn_config.h"  // DISABLED - contains QNN types
// #include "rac/backends/rac_onnx_npu.h"    // DISABLED - declares QNN functions

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "QNNStub"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#else
#include <cstdio>
#define LOGI(...) fprintf(stdout, "[QNNStub] " __VA_ARGS__); fprintf(stdout, "\n")
#endif

// =============================================================================
// LOCAL TYPE DEFINITIONS (instead of including rac_qnn_config.h)
// These match the header but are defined locally to avoid any QNN dependencies
// =============================================================================

typedef enum {
    RAC_QNN_BACKEND_CPU = 0,
    RAC_QNN_BACKEND_GPU = 1,
    RAC_QNN_BACKEND_HTP = 2,
    RAC_QNN_BACKEND_DSP = 3,
} rac_qnn_backend_t;

typedef enum {
    RAC_NPU_STRATEGY_CPU_ONLY = 0,
    RAC_NPU_STRATEGY_NPU_PREFERRED = 1,
    RAC_NPU_STRATEGY_NPU_REQUIRED = 2,
    RAC_NPU_STRATEGY_HYBRID = 3,
} rac_npu_strategy_t;

typedef struct {
    rac_qnn_backend_t backend;
    int performance_mode;
    int precision;
    int32_t vtcm_mb;
    rac_bool_t disable_cpu_fallback;
    rac_bool_t enable_context_cache;
    const char* context_cache_path;
    int32_t num_htp_threads;
    rac_bool_t enable_profiling;
    int32_t soc_id;
    rac_npu_strategy_t strategy;
} rac_qnn_config_t;

typedef struct {
    const char* encoder_path;
    const char* vocoder_path;
    rac_bool_t encoder_is_quantized;
    const char* encoder_output_names;
    const char* vocoder_input_names;
} rac_split_model_config_t;

typedef struct {
    char name[64];
    int32_t soc_id;
    int32_t hexagon_arch;
    char marketing_name[128];
    rac_bool_t htp_available;
    float htp_tops;
} rac_soc_info_t;

typedef struct {
    rac_bool_t is_npu_active;
    rac_npu_strategy_t active_strategy;
    int32_t ops_on_npu;
    int32_t ops_on_cpu;
    float npu_op_percentage;
    double encoder_inference_ms;
    double vocoder_inference_ms;
    double total_inference_ms;
    int64_t npu_memory_bytes;
    int64_t cpu_memory_bytes;
    int64_t total_inferences;
} rac_npu_stats_t;

typedef struct {
    rac_bool_t is_npu_ready;
    rac_bool_t is_qdq_quantized;
    rac_bool_t has_static_shapes;
    rac_bool_t all_ops_supported;
    int32_t unsupported_op_count;
    char unsupported_ops[512];
    char dynamic_dims[256];
    char recommendation[512];
} rac_model_validation_result_t;

typedef struct {
    float encoder_inference_ms;
    float vocoder_inference_ms;
    float total_inference_ms;
    uint64_t total_inferences;
    rac_bool_t encoder_on_npu;
} rac_split_exec_stats_t;

typedef void* rac_split_executor_t;

extern "C" {

// =============================================================================
// QNN Detection and Information API Stubs
// =============================================================================

rac_bool_t rac_qnn_is_available(void) {
    LOGI("rac_qnn_is_available() - QNN DISABLED, returning FALSE");
    return RAC_FALSE;
}

rac_result_t rac_qnn_get_soc_info(rac_soc_info_t* out_info) {
    LOGI("rac_qnn_get_soc_info() - QNN DISABLED");
    if (out_info) {
        memset(out_info, 0, sizeof(rac_soc_info_t));
        snprintf(out_info->name, sizeof(out_info->name), "QNN_DISABLED");
        snprintf(out_info->marketing_name, sizeof(out_info->marketing_name), "QNN disabled for NNAPI testing");
        out_info->htp_available = RAC_FALSE;
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t rac_qnn_get_soc_info_json(char* json_buffer, size_t buffer_size) {
    LOGI("rac_qnn_get_soc_info_json() - QNN DISABLED");
    if (json_buffer && buffer_size > 0) {
        snprintf(json_buffer, buffer_size,
            "{\"htp_available\":false,\"name\":\"QNN_DISABLED\",\"reason\":\"QNN disabled for NNAPI testing\"}");
    }
    return RAC_SUCCESS;  // Return success so callers don't fail
}

// =============================================================================
// QNN Configuration API Stubs
// =============================================================================

void rac_qnn_config_init_default(rac_qnn_config_t* config) {
    LOGI("rac_qnn_config_init_default() - QNN DISABLED");
    if (config) {
        memset(config, 0, sizeof(rac_qnn_config_t));
        config->backend = RAC_QNN_BACKEND_CPU;
        config->strategy = RAC_NPU_STRATEGY_CPU_ONLY;
    }
}

rac_result_t rac_qnn_validate_config(const rac_qnn_config_t* config) {
    (void)config;
    LOGI("rac_qnn_validate_config() - QNN DISABLED");
    return RAC_ERROR_NOT_IMPLEMENTED;
}

// =============================================================================
// Model Validation API Stubs
// =============================================================================

rac_result_t rac_qnn_validate_model(const char* model_path, rac_model_validation_result_t* result) {
    (void)model_path;
    LOGI("rac_qnn_validate_model() - QNN DISABLED");
    if (result) {
        memset(result, 0, sizeof(rac_model_validation_result_t));
        result->is_npu_ready = RAC_FALSE;
        snprintf(result->recommendation, sizeof(result->recommendation), "QNN disabled for NNAPI testing");
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t rac_qnn_get_supported_ops(char* out_ops, size_t ops_size) {
    LOGI("rac_qnn_get_supported_ops() - QNN DISABLED");
    if (out_ops && ops_size > 0) {
        snprintf(out_ops, ops_size, "QNN_DISABLED");
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

void rac_split_model_config_init(rac_split_model_config_t* config, const char* encoder_path,
                                 const char* vocoder_path) {
    LOGI("rac_split_model_config_init() - QNN DISABLED");
    if (config) {
        memset(config, 0, sizeof(rac_split_model_config_t));
        config->encoder_path = encoder_path;
        config->vocoder_path = vocoder_path;
        config->encoder_is_quantized = RAC_FALSE;
    }
}

// =============================================================================
// Split Model Executor Stubs (from rac_onnx_npu.h)
// =============================================================================

rac_result_t rac_split_executor_create(const rac_split_model_config_t* config,
                                       const rac_qnn_config_t* qnn_config,
                                       rac_split_executor_t* out_executor) {
    (void)config;
    (void)qnn_config;
    LOGI("rac_split_executor_create() - QNN DISABLED");
    if (out_executor) {
        *out_executor = nullptr;
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t rac_split_executor_run(rac_split_executor_t executor,
                                    const int64_t* phoneme_ids, size_t phoneme_count,
                                    const float* style_vector, float* out_audio,
                                    size_t* out_audio_samples) {
    (void)executor;
    (void)phoneme_ids;
    (void)phoneme_count;
    (void)style_vector;
    (void)out_audio;
    LOGI("rac_split_executor_run() - QNN DISABLED");
    if (out_audio_samples) {
        *out_audio_samples = 0;
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t rac_split_executor_get_stats(rac_split_executor_t executor,
                                          rac_split_exec_stats_t* out_stats) {
    (void)executor;
    LOGI("rac_split_executor_get_stats() - QNN DISABLED");
    if (out_stats) {
        memset(out_stats, 0, sizeof(rac_split_exec_stats_t));
        out_stats->encoder_on_npu = RAC_FALSE;
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

void rac_split_executor_destroy(rac_split_executor_t executor) {
    (void)executor;
    LOGI("rac_split_executor_destroy() - QNN DISABLED");
}

// =============================================================================
// Context Caching Stubs (from rac_onnx_npu.h)
// =============================================================================

rac_result_t rac_onnx_generate_context_binary(const char* model_path,
                                              const rac_qnn_config_t* qnn_config,
                                              const char* output_path) {
    (void)model_path;
    (void)qnn_config;
    (void)output_path;
    LOGI("rac_onnx_generate_context_binary() - QNN DISABLED");
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_bool_t rac_onnx_has_context_binary(const char* model_path, const char* cache_dir) {
    (void)model_path;
    (void)cache_dir;
    LOGI("rac_onnx_has_context_binary() - QNN DISABLED");
    return RAC_FALSE;
}

// =============================================================================
// NPU Supported Ops Stub (from rac_onnx_npu.h)
// =============================================================================

rac_result_t rac_onnx_get_npu_supported_ops(char* out_ops, size_t ops_size) {
    LOGI("rac_onnx_get_npu_supported_ops() - QNN DISABLED");
    if (out_ops && ops_size > 0) {
        snprintf(out_ops, ops_size, "QNN_DISABLED");
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

// =============================================================================
// TTS NPU Creation Stub (from rac_onnx_npu.h)
// =============================================================================

rac_result_t rac_tts_onnx_create_npu(const char* model_path,
                                     const rac_qnn_config_t* qnn_config,
                                     rac_handle_t* out_handle) {
    (void)model_path;
    (void)qnn_config;
    LOGI("rac_tts_onnx_create_npu() - QNN DISABLED");
    if (out_handle) {
        *out_handle = nullptr;
    }
    return RAC_ERROR_NOT_IMPLEMENTED;
}

// =============================================================================
// NOTE: The following rac_onnx_* and rac_tts_onnx_* functions are defined in
// rac_onnx.cpp with void* parameter types. Do NOT define them here:
// - rac_onnx_is_npu_available()
// - rac_onnx_get_npu_info_json()
// - rac_onnx_get_soc_info(void*)
// - rac_onnx_validate_model_for_npu(const char*, void*)
// - rac_tts_onnx_create_hybrid(const char*, const char*, const void*, rac_handle_t*)
// - rac_tts_onnx_get_npu_stats(rac_handle_t, void*)
// - rac_tts_onnx_is_npu_active(rac_handle_t)
// - rac_tts_onnx_destroy_hybrid(rac_handle_t)
//
// This file defines the rac_qnn_* and rac_split_* functions that are declared
// in rac_qnn_config.h and rac_onnx_npu.h.
// =============================================================================

} // extern "C"
