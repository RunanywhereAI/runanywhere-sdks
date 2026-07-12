/**
 * @file rac_platform_capabilities.h
 * @brief Platform capability boundary for inference frameworks.
 *
 * Canonical, compile-time matrix of which inference frameworks can ever run
 * on the platform this library was built for. This is THE cross-platform
 * boundary: every SDK (Swift, Kotlin, Flutter, React Native, Web) inherits it
 * through the registry list paths, so example apps never need to hide
 * platform-impossible models themselves.
 *
 * Matrix (compile-time, by build target):
 *   - Apple-only frameworks — MLX, FOUNDATION_MODELS, COREML,
 *     SWIFT_TRANSFORMERS, FLUID_AUDIO — are supported only on Apple targets
 *     (iOS, macOS, and friends).
 *   - Qualcomm-Android-only — QHEXRT — is supported only on Android targets.
 *   - Everything else (LLAMA_CPP, ONNX, SHERPA, SYSTEM_TTS, BUILT_IN, cloud,
 *     ...) is available everywhere and is never restricted.
 *   - WASM/Emscripten, desktop Linux, and Windows exclude both restricted
 *     sets; desktop macOS behaves as Apple.
 */

#ifndef RAC_PLATFORM_CAPABILITIES_H
#define RAC_PLATFORM_CAPABILITIES_H

#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Check whether an inference framework can ever run on this platform.
 *
 * The decision is made at compile time from the build target (Apple /
 * Android / everything else) — it is a hard platform boundary, not a
 * runtime-availability probe (it does not check whether the corresponding
 * backend plugin is actually registered or the device has the hardware).
 *
 * Model registry list/query entry points use this to hide models whose
 * framework can never run here; get-by-id, registration, and download paths
 * are intentionally NOT filtered.
 *
 * @param inference_framework Wire value of the runanywhere.v1.InferenceFramework
 *                            proto enum (see idl/model_types.proto), e.g.
 *                            INFERENCE_FRAMEWORK_MLX = 7.
 * @return RAC_TRUE if the framework is supported on the platform this library
 *         was compiled for (unknown/unspecified values default to RAC_TRUE),
 *         RAC_FALSE otherwise.
 */
RAC_API rac_bool_t rac_framework_supported_on_platform(int32_t inference_framework);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLATFORM_CAPABILITIES_H */
