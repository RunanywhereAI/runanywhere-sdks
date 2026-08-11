/**
 * @file rac_plugin_entry_neurt.h
 * @brief NeuRT (Apple Neural Engine) engine plugin entry declaration
 *        (Swift bridge copy).
 *
 * Mirrors core/include/rac/plugin/rac_plugin_entry_neurt.h
 * so the Swift SDK can register the neurt engine's unified-ABI vtable with the
 * plugin registry without pulling the commons private plugin headers into the
 * CRACommons module map.
 *
 * The shipped RABackendNeuRT.xcframework exports only `rac_plugin_entry_neurt`
 * (the `rac_backend_neurt_register` wrapper is not re-exported), so
 * `NeuRT.register()` calls `rac_plugin_register(rac_plugin_entry_neurt())`
 * directly — the same pattern ONNXRuntime uses for Sherpa.
 */
#ifndef RAC_PLUGIN_ENTRY_NEURT_H
#define RAC_PLUGIN_ENTRY_NEURT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Forward-declare the engine vtable struct. Swift treats this as an opaque
 * pointer inside the NeuRTBackend module and casts to
 * `UnsafePointer<rac_engine_vtable_t>` (imported from CRACommons) via
 * `withMemoryRebound` before handing it to `rac_plugin_register()`. A plain
 * forward declaration (rather than #include'ing the commons plugin header)
 * avoids pulling internal plugin types into the Swift module map twice. */
struct rac_engine_vtable;

/**
 * @brief Returns the engine vtable for the neurt engine (ANE LLM + CoreML
 *        diffusion). Linked from RABackendNeuRT.xcframework. Safe to call
 *        multiple times; returns the same static pointer.
 */
const struct rac_engine_vtable* rac_plugin_entry_neurt(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_NEURT_H */
