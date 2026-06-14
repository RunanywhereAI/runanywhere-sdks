/**
 * @file rac_llm_service.cpp
 * @brief LLM Service - Generic API with VTable Dispatch
 *
 * Simple dispatch layer that routes calls through the service vtable.
 * Each backend provides its own vtable when creating a service.
 * No wrappers, no switch statements - just vtable calls.
 */

#include "rac/features/llm/rac_llm_service.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#ifdef __ANDROID__
#include <android/log.h>
#define ALOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "RAC_LLM_SVC", __VA_ARGS__)
#else
#define ALOGD(...) fprintf(stderr, __VA_ARGS__)
#endif

#include "../common/rac_service_factory_internal.h"
#include "features/llm/llm_thinking_directive_internal.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "LLM.Service";

namespace {

const rac_llm_service_ops_t* llm_ops(const rac_engine_vtable_t* vt) {
    return vt ? vt->llm_ops : nullptr;
}

}  // namespace

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    ALOGD("rac_llm_create: model_id=%s", model_id);
    RAC_LOG_INFO(LOG_CAT, "Creating LLM service for: %s", model_id);

    rac::features::ResolvedModelReference model_ref;
    rac_result_t result =
        rac::features::resolve_model_reference(model_id,
                                               {.log_cat = LOG_CAT,
                                                .default_framework = RAC_FRAMEWORK_LLAMACPP,
                                                .allow_null_model_id = false,
                                                .lookup_last_path_component = true,
                                                .prefer_input_path_when_contains = ".gguf"},
                                               &model_ref);
    if (result != RAC_SUCCESS) {
        return result;
    }

    rac_llm_service_t* service = nullptr;
    result = rac::features::create_plugin_service<rac_llm_service_t, rac_llm_service_ops_t>(
        {.log_cat = LOG_CAT,
         .primitive = RAC_PRIMITIVE_GENERATE_TEXT,
         .select_ops = llm_ops,
         .model_create_id = model_ref.path.c_str(),
         .model_id_for_service = model_id,
         .config_json = nullptr},
        &service);
    if (result != RAC_SUCCESS) {
        return result;
    }
    *out_handle = service;

    ALOGD("LLM service created successfully");
    RAC_LOG_INFO(LOG_CAT, "LLM service created");
    return RAC_SUCCESS;
}

// =============================================================================
// GENERIC API - Simple vtable dispatch
// =============================================================================

rac_result_t rac_llm_initialize(rac_handle_t handle, const char* model_path) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->initialize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->initialize(service->impl, model_path);
}

rac_result_t rac_llm_generate(rac_handle_t handle, const char* prompt,
                              const rac_llm_options_t* options, rac_llm_result_t* out_result) {
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: START handle=%p, prompt=%p, out_result=%p", handle,
                 (void*)prompt, (void*)out_result);

    if (!handle || !prompt || !out_result) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_generate: NULL pointer!");
        return RAC_ERROR_NULL_POINTER;
    }

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: casting to service...");
    auto* service = static_cast<rac_llm_service_t*>(handle);
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: service=%p, ops=%p", (void*)service,
                 (void*)service->ops);

    if (!service->ops || !service->ops->generate) {
        RAC_LOG_ERROR(LOG_CAT, "rac_llm_generate: ops or generate is NULL!");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: ops->generate=%p, impl=%p",
                 (void*)service->ops->generate, service->impl);
    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: calling backend generate...");

    const std::string effective_prompt =
        rac::llm::apply_no_think_directive(prompt, options ? options->disable_thinking : RAC_FALSE);
    rac_result_t result =
        service->ops->generate(service->impl, effective_prompt.c_str(), options, out_result);

    RAC_LOG_INFO(LOG_CAT, "rac_llm_generate: backend returned result=%d", result);
    return result;
}

rac_result_t rac_llm_generate_stream(rac_handle_t handle, const char* prompt,
                                     const rac_llm_options_t* options,
                                     rac_llm_stream_callback_fn callback, void* user_data) {
    if (!handle || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->generate_stream) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const std::string effective_prompt =
        rac::llm::apply_no_think_directive(prompt, options ? options->disable_thinking : RAC_FALSE);
    return service->ops->generate_stream(service->impl, effective_prompt.c_str(), options, callback,
                                         user_data);
}

rac_result_t rac_llm_get_info(rac_handle_t handle, rac_llm_info_t* out_info) {
    if (!handle || !out_info)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->get_info) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    return service->ops->get_info(service->impl, out_info);
}

rac_result_t rac_llm_cancel(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->cancel) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cancel(service->impl);
}

rac_result_t rac_llm_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->cleanup) {
        return RAC_SUCCESS;  // No-op if not supported
    }

    return service->ops->cleanup(service->impl);
}

void rac_llm_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* service = static_cast<rac_llm_service_t*>(handle);

    // Call backend destroy
    if (service->ops && service->ops->destroy) {
        service->ops->destroy(service->impl);
    }

    // Free model_id if allocated
    if (service->model_id) {
        free(const_cast<char*>(service->model_id));
    }

    // Free service struct
    free(service);
}

void rac_llm_result_free(rac_llm_result_t* result) {
    if (!result)
        return;
    if (result->text) {
        free(result->text);
        result->text = nullptr;
    }
}

// =============================================================================
// ADAPTIVE CONTEXT API - VTable dispatch
// =============================================================================

rac_result_t rac_llm_inject_system_prompt(rac_handle_t handle, const char* prompt) {
    if (!handle || !prompt)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->inject_system_prompt)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->inject_system_prompt(service->impl, prompt);
}

rac_result_t rac_llm_append_context(rac_handle_t handle, const char* text) {
    if (!handle || !text)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->append_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->append_context(service->impl, text);
}

rac_result_t rac_llm_generate_from_context(rac_handle_t handle, const char* query,
                                           const rac_llm_options_t* options,
                                           rac_llm_result_t* out_result) {
    if (!handle || !query || !out_result)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->generate_from_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->generate_from_context(service->impl, query, options, out_result);
}

rac_result_t rac_llm_clear_context(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;

    auto* service = static_cast<rac_llm_service_t*>(handle);
    if (!service->ops || !service->ops->clear_context)
        return RAC_ERROR_NOT_SUPPORTED;

    return service->ops->clear_context(service->impl);
}

}  // extern "C"
