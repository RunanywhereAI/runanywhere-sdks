/**
 * @file rac_plugin_entry_llamacpp.h
 * @brief Public declaration of the llama.cpp unified-ABI plugin entry point.
 *
 * llama.cpp is one engine that supports both text generation (LLM) and
 * vision-language (VLM) modalities. A single plugin vtable fills both the
 * `llm_ops` and `vlm_ops` slots; there is one entry point.
 *
 * Consumers that want to register llama.cpp via the unified plugin registry
 * include this header and call `rac_plugin_entry_llamacpp()` manually, or use
 * `RAC_STATIC_PLUGIN_REGISTER(llamacpp)` in their bootstrap TU.
 */

#ifndef RAC_PLUGIN_ENTRY_LLAMACPP_H
#define RAC_PLUGIN_ENTRY_LLAMACPP_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for llama.cpp (both LLM and VLM modalities).
 */
RAC_PLUGIN_ENTRY_DECL(llamacpp);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_LLAMACPP_H */
