/**
 * @file rac_vad_onnx.h
 * @brief Backend registration API for ONNX
 *
 * Forward declarations for ONNX backend registration functions.
 * These symbols are exported by RABackendONNX.xcframework.
 */

#ifndef RAC_VAD_ONNX_H
#define RAC_VAD_ONNX_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Register the ONNX backend with the RACommons service registry.
 * @return RAC_SUCCESS on success, RAC_ERROR_MODULE_ALREADY_REGISTERED if already registered
 */
rac_result_t rac_backend_onnx_register(void);

/**
 * Unregister the ONNX backend from the RACommons service registry.
 * @return RAC_SUCCESS on success
 */
rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ONNX_H */
