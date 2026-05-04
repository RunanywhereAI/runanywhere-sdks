/**
 * @file rac_plugin_entry_llamacpp.h
 * @brief Public declaration of the llama.cpp unified-ABI plugin entry points.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Consumers that want to register llama.cpp via the unified plugin registry
 * include this header and call either entry point manually, or use
 * `RAC_STATIC_PLUGIN_REGISTER(llamacpp)` in their bootstrap TU.
 */

#ifndef RAC_PLUGIN_ENTRY_LLAMACPP_H
#define RAC_PLUGIN_ENTRY_LLAMACPP_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for llama.cpp text generation (LLM).
 */
RAC_PLUGIN_ENTRY_DECL(llamacpp);

/**
 * @brief Returns the engine vtable for llama.cpp vision-language models (VLM).
 */
RAC_PLUGIN_ENTRY_DECL(llamacpp_vlm);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_LLAMACPP_H */
