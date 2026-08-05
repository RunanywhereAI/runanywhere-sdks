/**
 * @file rac_plugin_entry_neurt.h
 * @brief Public declaration of the `neurt` engine unified-ABI plugin entry.
 *
 * Apple-only engine named for the RUNTIME THAT IMPLEMENTS IT (NeuRT, the Apple
 * half of the sibling `neurun` repo), not for a modality and not for Apple's
 * framework — mirrors the `cloud` engine. It serves GENERATE_TEXT on the Apple
 * Neural Engine and DIFFUSION over CoreML MLModel; further modalities (VLM /
 * embeddings) attach by filling more vtable op-tables. Consumers register it
 * either by calling the entry below manually, or by using
 * `RAC_STATIC_PLUGIN_REGISTER(neurt)` in a bootstrap TU. Dynamic (dlopen) hosts
 * load `librunanywhere_neurt.{dylib,so}` via `rac_registry_load_plugin()`.
 *
 * Renamed from `coreml` when NeuRT became the implementation. The library
 * filename, this entry symbol and the manifest `.name` are derived from one
 * another (see plugin_loader.cpp::entry_symbol_from_path) and must always move
 * together.
 */

#ifndef RAC_PLUGIN_ENTRY_NEURT_H
#define RAC_PLUGIN_ENTRY_NEURT_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for the neurt engine (ANE LLM + diffusion).
 */
RAC_PLUGIN_ENTRY_DECL(neurt);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_NEURT_H */
