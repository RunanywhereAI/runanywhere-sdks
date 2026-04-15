/**
 * @file rac_backend_metalrt.h
 * @brief RunAnywhere Commons - MetalRT Backend Registration
 *
 * Public header for the MetalRT backend. MetalRT provides high-performance
 * LLM, STT, TTS, and VLM inference using custom Metal GPU kernels on Apple
 * silicon. This backend handles models registered with RAC_FRAMEWORK_METALRT.
 *
 * Apple-only (iOS/macOS).
 */

#ifndef RAC_BACKEND_METALRT_H
#define RAC_BACKEND_METALRT_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// EXPORT MACRO
// =============================================================================

#if defined(RAC_METALRT_BUILDING)
#if defined(__GNUC__) || defined(__clang__)
#define RAC_METALRT_API __attribute__((visibility("default")))
#else
#define RAC_METALRT_API
#endif
#else
#define RAC_METALRT_API
#endif

// =============================================================================
// BACKEND REGISTRATION
// =============================================================================

/**
 * Registers the MetalRT backend with the commons module and service registries.
 *
 * Registers providers for:
 * - LLM (TEXT_GENERATION) — metalrt_generate / metalrt_generate_stream
 * - STT (SPEECH_RECOGNITION) — metalrt_whisper_transcribe
 * - TTS (TEXT_TO_SPEECH) — metalrt_tts_synthesize
 * - VLM (VISION_LANGUAGE) — metalrt_vision_analyze
 *
 * Should be called once during SDK initialization.
 * Only handles models with RAC_FRAMEWORK_METALRT framework hint.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_METALRT_API RAC_NODISCARD rac_result_t rac_backend_metalrt_register(void);

/**
 * Unregisters the MetalRT backend.
 *
 * @return RAC_SUCCESS or error code
 */
RAC_METALRT_API RAC_NODISCARD rac_result_t rac_backend_metalrt_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BACKEND_METALRT_H */
