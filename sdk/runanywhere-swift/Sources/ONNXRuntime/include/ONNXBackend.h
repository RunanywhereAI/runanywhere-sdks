/**
 * @file ONNXBackend.h
 * @brief Umbrella header for ONNX backend C APIs
 *
 * This header exposes the ONNX backend C APIs to Swift.
 * Part of the unified ONNXRuntime module.
 */

#ifndef ONNX_BACKEND_H
#define ONNX_BACKEND_H

// ONNX backend: the two registration calls (rac_backend_onnx_register /
// rac_backend_onnx_unregister) live in rac_vad_onnx.h for legacy reasons
// (the registration was originally in the VAD header). The old
// rac_stt_onnx.h / rac_tts_onnx.h declared low-level C APIs Swift never
// called — deleted per swift.md SWIFT-DUP-RUNTIME-HEADERS. Common types
// come from CRACommons which this target now depends on.
#include "rac_vad_onnx.h"

// Sherpa-ONNX backend plugin entry (STT / TTS / VAD via Sherpa-ONNX).
// Needed so `ONNX.register()` can register the sherpa plugin with the
// unified plugin registry via `rac_plugin_register(rac_plugin_entry_sherpa())`.
#include "rac_plugin_entry_sherpa.h"

#endif /* ONNX_BACKEND_H */
