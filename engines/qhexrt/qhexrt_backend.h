#ifndef RUNANYWHERE_QHEXRT_BACKEND_H
#define RUNANYWHERE_QHEXRT_BACKEND_H

/**
 * @file qhexrt_backend.h
 * @brief Shell header for the QHexRT (Qualcomm Hexagon NPU runtime) engine plugin.
 *
 * QHexRT is a PRIVATE, closed-source C++ runtime that runs prebuilt QNN context
 * binaries on Snapdragon Hexagon NPUs (HTP). QHexRT is the RunAnywhere-owned
 * NPU runtime routed today for LLM, VLM, ASR/STT, TTS, embeddings, and image
 * restoration/inpaint workloads.
 *
 * ### How this plugin stays private
 *
 * The QHexRT source never enters this repo. The SDK consumes a prebuilt static
 * archive (`libqhexrt_core.a` + `libqhexrt_host.a`) plus a single ABI-stable C
 * header (`qhexrt/qhexrt_c.h`) discovered through `QHEXRT_ROOT` (defaults to
 * the atomically selected `engines/qhexrt/prebuilt/current`, which is
 * gitignored). The archives are linked
 * *into* the plugin `.so` so there is no separately-shippable QHexRT binary and
 * the runtime symbols are internal to the carrier library.
 *
 * Two build modes:
 *
 *   - Engine NOT available (default / public): `RAC_QHEXRT_ENGINE_AVAILABLE=0`.
 *     The plugin compiles to a not-routable shell that rejects registration
 *     with RAC_ERROR_BACKEND_UNAVAILABLE; no QHexRT header/lib is needed.
 *   - Engine IS available (internal / authorized): `RAC_QHEXRT_ENGINE_AVAILABLE=1`
 *     with the prebuilt archive present. The plugin links QHexRT and publishes
 *     a routable vtable exposing the supported text, vision, speech, embedding,
 *     and image-generation/restoration primitives.
 *
 * ### QHexRT C ABI brief (from qhexrt/qhexrt_c.h — present only in linked builds)
 *
 *   qhx_runtime* qhx_runtime_create(htp, system);          // one per process
 *   qhx_model*   qhx_model_load(rt, manifest_path, dir);   // load a model manifest
 *   qhx_session* qhx_session_create(model);                // one per stream
 *   qhx_status   qhx_generate(sess, inputs, cfg, cb, user, out);
 *
 * No C++ types or exceptions cross that boundary; every error is a qhx_status.
 */

#include "rac/qhexrt/rac_qhexrt.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Marker returned by qhexrt_backend_build_info().
 *
 * Lets tests assert the engine compiled against the expected QHexRT visibility
 * without pulling the private QHexRT header.
 */
const char* qhexrt_backend_build_info(void);

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_QHEXRT_BACKEND_H
