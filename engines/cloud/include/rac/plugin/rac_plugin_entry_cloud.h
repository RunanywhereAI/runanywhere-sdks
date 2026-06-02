/**
 * @file rac_plugin_entry_cloud.h
 * @brief Public declaration of the generic cloud unified-ABI plugin entry.
 *
 * The cloud engine fronts one or more HTTP providers with no local compute
 * substrate. It serves STT today (RAC_PRIMITIVE_TRANSCRIBE) via its STT-modality
 * ops; future modalities (TTS / LLM / embeddings) plug in by filling the
 * corresponding ops slots in the engine vtable. It publishes a single `"cloud"`
 * engine plugin so it becomes routable via
 * `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, …, hint="cloud")` — exactly the
 * same registry path as the in-tree sherpa STT plugin. Callers pick the provider
 * via the create config (`{"provider":"sarvam"}`).
 *
 * Like onnx / llamacpp / sherpa, the engine registers via the explicit-register
 * + static-shim pattern: dynamic-linkage hosts call `rac_backend_cloud_register()`
 * from the SDK bridge; static-linkage hosts (iOS / WASM, RAC_STATIC_PLUGINS=ON)
 * route through it via `RAC_STATIC_REGISTER_BACKEND(cloud)` expanded from
 * rac_static_register_cloud.cpp.
 */
#ifndef RAC_PLUGIN_ENTRY_CLOUD_H
#define RAC_PLUGIN_ENTRY_CLOUD_H

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for the generic cloud backend (TRANSCRIBE today).
 */
RAC_PLUGIN_ENTRY_DECL(cloud);

/**
 * @brief Explicit backend registration. Registers the unified plugin vtable
 *        with the plugin registry. Idempotent: subsequent calls return
 *        RAC_ERROR_MODULE_ALREADY_REGISTERED.
 *
 * Dynamic-linkage hosts (Android, Linux, macOS dev) call this from the SDK
 * bridge. Static-linkage hosts (iOS / WASM, RAC_STATIC_PLUGINS=ON) also route
 * through this function when RAC_STATIC_REGISTER_BACKEND(cloud) fires; see
 * rac_static_register_cloud.cpp.
 */
rac_result_t rac_backend_cloud_register(void);

/**
 * @brief Reverse of rac_backend_cloud_register().
 */
rac_result_t rac_backend_cloud_unregister(void);

#ifdef __cplusplus
}
#endif
#endif  // RAC_PLUGIN_ENTRY_CLOUD_H
