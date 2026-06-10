/**
 * @file rac_plugin_entry_sherpa.h
 * @brief Sherpa-ONNX engine plugin entry declaration (Swift bridge copy).
 *
 * Mirrors sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry_sherpa.h
 * so the Swift SDK can register the sherpa engine's unified-ABI vtable with
 * the plugin registry without pulling the commons private plugin headers
 * into the CRACommons module map.
 *
 * Phase 5b (Swift-only E2E): the Swift SDK ships sherpa's STT/TTS/VAD vtable
 * in RABackendSherpa.xcframework, but only `rac_plugin_entry_sherpa` is
 * exported from that archive. The registration wrapper
 * `rac_backend_sherpa_register` is not re-exported, so we route around it
 * and call `rac_plugin_register(rac_plugin_entry_sherpa())` directly from
 * `ONNX.register()` at SDK boot. This plumbs the `sherpa` plugin so STT /
 * TTS / VAD model loads where `framework == .sherpa` can actually resolve.
 */
#ifndef RAC_PLUGIN_ENTRY_SHERPA_H
#define RAC_PLUGIN_ENTRY_SHERPA_H

#ifdef __cplusplus
extern "C" {
#endif

/* Forward-declare the engine vtable struct. Swift treats this as an opaque
 * pointer inside the ONNXBackend module. Callers cast to
 * `UnsafePointer<rac_engine_vtable_t>` (imported from CRACommons) via
 * `withMemoryRebound` before handing it to `rac_plugin_register()`. Using a
 * plain forward declaration (rather than #include'ing the commons plugin
 * header) avoids pulling internal plugin types into the Swift module map
 * twice. */
struct rac_engine_vtable;

/**
 * @brief Returns the engine vtable for the Sherpa-ONNX backend (STT / TTS /
 *        VAD). Linked from RABackendSherpa.xcframework. Safe to call multiple
 *        times; returns the same static pointer.
 */
const struct rac_engine_vtable* rac_plugin_entry_sherpa(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_SHERPA_H */
