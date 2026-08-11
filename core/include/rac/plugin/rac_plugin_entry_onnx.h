/**
 * @file rac_plugin_entry_onnx.h
 * @brief Public declaration of the ONNX Runtime unified-ABI plugin entry point.
 */
#ifndef RAC_PLUGIN_ENTRY_ONNX_H
#define RAC_PLUGIN_ENTRY_ONNX_H

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_PLUGIN_ENTRY_DECL(onnx);

/** Register the generic ONNX Runtime engine with the plugin registry. */
rac_result_t rac_backend_onnx_register(void);

/** Unregister the generic ONNX Runtime engine. */
rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif
#endif
