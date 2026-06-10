/**
 * @file rac_plugin_entry_cloud.h
 * @brief cloud unified-ABI engine plugin registration (Swift bridge copy).
 *
 * Mirrors engines/cloud/include/rac/plugin/rac_plugin_entry_cloud.h so
 * the Swift SDK can register the generic cloud engine's unified-ABI plugin
 * (RAC_PRIMITIVE_TRANSCRIBE → an HTTP STT provider, Sarvam first) with the
 * commons plugin registry, exactly as ONNX.register() does for sherpa. The
 * concrete provider is chosen via the create config (`{"provider":"sarvam"}`),
 * not by a distinct plugin. Only the two registration symbols Swift calls from
 * `Cloud.register()` are declared here — the engine vtable + STT factory
 * stay private to the engine.
 *
 * Linkage note: the cloud engine (engines/cloud) registers via the
 * explicit-register + static-shim pattern. Dynamic-linkage hosts call
 * `rac_backend_cloud_register()` from this SDK bridge; static-linkage hosts
 * (iOS / WASM, RAC_STATIC_PLUGINS=ON) route through it via
 * RAC_STATIC_REGISTER_BACKEND(cloud). The engine is folded into the iOS
 * commons static-plugin archive (RACommons.xcframework) alongside
 * sherpa/onnx/llamacpp, so `rac_backend_cloud_register` resolves from the
 * shipped Apple binaries. This header lets the Swift binding compile +
 * typecheck against the symbol. See Cloud.register() for the runtime guard.
 */
#ifndef RAC_PLUGIN_ENTRY_CLOUD_H
#define RAC_PLUGIN_ENTRY_CLOUD_H

#include "rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Explicit cloud backend registration. Registers the unified plugin
 *        vtable with the plugin registry. Idempotent: subsequent calls return
 *        RAC_ERROR_MODULE_ALREADY_REGISTERED.
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
