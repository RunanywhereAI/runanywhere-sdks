/**
 * @file rac_onnx_api.h
 * @brief Export/import decoration for symbols the ONNX engine publishes to its
 *        thin carrier.
 *
 * Peer of RAC_LLAMACPP_API in core/include/rac/backends/rac_llm_llamacpp.h.
 *
 * When building rac_backend_onnx.dll: dllexport / default visibility.
 * When a shared consumer (the thin runanywhere_onnx carrier, JNI, tests) links
 * that DLL on Windows: dllimport — MANDATORY for DATA symbols such as
 * g_onnx_{embeddings,segmentation,diarization}_ops, because MSVC cannot fix up
 * a cross-image data reference the way it can synthesize a function thunk.
 * RAC_USING_SHARED is the INTERFACE define from shared rac_commons (the
 * electron / desktop presets).
 *
 * RAC_ONNX_BUILDING must therefore be set on rac_backend_onnx ONLY — never on
 * the carrier, which has to see the dllimport side.
 */

#ifndef RAC_ONNX_API_H
#define RAC_ONNX_API_H

#if defined(RAC_ONNX_BUILDING)
#if defined(_WIN32)
#define RAC_ONNX_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_ONNX_API __attribute__((visibility("default")))
#else
#define RAC_ONNX_API
#endif
#elif defined(_WIN32) && defined(RAC_USING_SHARED)
#define RAC_ONNX_API __declspec(dllimport)
#else
#define RAC_ONNX_API
#endif

#endif /* RAC_ONNX_API_H */
