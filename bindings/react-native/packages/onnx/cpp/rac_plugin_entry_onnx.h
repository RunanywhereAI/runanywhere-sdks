/**
 * @file rac_plugin_entry_onnx.h
 * @brief ONNX backend registration API for the React Native bridge.
 */
#ifndef RAC_PLUGIN_ENTRY_ONNX_H
#define RAC_PLUGIN_ENTRY_ONNX_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_backend_onnx_register(void);
rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_ONNX_H */
