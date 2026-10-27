/** @file rac_segmentation_service.cpp @brief Semantic segmentation plugin dispatch. */

#include "rac/features/segmentation/rac_segmentation_service.h"

#include "segmentation_service_internal.h"

#include <cstdlib>
#include <limits>
#include <mutex>
#include <unordered_map>

#include "../common/rac_service_factory_internal.h"
#include "plugin/plugin_registry_internal.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_primitive.h"

namespace {

constexpr const char* kLogCategory = "Segmentation.Service";

struct ProviderRegistry {
    std::mutex mutex;
    std::unordered_map<rac_handle_t, std::shared_ptr<rac::segmentation::ProviderContext>> providers;
    // Construct the plugin registry first so leases can still be released
    // when these model records are destroyed during process shutdown.
    ProviderRegistry() { (void)rac_plugin_count(); }
};

ProviderRegistry& provider_registry() {
    static ProviderRegistry value;
    return value;
}

rac_result_t admit_provider(const rac_engine_vtable_t* vt, void* context) {
    return rac::segmentation::acquire_provider(
        vt, static_cast<std::shared_ptr<rac::segmentation::ProviderContext>*>(context));
}

const rac_segmentation_service_ops_t* segmentation_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->segmentation_ops : nullptr;
}

}  // namespace

