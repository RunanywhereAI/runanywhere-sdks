/**
 * @file rac_sherpa_api.h
 * @brief Export/import decoration for symbols the Sherpa engine publishes to
 *        its thin carrier.
 *
 * Peer of RAC_LLAMACPP_API (core/include/rac/backends/rac_llm_llamacpp.h) and
 * RAC_ONNX_API (engines/onnx/rac_onnx_api.h).
 *
 * When building rac_backend_sherpa.dll: dllexport / default visibility.
 * When a shared consumer (the thin runanywhere_sherpa carrier, JNI, tests)
 * links that DLL on Windows: dllimport — MANDATORY for DATA symbols such as
 * g_sherpa_{stt,tts,vad}_ops, because MSVC cannot fix up a cross-image data
 * reference the way it can synthesize a function thunk. RAC_USING_SHARED is
 * the INTERFACE define from shared rac_commons (electron / desktop presets).
 *
 * RAC_SHERPA_BUILDING must therefore be set on rac_backend_sherpa ONLY — never
 * on the carrier, which has to see the dllimport side.
 */

#ifndef RAC_SHERPA_API_H
#define RAC_SHERPA_API_H

#if defined(RAC_SHERPA_BUILDING)
#if defined(_WIN32)
#define RAC_SHERPA_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_SHERPA_API __attribute__((visibility("default")))
#else
#define RAC_SHERPA_API
#endif
#elif defined(_WIN32) && defined(RAC_USING_SHARED)
#define RAC_SHERPA_API __declspec(dllimport)
#else
#define RAC_SHERPA_API
#endif

#endif /* RAC_SHERPA_API_H */
