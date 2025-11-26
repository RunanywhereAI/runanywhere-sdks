#ifndef RUNANYWHERE_TYPES_H
#define RUNANYWHERE_TYPES_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle types for backends
typedef void* ra_onnx_handle;
typedef void* ra_llamacpp_handle;
typedef void* ra_coreml_handle;
typedef void* ra_tflite_handle;

// Common result codes
typedef enum {
    RA_SUCCESS = 0,
    RA_ERROR_INIT_FAILED = -1,
    RA_ERROR_MODEL_LOAD_FAILED = -2,
    RA_ERROR_INFERENCE_FAILED = -3,
    RA_ERROR_INVALID_HANDLE = -4,
    RA_ERROR_INVALID_PARAMS = -5,
    RA_ERROR_OUT_OF_MEMORY = -6,
    RA_ERROR_NOT_IMPLEMENTED = -7,
    RA_ERROR_UNKNOWN = -99
} ra_result_code;

// Device types
typedef enum {
    RA_DEVICE_CPU = 0,
    RA_DEVICE_GPU = 1,
    RA_DEVICE_NEURAL_ENGINE = 2,
    RA_DEVICE_METAL = 3,
    RA_DEVICE_CUDA = 4,
    RA_DEVICE_NNAPI = 5,
    RA_DEVICE_UNKNOWN = 99
} ra_device_type;

#ifdef __cplusplus
}
#endif

#endif // RUNANYWHERE_TYPES_H