namespace rac::segmentation {

ProviderContext::~ProviderContext() {
    if (vtable) {
        rac_plugin_registry_release(vtable);
    }
}

rac_result_t acquire_provider(const rac_engine_vtable_t* vtable,
                              std::shared_ptr<ProviderContext>* out_context) {
    if (!out_context) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_context->reset();
    try {
        auto context = std::make_shared<ProviderContext>();
        const rac_engine_manifest_t* manifest = nullptr;
        const rac_result_t rc = rac_plugin_registry_acquire(vtable, &manifest);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
        context->vtable = vtable;
        if (manifest &&
            (manifest->capability_flags & RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1) != 0) {
            // The flag promises the wrapper allocation. Never read an old
            // manifest's tail merely because its engine serves segmentation.
            const auto* extension =
                reinterpret_cast<const rac_segmentation_confidence_manifest_v1_t*>(manifest);
            context->confidence_status = RAC_ERROR_INVALID_PARAMETER;
            if (extension->struct_size >= sizeof(*extension) &&
                extension->version == RAC_SEGMENTATION_CONFIDENCE_VERSION_1 &&
                extension->confidence_ops) {
                const auto* ops = extension->confidence_ops;
                if (ops->struct_size >= sizeof(*ops) &&
                    ops->version == RAC_SEGMENTATION_CONFIDENCE_VERSION_1 && ops->segment) {
                    context->confidence_ops = *ops;
                    context->confidence_status = RAC_SUCCESS;
                }
            }
        }
        *out_context = std::move(context);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

std::shared_ptr<ProviderContext> service_provider(rac_handle_t handle) {
    auto& registry = provider_registry();
    std::lock_guard<std::mutex> lock(registry.mutex);
    const auto it = registry.providers.find(handle);
    return it == registry.providers.end() ? nullptr : it->second;
}

rac_result_t segment_with_confidence(rac_segmentation_service_t* service,
                                     const ProviderContext* provider,
                                     const rac_segmentation_image_t* image,
                                     const rac_segmentation_options_t* options,
                                     rac_segmentation_result_t* out_result,
                                     rac_segmentation_confidence_mask_v1_t* out_confidence) {
    if (!service || !image || !image->data || !out_result || !out_confidence) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_confidence->struct_size < sizeof(*out_confidence) ||
        out_confidence->version != RAC_SEGMENTATION_CONFIDENCE_VERSION_1) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    *out_result = {};
    if (out_confidence->data || out_confidence->size != 0 || image->width == 0 ||
        image->height == 0 || image->width > std::numeric_limits<size_t>::max() / image->height) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (!provider) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (provider->confidence_status != RAC_SUCCESS) {
        return provider->confidence_status;
    }
    const auto defaults = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    rac_result_t rc;
    try {
        rc = provider->confidence_ops.segment(service->impl, image, options ? options : &defaults,
                                              out_result, out_confidence);
    } catch (const std::bad_alloc&) {
        rc = RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        rc = RAC_ERROR_INFERENCE_FAILED;
    }
    const size_t pixels = static_cast<size_t>(image->width) * image->height;
    if (rc == RAC_SUCCESS &&
        (out_confidence->struct_size < sizeof(*out_confidence) ||
         out_confidence->version != RAC_SEGMENTATION_CONFIDENCE_VERSION_1 ||
         !out_confidence->data || out_confidence->size != pixels ||
         out_result->width != image->width || out_result->height != image->height ||
         !out_result->class_mask || out_result->class_mask_count != pixels)) {
        rc = RAC_ERROR_ENCODING_ERROR;
    }
    if (rc != RAC_SUCCESS) {
        rac_segmentation_result_free(out_result);
        std::free(out_confidence->data);
        *out_confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
    }
    return rc;
}

}  // namespace rac::segmentation

rac_result_t rac::segmentation::create_service(const char* model_id, const char* config_json,
                                               rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = nullptr;

    rac::features::ResolvedModelReference model_ref;
    rac_result_t rc =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = kLogCategory,
                                                .default_framework = RAC_FRAMEWORK_ONNX,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = nullptr},
                                               &model_ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    std::shared_ptr<ProviderContext> provider;
    rac_segmentation_service_t* service = nullptr;
    rc = rac::features::create_plugin_service<rac_segmentation_service_t,
                                              rac_segmentation_service_ops_t>(
        {.log_cat = kLogCategory,
         .primitive = RAC_PRIMITIVE_SEGMENT,
         .select_ops = segmentation_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = model_id,
         .config_json = config_json,
         .framework = model_ref.framework,
         .admit_provider = admit_provider,
         .admission_context = &provider},
        &service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    try {
        auto& registry = provider_registry();
        std::lock_guard<std::mutex> lock(registry.mutex);
        registry.providers.insert_or_assign(service, provider);
    } catch (...) {
        rac_segmentation_destroy(service);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_handle = service;
    return RAC_SUCCESS;
}

extern "C" {

rac_result_t rac_segmentation_create(const char* model_id, rac_handle_t* out_handle) {
    return rac::segmentation::create_service(model_id, nullptr, out_handle);
}

rac_result_t rac_segmentation_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_segmentation_segment(rac_handle_t handle, const rac_segmentation_image_t* image,
                                      const rac_segmentation_options_t* options,
                                      rac_segmentation_result_t* out_result) {
    if (!handle || !image || !image->data || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    if (!service->ops || !service->ops->segment) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    *out_result = {};
    if (image->width == 0 || image->height == 0 ||
        image->width > std::numeric_limits<size_t>::max() / image->height) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const rac_segmentation_options_t defaults = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    const auto* effective_options = options ? options : &defaults;
    return service->ops->segment(service->impl, image, effective_options, out_result);
}

rac_result_t
rac_segmentation_segment_with_confidence(rac_handle_t handle, const rac_segmentation_image_t* image,
                                         const rac_segmentation_options_t* options,
                                         rac_segmentation_result_t* out_result,
                                         rac_segmentation_confidence_mask_v1_t* out_confidence) {
    const auto provider = rac::segmentation::service_provider(handle);
    return rac::segmentation::segment_with_confidence(
        static_cast<rac_segmentation_service_t*>(handle), provider.get(), image, options,
        out_result, out_confidence);
}

void rac_segmentation_confidence_mask_free(rac_segmentation_confidence_mask_v1_t* confidence) {
    if (confidence && confidence->struct_size >= sizeof(*confidence) &&
        confidence->version == RAC_SEGMENTATION_CONFIDENCE_VERSION_1) {
        std::free(confidence->data);
        *confidence = RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT;
    }
}

rac_result_t rac_segmentation_cleanup(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    return service->ops && service->ops->cleanup ? service->ops->cleanup(service->impl)
                                                 : RAC_SUCCESS;
}

void rac_segmentation_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    auto* service = static_cast<rac_segmentation_service_t*>(handle);
    // Keep the lease through the engine's final destructor callback.
    auto provider = rac::segmentation::service_provider(handle);
    {
        // Remove the key before freeing the address for another service to reuse.
        auto& registry = provider_registry();
        std::lock_guard<std::mutex> lock(registry.mutex);
        registry.providers.erase(handle);
    }
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }
    std::free(const_cast<char*>(service->model_id));
    std::free(service);
}

void rac_segmentation_result_free(rac_segmentation_result_t* result) {
    if (!result) {
        return;
    }
    std::free(result->class_mask);
    std::free(result->diagnostic_rgba);
    if (result->class_summaries) {
        for (size_t i = 0; i < result->class_summary_count; ++i) {
            std::free(result->class_summaries[i].label);
        }
    }
    std::free(result->class_summaries);
    std::free(result->model_id);
    *result = {};
}

}  // extern "C"
