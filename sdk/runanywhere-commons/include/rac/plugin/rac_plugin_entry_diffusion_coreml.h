/**
 * @file rac_plugin_entry_diffusion_coreml.h
 * @brief Public declaration of the diffusion_coreml unified-ABI plugin entry.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Apple Stable Diffusion / CoreML diffusion backend. Consumers register it
 * either by calling the entry below manually, or by using
 * `RAC_STATIC_PLUGIN_REGISTER(diffusion_coreml)` in a bootstrap TU. Dynamic
 * (dlopen) hosts load `librunanywhere_diffusion_coreml.{dylib,so}` via
 * `rac_registry_load_plugin()`.
 */

#ifndef RAC_PLUGIN_ENTRY_DIFFUSION_COREML_H
#define RAC_PLUGIN_ENTRY_DIFFUSION_COREML_H

#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for Apple CoreML Stable Diffusion.
 */
RAC_PLUGIN_ENTRY_DECL(diffusion_coreml);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_DIFFUSION_COREML_H */
