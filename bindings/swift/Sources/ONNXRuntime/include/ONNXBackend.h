/**
 * @file ONNXBackend.h
 * @brief Umbrella header for ONNX backend C APIs
 *
 * This header exposes the ONNX backend C APIs to Swift.
 * Part of the unified ONNXRuntime module.
 */

#ifndef ONNX_BACKEND_H
#define ONNX_BACKEND_H

// Generic ONNX backend registration (embeddings).
#include "rac_plugin_entry_onnx.h"

// Sherpa-ONNX backend plugin entry (STT / TTS / VAD via Sherpa-ONNX).
// Needed so `ONNX.register()` can register the sherpa plugin with the
// unified plugin registry via `rac_plugin_register(rac_plugin_entry_sherpa())`.
#include "rac_plugin_entry_sherpa.h"

#endif /* ONNX_BACKEND_H */
