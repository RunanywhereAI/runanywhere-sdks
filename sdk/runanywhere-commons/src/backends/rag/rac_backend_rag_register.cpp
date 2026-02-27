/**
 * @file rac_backend_rag_register.cpp
 * @brief RAG Backend Registration
 */

#include "rac/backends/rac_rag.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/features/rag/rac_rag_pipeline.h"

#include <string.h>

static const char* LOG_TAG = "RAG.Register";

// =============================================================================
// MODULE REGISTRATION
// =============================================================================

static const char* MODULE_ID = "rag";
static const char* MODULE_NAME = "RAG Backend";
static const char* MODULE_VERSION = "1.0.0";
static const char* MODULE_DESC = "Retrieval-Augmented Generation with USearch";

extern "C" {

rac_result_t rac_backend_rag_register(void) {
    RAC_LOG_INFO(LOG_TAG,"Registering RAG backend module...");

    // Register module
    rac_capability_t capabilities[] = {
        // RAG doesn't register as a service provider yet
        // It's a higher-level pipeline using existing services
    };

    rac_module_info_t module_info = {
        .id = MODULE_ID,
        .name = MODULE_NAME,
        .version = MODULE_VERSION,
        .description = MODULE_DESC,
        .capabilities = capabilities,
        .num_capabilities = 0
    };

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG,"Failed to register RAG module");
        return result;
    }

    RAC_LOG_INFO(LOG_TAG,"RAG backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_rag_unregister(void) {
    RAC_LOG_INFO(LOG_TAG,"Unregistering RAG backend...");

    rac_result_t result = rac_module_unregister(MODULE_ID);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_TAG,"Failed to unregister RAG module");
        return result;
    }

    RAC_LOG_INFO(LOG_TAG,"RAG backend unregistered");
    return RAC_SUCCESS;
}

} // extern "C"
