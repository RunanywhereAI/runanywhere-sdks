/**
 * @file rac_plugin_entry_sherpa.h
 * @brief Public declaration of the Sherpa-ONNX unified-ABI plugin entry point.
 *
 * The sherpa engine previously registered itself via an ELF
 * `__attribute__((constructor))` emitted at the bottom of
 * rac_plugin_entry_sherpa.cpp. That constructor has been deleted in favor of
 * the explicit-register + static-shim pattern already used by llamacpp and
 * onnx. Consumers now either call `rac_backend_sherpa_register()` explicitly
 * or rely on `RAC_STATIC_PLUGIN_REGISTER(sherpa)` expanded from
 * rac_static_register_sherpa.cpp.
 */
#ifndef RAC_PLUGIN_ENTRY_SHERPA_H
#define RAC_PLUGIN_ENTRY_SHERPA_H

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Returns the engine vtable for the Sherpa-ONNX backend (STT / TTS / VAD).
 */
RAC_PLUGIN_ENTRY_DECL(sherpa);

/**
 * @brief Explicit backend registration. Registers the module record and the
 *        unified plugin vtable with the plugin registry. Safe to call once;
 *        subsequent calls return RAC_ERROR_MODULE_ALREADY_REGISTERED.
 *
 * Dynamic-linkage hosts (Android, Linux, macOS dev) call this from the SDK
 * bridge. Static-linkage hosts (iOS / WASM, RAC_STATIC_PLUGINS=ON) also route
 * through this function when RAC_STATIC_PLUGIN_REGISTER(sherpa) fires; see
 * rac_static_register_sherpa.cpp.
 */
rac_result_t rac_backend_sherpa_register(void);

/**
 * @brief Reverse of rac_backend_sherpa_register().
 */
rac_result_t rac_backend_sherpa_unregister(void);

#ifdef __cplusplus
}
#endif
#endif
