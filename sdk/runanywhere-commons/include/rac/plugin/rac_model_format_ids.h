/**
 * @file rac_model_format_ids.h
 * @brief ABI-safe model format IDs shared by engine/runtime metadata.
 *
 * These values mirror `runanywhere.v1.ModelFormat` in `idl/model_types.proto`.
 * Keep plugin/runtime metadata on these IDs instead of hand-writing numeric
 * literals or including protobuf headers in ABI-facing C headers.
 */

#ifndef RAC_PLUGIN_MODEL_FORMAT_IDS_H
#define RAC_PLUGIN_MODEL_FORMAT_IDS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_model_format_id {
    RAC_MODEL_FORMAT_ID_UNSPECIFIED = 0u,
    RAC_MODEL_FORMAT_ID_GGUF = 1u,
    RAC_MODEL_FORMAT_ID_GGML = 2u,
    RAC_MODEL_FORMAT_ID_ONNX = 3u,
    RAC_MODEL_FORMAT_ID_ORT = 4u,
    RAC_MODEL_FORMAT_ID_BIN = 5u,
    RAC_MODEL_FORMAT_ID_COREML = 6u,
    RAC_MODEL_FORMAT_ID_MLMODEL = 7u,
    RAC_MODEL_FORMAT_ID_MLPACKAGE = 8u,
    RAC_MODEL_FORMAT_ID_TFLITE = 9u,
    RAC_MODEL_FORMAT_ID_SAFETENSORS = 10u,
    RAC_MODEL_FORMAT_ID_QNN_CONTEXT = 11u,
    RAC_MODEL_FORMAT_ID_ZIP = 12u,
    RAC_MODEL_FORMAT_ID_FOLDER = 13u,
    RAC_MODEL_FORMAT_ID_PROPRIETARY = 14u,
    RAC_MODEL_FORMAT_ID_UNKNOWN = 15u,
} rac_model_format_id_t;

static inline uint32_t rac_model_format_id_value(rac_model_format_id_t id) {
    return (uint32_t)id;
}

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_MODEL_FORMAT_IDS_H */
