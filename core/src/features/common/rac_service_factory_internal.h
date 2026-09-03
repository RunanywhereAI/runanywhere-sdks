/**
 * @file rac_service_factory_internal.h
 * @brief Shared internal helpers for feature service construction.
 *
 * Private commons-only utilities for the repeated feature-service path:
 * resolve model reference, select the primitive plugin, create backend impl,
 * wrap it in the feature service struct, and unwind consistently on failure.
 */

#ifndef RAC_FEATURES_COMMON_RAC_SERVICE_FACTORY_INTERNAL_H
#define RAC_FEATURES_COMMON_RAC_SERVICE_FACTORY_INTERNAL_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_engine_ids.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

namespace rac::features {

struct ModelReferenceOptions {
    const char* log_cat;
    rac_inference_framework_t default_framework;
    bool allow_null_model_id;
    bool lookup_last_path_component;
    const char* prefer_input_path_when_contains;
};

struct ModelInfoDeleter {
    void operator()(rac_model_info_t* info) const {
        if (info) {
            rac_model_info_free(info);
        }
    }
};

using ModelInfoPtr = std::unique_ptr<rac_model_info_t, ModelInfoDeleter>;

struct ResolvedModelReference {
    std::string path;
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    rac_result_t registry_result = RAC_ERROR_NOT_FOUND;
    bool found = false;
    ModelInfoPtr model_info;
};

inline rac_result_t resolve_model_reference(const char* model_id,
                                            const ModelReferenceOptions& options,
                                            ResolvedModelReference* out_reference) {
    if (!out_reference) {
        return RAC_ERROR_NULL_POINTER;
    }

    out_reference->path = model_id ? model_id : "";
    out_reference->framework = options.default_framework;
    out_reference->registry_result = RAC_ERROR_NOT_FOUND;
    out_reference->found = false;
    out_reference->model_info.reset();

    if (!model_id) {
        return options.allow_null_model_id ? RAC_SUCCESS : RAC_ERROR_NULL_POINTER;
    }

    rac_model_info_t* raw_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &raw_info);

    if (result != RAC_SUCCESS) {
        RAC_LOG_DEBUG(options.log_cat, "Model not found by ID, trying path lookup: %s", model_id);
        result = rac_get_model_by_path(model_id, &raw_info);
    }

    if (result != RAC_SUCCESS && options.lookup_last_path_component) {
        const char* last_fwd = strrchr(model_id, '/');
        const char* last_bck = strrchr(model_id, '\\');
        const char* last_slash = (last_fwd && last_bck) ? std::max(last_fwd, last_bck)
                                 : last_fwd             ? last_fwd
                                                        : last_bck;
        if (last_slash && last_slash[1] != '\0') {
            const char* extracted_id = last_slash + 1;
            RAC_LOG_DEBUG(options.log_cat, "Trying extracted model ID from path: %s", extracted_id);
            result = rac_get_model(extracted_id, &raw_info);
        }
    }

    out_reference->registry_result = result;
    if (result == RAC_SUCCESS && raw_info) {
        out_reference->found = true;
        out_reference->model_info.reset(raw_info);
        out_reference->framework = raw_info->framework;

        // Empty local_path falls through to the literal model ID, which is
        // not a filesystem path — engines stat() it and fail. Before
        // accepting that, try the canonical on-disk folder for this
        // model/framework and let the artifact resolver recover the primary
        // file (mirrors the lifecycle load path's lazy resolution). Read-only
        // here: the registry self-heal lives once, on the lifecycle path.
        std::string registry_path = (raw_info->local_path && raw_info->local_path[0] != '\0')
                                        ? raw_info->local_path
                                        : model_id;
        if (!raw_info->local_path || raw_info->local_path[0] == '\0') {
            char canonical_folder[1024] = {0};
            if (rac_model_paths_get_model_folder(model_id, raw_info->framework, canonical_folder,
                                                 sizeof(canonical_folder)) == RAC_SUCCESS &&
                canonical_folder[0] != '\0') {
                rac_model_path_resolution_t resolution = {};
                const rac_result_t resolve_rc = rac_model_paths_resolve_artifact(
                    raw_info, canonical_folder, nullptr, &resolution);
                if ((resolve_rc == RAC_SUCCESS || resolution.primary_model_path) &&
                    resolution.primary_model_path && resolution.primary_model_path[0] != '\0') {
                    registry_path = resolution.primary_model_path;
                    RAC_LOG_INFO(options.log_cat,
                                 "Resolved empty local_path for %s via canonical folder: %s",
                                 model_id, registry_path.c_str());
                }
                rac_model_path_resolution_free(&resolution);
            }
        }
        bool prefer_input = false;
        if (options.prefer_input_path_when_contains) {
            if (std::strcmp(options.prefer_input_path_when_contains, "/") == 0) {
                // Path separator match: accept either '/' or '\' for cross-platform file paths
                prefer_input =
                    (strchr(model_id, '/') != nullptr || strchr(model_id, '\\') != nullptr);
            } else {
                prefer_input =
                    (strstr(model_id, options.prefer_input_path_when_contains) != nullptr);
            }
        }
        if (prefer_input) {
            out_reference->path = model_id;
        } else {
            out_reference->path = registry_path;
        }

        RAC_LOG_INFO(options.log_cat, "Found model in registry: id=%s, framework=%d, local_path=%s",
                     raw_info->id ? raw_info->id : "NULL",
                     static_cast<int>(out_reference->framework), out_reference->path.c_str());
        return RAC_SUCCESS;
    }

