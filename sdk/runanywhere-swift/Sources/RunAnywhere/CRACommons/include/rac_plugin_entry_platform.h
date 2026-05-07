/**
 * @file rac_plugin_entry_platform.h
 * @brief Apple platform engine plugin entry declaration (Swift bridge copy).
 *
 * Mirrors the in-tree commons declaration so the Swift SDK can register the
 * platform engine's unified-ABI vtable with the plugin registry. The commons
 * shipped in RACommons.xcframework defines `rac_plugin_entry_platform()` and
 * compiles the platform plugin's vtable + primitive ops (LLM /
 * Foundation Models, TTS / AVSpeechSynthesizer, Diffusion / CoreML), but
 * `rac_backend_platform_register()` only wires the module record and the
 * built-in catalog entries — it does NOT call `rac_plugin_register()` on the
 * platform vtable. Without that call the unified plugin router has no entry
 * for `framework == .foundationModels` / `.systemTts` / `.coreml`, so
 * `RunAnywhere.loadModel(...)` returns "no backend route".
 *
 * Phase 5b fix: `CppBridge.Platform.register()` now calls
 * `rac_plugin_register(rac_plugin_entry_platform())` right after
 * `rac_backend_platform_register()`, symmetric to the llamacpp / onnx /
 * sherpa plugin registration paths.
 */
#ifndef RAC_PLUGIN_ENTRY_PLATFORM_H
#define RAC_PLUGIN_ENTRY_PLATFORM_H

#ifdef __cplusplus
extern "C" {
#endif

/* Forward-declare the engine vtable as opaque. The caller casts the returned
 * pointer to `rac_engine_vtable_t*` (imported from rac_engine_vtable.h in
 * this same module) via `withMemoryRebound` before handing it to
 * `rac_plugin_register()`. */
struct rac_engine_vtable;

/**
 * @brief Returns the engine vtable for the Apple platform backend.
 *        Linked from RACommons.xcframework. Safe to call multiple times;
 *        returns the same static pointer.
 */
const struct rac_engine_vtable* rac_plugin_entry_platform(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_PLATFORM_H */
