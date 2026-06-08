/**
 * @file rac_vad_service.cpp
 * @brief VAD Service - model-backed service creation (Component + Service split)
 *
 * Service layer for the VAD feature, mirroring rac_stt_service.cpp. Owns the
 * model-VAD service-creation factory: it resolves the highest-priority plugin
 * serving the DETECT_VOICE primitive, creates the backend impl, wraps it in a
 * rac_vad_service_t, and fires the "vad.backend.created" telemetry once from the
 * commons service layer (single source of truth, so future backends inherit it).
 *
 * The public rac_vad_* struct API in rac/features/vad/rac_vad_service.h is
 * `delete after SDK migration` dead surface (never implemented) — the canonical
 * surface is the proto/component ABI in vad_module.cpp — so no generic
 * vtable-dispatch wrappers live here; there are none to relocate. The VAD
 * component (vad_module.cpp) still owns both the energy-VAD fallback and the
 * model service produced here, and selects model-first / energy-fallback at
 * process time.
 */

#include "rac_vad_service_internal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_logger.h"
#include "../common/rac_service_factory_internal.h"

namespace rac::vad {

namespace {
const char* LOG_CAT = "VAD.Service";

const rac_vad_service_ops_t* vad_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->vad_ops : nullptr;
}

}  // namespace

rac_result_t create_model_vad_service(const char* model_path, rac_vad_service_t** out_service) {
    if (!out_service) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_service = nullptr;

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result = rac::features::resolve_model_reference(
        model_path,
        {.log_cat = LOG_CAT,
         .default_framework = RAC_FRAMEWORK_ONNX,
         .allow_null_model_id = false,
         .lookup_last_path_component = true,
         .prefer_input_path_when_contains = nullptr},
        &model_ref);
    if (result != RAC_SUCCESS) {
        return result;
    }

    return rac::features::create_plugin_service<rac_vad_service_t, rac_vad_service_ops_t>(
        {.log_cat = LOG_CAT,
         .primitive = RAC_PRIMITIVE_DETECT_VOICE,
         .select_ops = vad_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = model_path,
         .config_json = nullptr,
         .created_event_name = "vad.backend.created",
         .created_event_category = RAC_EVENT_CATEGORY_VOICE},
        out_service);
}

}  // namespace rac::vad