    if (raw_info) {
        rac_model_info_free(raw_info);
    }
    RAC_LOG_WARNING(options.log_cat,
                    "Model NOT found in registry (result=%d), using default framework=%d", result,
                    static_cast<int>(out_reference->framework));
    return RAC_SUCCESS;
}

template <typename OpsT>
using OpsSelector = const OpsT* (*)(const rac_engine_vtable_t* vt);

template <typename ServiceT, typename OpsT>
struct PluginServiceCreateSpec {
    const char* log_cat;
    rac_primitive_t primitive;
    OpsSelector<OpsT> select_ops;
    const char* model_create_id;
    const char* model_id_for_service;
    const char* config_json;
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
};

inline const char* plugin_hint_for_framework(rac_inference_framework_t framework,
                                             rac_primitive_t primitive) {
    switch (framework) {
        case RAC_FRAMEWORK_LLAMACPP:
            return RAC_ENGINE_ID_LLAMACPP;
        case RAC_FRAMEWORK_MLX:
            return RAC_ENGINE_ID_MLX;
        case RAC_FRAMEWORK_SHERPA:
            return RAC_ENGINE_ID_SHERPA;
        case RAC_FRAMEWORK_ONNX:
            if (primitive == RAC_PRIMITIVE_EMBED) {
                return RAC_ENGINE_ID_ONNX;
            }
            if (primitive == RAC_PRIMITIVE_TRANSCRIBE || primitive == RAC_PRIMITIVE_SYNTHESIZE ||
                primitive == RAC_PRIMITIVE_DETECT_VOICE) {
                return RAC_ENGINE_ID_SHERPA;
            }
            return nullptr;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return RAC_ENGINE_ID_PLATFORM;
        case RAC_FRAMEWORK_COREML:
            // A Core ML model is a NeuRT model, for every primitive NeuRT serves.
            //
            // This used to be a per-primitive allow-list ({DIFFUSION, GENERATE_TEXT}),
            // with everything else falling through to `platform` (Apple Foundation
            // Models / System TTS). That list went stale twice: first for GENERATE_TEXT
            // — a COREML-framework LLM pinned the wrong engine and quietly generated
            // from Foundation Models instead of the ANE bundle the caller asked for —
            // and again the moment NeuRT grew TRANSCRIBE, EMBED, RERANK and VLM.
            //
            // The second staleness is the dangerous one, because it does not fail: when
            // the hinted engine does not serve the primitive, create_plugin_service()
            // below falls back to plain priority. MLX is priority 110 and NeuRT is 100,
            // and MLX also fills embedding_ops — so a Core ML embedding model would be
            // served by MLX, silently, with a warning nobody reads.
            //
            // model_lifecycle.cpp's engine_name_for_framework() has always mapped
            // COREML -> neurt unconditionally. Matching that invariant here is what
            // stops the two paths disagreeing, and it cannot go stale again.
            //
            // See framework_requires_hinted_plugin() below for why COREML must not use
            // the priority fallback at all.
            return RAC_ENGINE_ID_NEURT;
        case RAC_FRAMEWORK_QHEXRT:
            return RAC_ENGINE_ID_QHEXRT;
        case RAC_FRAMEWORK_FLUID_AUDIO:
        case RAC_FRAMEWORK_BUILTIN:
        case RAC_FRAMEWORK_NONE:
        case RAC_FRAMEWORK_UNKNOWN:
        default:
            return nullptr;
    }
}

