/**
 * @file rac_vad_onnx.h
 * @brief ONNX backend registration (STT + TTS + VAD unified bundle).
 *
 * Trimmed down from a 166-line duplicate of the commons header to just the
 * two registration symbols Swift actually calls from `ONNX.swift` (per
 * swift.md SWIFT-DUP-RUNTIME-HEADERS). Common types (rac_result_t etc.)
 * come from the CRACommons module this target now depends on.
 */
#ifndef RAC_VAD_ONNX_H
#define RAC_VAD_ONNX_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Registers the ONNX backend with the commons module and service registries.
 * Should be called once during SDK initialization. Registers:
 *   - Module: "onnx" with STT, TTS, VAD capabilities.
 *   - Service providers for STT, TTS, VAD.
 */
rac_result_t rac_backend_onnx_register(void);

/** Unregisters the ONNX backend. */
rac_result_t rac_backend_onnx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ONNX_H */
