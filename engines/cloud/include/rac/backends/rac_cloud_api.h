/**
 * @file rac_cloud_api.h
 * @brief Export/import decoration for symbols the cloud engine publishes to its
 *        thin carrier.
 *
 * Peer of RAC_ONNX_API (engines/onnx/rac_onnx_api.h) and RAC_LLAMACPP_API.
 *
 * When building rac_backend_cloud: dllexport / default visibility.
 * When the thin runanywhere_cloud carrier links that DLL on Windows: dllimport
 * — MANDATORY for the DATA symbol g_cloud_stt_ops, because MSVC cannot fix up a
 * cross-image data reference the way it can synthesize a function thunk.
 * RAC_USING_SHARED is the INTERFACE define from shared rac_commons.
 *
 * RAC_CLOUD_BUILDING must therefore be set on rac_backend_cloud ONLY — never on
 * runanywhere_cloud, which has to see the dllimport side.
 *
 * This lives under include/ rather than beside the sources, where
 * rac_onnx_api.h sits, because the carrier target's include path is
 * engines/cloud/include only; a header at the engine root would be invisible to
 * exactly the target that needs the dllimport side.
 */

#ifndef RAC_CLOUD_API_H
#define RAC_CLOUD_API_H

#if defined(RAC_CLOUD_BUILDING)
#if defined(_WIN32)
#define RAC_CLOUD_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RAC_CLOUD_API __attribute__((visibility("default")))
#else
#define RAC_CLOUD_API
#endif
#elif defined(_WIN32) && defined(RAC_USING_SHARED)
#define RAC_CLOUD_API __declspec(dllimport)
#else
#define RAC_CLOUD_API
#endif

#endif /* RAC_CLOUD_API_H */