// Whether plugin_hint_for_framework()'s answer is a hard requirement rather than a
// preference.
//
// The priority fallback in create_plugin_service() exists for frameworks whose hint is
// advisory — several engines can read the same bytes, so the next-best engine is a real
// answer. That is not true when the framework names the on-disk *format*: nothing but
// NeuRT can open an .mlmodelc/.mlpackage tree. Falling back by priority hands a Core ML
// bundle to MLX (safetensors), Sherpa or ONNX, which can only produce a confusing
// load-time error far from its cause — or, for a primitive where the fallback engine
// happens to accept the path, a silently wrong model.
//
// This is not hypothetical. Before COREML was routed to NeuRT unconditionally it mapped
// to `platform` for the primitives NeuRT did not serve, and `platform` really does serve
// SYNTHESIZE; without this guard, routing COREML to NeuRT would have sent a Core ML TTS
// request to MLX by priority (110 > 100) instead.
//
// NeuRT now fills tts_ops, so that particular case no longer fires -- but the guard is not
// therefore obsolete. It is what keeps the NEXT unfilled slot from repeating the pattern,
// which this engine has already done twice.
//
// Only COREML is strict here. The other format-determined frameworks (LLAMACPP, MLX,
// QHEXRT) have the same argument available to them, but changing their behaviour is
// outside the scope of the ABI-10 work and untested.
inline bool framework_requires_hinted_plugin(rac_inference_framework_t framework) {
    return framework == RAC_FRAMEWORK_COREML;
}

template <typename ServiceT, typename OpsT>
rac_result_t create_plugin_service(const PluginServiceCreateSpec<ServiceT, OpsT>& spec,
                                   ServiceT** out_service) {
    if (!out_service) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_service = nullptr;

    const char* engine_hint = plugin_hint_for_framework(spec.framework, spec.primitive);
    const rac_engine_vtable_t* vt = nullptr;
    if (engine_hint != nullptr) {
        vt = rac_plugin_find_for_engine(spec.primitive, engine_hint);
        if (vt == nullptr) {
            if (framework_requires_hinted_plugin(spec.framework)) {
                RAC_LOG_ERROR(spec.log_cat,
                              "plugin '%s' does not serve %s and no other plugin can read this "
                              "model's format; failing closed",
                              engine_hint, rac_primitive_name(spec.primitive));
                return RAC_ERROR_BACKEND_NOT_FOUND;
            }
            RAC_LOG_WARNING(spec.log_cat, "plugin '%s' does not serve %s; falling back to priority",
                            engine_hint, rac_primitive_name(spec.primitive));
        }
    }
    if (vt == nullptr) {
        vt = rac_plugin_find(spec.primitive);
    }
    const OpsT* ops = (vt && spec.select_ops) ? spec.select_ops(vt) : nullptr;
    if (!vt || !ops || !ops->create) {
        if (engine_hint != nullptr) {
            RAC_LOG_ERROR(spec.log_cat, "no registered plugin '%s' serves %s", engine_hint,
                          rac_primitive_name(spec.primitive));
        } else {
            RAC_LOG_ERROR(spec.log_cat, "no registered plugin serves %s",
                          rac_primitive_name(spec.primitive));
        }
        return RAC_ERROR_BACKEND_NOT_FOUND;
    }
    RAC_LOG_INFO(spec.log_cat, "Routed to plugin: %s", vt->metadata.name);

    void* impl = nullptr;
    rac_result_t result = ops->create(spec.model_create_id, spec.config_json, &impl);
    if (result != RAC_SUCCESS || !impl) {
        RAC_LOG_ERROR(spec.log_cat, "Plugin create failed: %d", result);
        return (result != RAC_SUCCESS) ? result : RAC_ERROR_BACKEND_NOT_READY;
    }

    auto* service = static_cast<ServiceT*>(malloc(sizeof(ServiceT)));
    if (!service) {
        if (ops->destroy) {
            ops->destroy(impl);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    service->ops = ops;
    service->impl = impl;
    service->model_id = spec.model_id_for_service ? strdup(spec.model_id_for_service) : nullptr;
    if (spec.model_id_for_service && !service->model_id) {
        if (ops->destroy) {
            ops->destroy(impl);
        }
        free(service);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    *out_service = service;

    return RAC_SUCCESS;
}

}  // namespace rac::features

#endif  // RAC_FEATURES_COMMON_RAC_SERVICE_FACTORY_INTERNAL_H
