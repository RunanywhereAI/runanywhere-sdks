/**
 * @file rac_plugin_entry_coreml.h
 * @brief Public declaration of the `coreml` engine unified-ABI plugin entry.
 *
 * Apple-only engine that runs ON Apple CoreML. Named by the FRAMEWORK it
 * targets (`coreml`), not the modality — mirrors the `cloud` engine. Serves the
 * DIFFUSION modality today (Stable Diffusion via MLModel); future CoreML
 * modalities (VLM / embeddings / LLM) attach by filling more vtable op-tables.
 * Consumers register it either by calling the entry below manually, or by using
 * `RAC_STATIC_PLUGIN_REGISTER(coreml)` in a bootstrap TU. Dynamic (dlopen) hosts
 * load `librunanywhere_coreml.{dylib,so}` via `rac_registry_load_plugin()`.
 */

#ifndef RAC_PLUGIN_ENTRY_COREML_H
#define RAC_PLUGIN_ENTRY_COREML_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for the coreml engine (DIFFUSION today).
 */
RAC_PLUGIN_ENTRY_DECL(coreml);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_COREML_H */
