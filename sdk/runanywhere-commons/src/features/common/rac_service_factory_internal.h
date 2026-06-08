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

#include "rac/core/rac_error.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/events/rac_events.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
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
        const char* last_slash = strrchr(model_id, '/');
        if (last_slash && last_slash[1] != '\0') {
            const char* extracted_id = last_slash + 1;
            RAC_LOG_DEBUG(options.log_cat, "Trying extracted model ID from path: %s",
                          extracted_id);
            result = rac_get_model(extracted_id, &raw_info);
        }
    }

    out_reference->registry_result = result;
    if (result == RAC_SUCCESS && raw_info) {
        out_reference->found = true;
        out_reference->model_info.reset(raw_info);
        out_reference->framework = raw_info->framework;

        const char* registry_path =
            (raw_info->local_path && raw_info->local_path[0] != '\0') ? raw_info->local_path
                                                                      : model_id;
        if (options.prefer_input_path_when_contains &&
            strstr(model_id, options.prefer_input_path_when_contains) != nullptr) {
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
    const char* created_event_name;
    rac_event_category_t created_event_category;
};

template <typename ServiceT, typename OpsT>
rac_result_t create_plugin_service(const PluginServiceCreateSpec<ServiceT, OpsT>& spec,
                                   ServiceT** out_service) {
    if (!out_service) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_service = nullptr;

    const rac_engine_vtable_t* vt = rac_plugin_find(spec.primitive);
    const OpsT* ops = (vt && spec.select_ops) ? spec.select_ops(vt) : nullptr;
    if (!vt || !ops || !ops->create) {
        RAC_LOG_ERROR(spec.log_cat, "no registered plugin serves %s", rac_primitive_name(spec.primitive));
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

    if (spec.created_event_name) {
        const char* backend_name = vt->metadata.name ? vt->metadata.name : "unknown";
        char props[128];
        snprintf(props, sizeof(props), R"({"backend":"%s"})", backend_name);
        rac_event_track(spec.created_event_name, spec.created_event_category,
                        RAC_EVENT_DESTINATION_ALL, props);
    }

    return RAC_SUCCESS;
}

}  // namespace rac::features

#endif  // RAC_FEATURES_COMMON_RAC_SERVICE_FACTORY_INTERNAL_H
