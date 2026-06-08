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
#include "rac/infrastructure/events/rac_events.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

namespace rac::vad {

namespace {
const char* LOG_CAT = "VAD.Service";
}  // namespace

rac_result_t create_model_vad_service(const char* model_path, rac_vad_service_t** out_service) {
    if (!out_service) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_service = nullptr;

    // Pick the highest-priority plugin that serves DETECT_VOICE (priority
    // assigned at backend registration; no hardware/format scoring). onnx_vad
    // wins for model-based VAD; energy VAD is not plugin-registered since it's
    // not a full ops-based engine.
    const rac_engine_vtable_t* vt = rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE);
    if (!vt || !vt->vad_ops || !vt->vad_ops->create) {
        RAC_LOG_ERROR(LOG_CAT, "no registered plugin serves DETECT_VOICE");
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(LOG_CAT, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    rac_result_t result = vt->vad_ops->create(model_path, /*config_json=*/nullptr, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(LOG_CAT, "Plugin create failed for VAD");
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<rac_vad_service_t*>(malloc(sizeof(rac_vad_service_t)));
    if (!service) {
        if (vt->vad_ops->destroy)
            vt->vad_ops->destroy(impl);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    service->ops = vt->vad_ops;
    service->impl = impl;
    service->model_id = model_path ? strdup(model_path) : nullptr;
    *out_service = service;

    // Single source of truth for the "*.backend.created" telemetry
    // event. Previously each backend fired this from its own *_create path;
    // now it fires once from the commons service layer so future backends
    // inherit the emit for free (and can't silently drop it).
    {
        const char* backend_name = vt->metadata.name ? vt->metadata.name : "unknown";
        char props[128];
        snprintf(props, sizeof(props), R"({"backend":"%s"})", backend_name);
        rac_event_track("vad.backend.created", RAC_EVENT_CATEGORY_VOICE, RAC_EVENT_DESTINATION_ALL,
                        props);
    }

    return RAC_SUCCESS;
}

}  // namespace rac::vad
