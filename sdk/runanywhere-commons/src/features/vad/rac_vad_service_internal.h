/**
 * @file rac_vad_service_internal.h
 * @brief Internal VAD service-creation factory (Component + Service split).
 *
 * NOT part of the public C ABI; only `vad_module.cpp` (the VAD component) may
 * include this header.
 *
 * Gives VAD the same Component+Service split STT/TTS already have. The
 * public `rac_vad_*` struct API declared in `rac/features/vad/rac_vad_service.h`
 * is `delete after SDK migration` dead surface (never implemented), and its
 * `rac_vad_create(rac_handle_t*)` signature has no model-path parameter. So the
 * model-VAD service factory lives here as an internal helper instead, mirroring
 * the structure of `rac_stt_create` (registry lookup → null-check vad_ops →
 * create → wrap in rac_vad_service_t → "vad.backend.created" telemetry) without
 * resurrecting any dead public symbol.
 *
 * The VAD component (`vad_module.cpp`) still owns BOTH services — the built-in
 * energy VAD fallback and the model service produced here — and chooses
 * model-first / energy-fallback at process time. Only the model-service
 * *creation* moved into this service layer.
 */

#ifndef RAC_FEATURES_VAD_RAC_VAD_SERVICE_INTERNAL_H
#define RAC_FEATURES_VAD_RAC_VAD_SERVICE_INTERNAL_H

#include "rac/core/rac_error.h"
#include "rac/features/vad/rac_vad_service.h"

namespace rac::vad {

/**
 * @brief Create a model-backed VAD service from the highest-priority plugin
 *        that serves the DETECT_VOICE primitive.
 *
 * Mirrors `rac_stt_create`: resolves the plugin via
 * `rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE)`, null-checks `vad_ops->create`,
 * invokes it, wraps the backend impl in a heap `rac_vad_service_t`
 * (`ops`/`impl`/`model_id`), and fires the single-source-of-truth
 * "vad.backend.created" telemetry event. The returned service does NOT start
 * the backend — the caller owns lifecycle (start/stop) and ownership of the
 * returned struct (free via the component's existing teardown path).
 *
 * @param model_path Path/ID passed to the backend's create + stored as model_id.
 * @param out_service Output: heap-allocated service on RAC_SUCCESS, else nullptr.
 * @return RAC_SUCCESS, RAC_ERROR_BACKEND_NOT_FOUND when no plugin serves
 *         DETECT_VOICE, the backend's error, RAC_ERROR_BACKEND_NOT_READY, or
 *         RAC_ERROR_OUT_OF_MEMORY.
 */
rac_result_t create_model_vad_service(const char* model_path, rac_vad_service_t** out_service);

}  // namespace rac::vad

#endif  // RAC_FEATURES_VAD_RAC_VAD_SERVICE_INTERNAL_H
