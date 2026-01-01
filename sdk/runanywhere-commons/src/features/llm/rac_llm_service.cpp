/**
 * @file rac_llm_service.cpp
 * @brief LLM Service - Framework-Aware Service Creation via Service Registry
 *
 * This file implements the generic LLM service API by routing requests
 * through the service registry. The registry selects the appropriate
 * provider (LlamaCPP, ONNX, Foundation Models, etc.) based on the
 * model's framework from the model registry.
 *
 * Flow:
 * 1. rac_llm_create(model_id) is called
 * 2. Query model registry to get framework for this model
 * 3. Create service request with framework hint
 * 4. Service registry finds matching provider (by can_handle + priority)
 * 5. Provider's create() is called to instantiate the service
 */

#include "rac/features/llm/rac_llm_service.h"

#include <cstring>

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

// =============================================================================
// INTERNAL HELPERS
// =============================================================================

static void log_info(const char* msg) {
    rac_log(RAC_LOG_INFO, "LLM.Service", msg);
}

static void log_error(const char* msg) {
    rac_log(RAC_LOG_ERROR, "LLM.Service", msg);
}

static void log_debug(const char* msg) {
    rac_log(RAC_LOG_DEBUG, "LLM.Service", msg);
}

// =============================================================================
// SERVICE CREATION - Routes through Service Registry
// =============================================================================

extern "C" {

rac_result_t rac_llm_create(const char* model_id, rac_handle_t* out_handle) {
    if (!model_id || !out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_handle = nullptr;

    // Step 1: Query model registry to get framework
    rac_model_info_t* model_info = nullptr;
    rac_result_t result = rac_get_model(model_id, &model_info);

    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    const char* model_path = nullptr;

    if (result == RAC_SUCCESS && model_info) {
        framework = model_info->framework;
        model_path = model_info->local_path;
        log_debug("Found model in registry");
    } else {
        // Model not in registry - treat model_id as path, default to LlamaCPP
        log_debug("Model not in registry, using model_id as path with LlamaCPP framework");
        model_path = model_id;
        framework = RAC_FRAMEWORK_LLAMACPP;
    }

    // Step 2: Build service request
    rac_service_request_t request = {};
    request.identifier = model_id;
    request.capability = RAC_CAPABILITY_TEXT_GENERATION;
    request.framework = framework;
    request.model_path = model_path;
    request.config_json = nullptr;

    // Step 3: Use service registry to create service
    result = rac_service_create(RAC_CAPABILITY_TEXT_GENERATION, &request, out_handle);

    // Cleanup model info
    if (model_info) {
        rac_model_info_free(model_info);
    }

    if (result != RAC_SUCCESS) {
        log_error("Service registry failed to create LLM service");
        return result;
    }

    if (*out_handle == nullptr) {
        log_error("Service registry returned null handle");
        return RAC_ERROR_NO_CAPABLE_PROVIDER;
    }

    log_info("LLM service created via service registry");
    return RAC_SUCCESS;
}

}  // extern "C"
