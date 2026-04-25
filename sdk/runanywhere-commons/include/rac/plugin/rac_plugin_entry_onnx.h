/**
 * @file rac_plugin_entry_onnx.h
 * @brief Public declaration of the ONNX Runtime unified-ABI plugin entry point.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 */
#ifndef RAC_PLUGIN_ENTRY_ONNX_H
#define RAC_PLUGIN_ENTRY_ONNX_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

RAC_PLUGIN_ENTRY_DECL(onnx);

#ifdef __cplusplus
}
#endif
#endif
