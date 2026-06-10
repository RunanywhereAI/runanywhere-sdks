/**
 * @file rac_rag_register.cpp
 * @brief RAG Pipeline Module Registration
 *
 * Registers the RAG pipeline module and its ONNX embeddings provider.
 * RAG itself is a pipeline (like Voice Agent) — it does not register as
 * a service provider. The ONNX embeddings provider is registered so that
 * rac_embeddings_create() can discover it via the service registry.
 */

#include "rac/core/rac_logger.h"
#include "rac/features/rag/rac_rag.h"

#ifdef RAG_HAS_ONNX_PROVIDER
#include "rac/backends/rac_embeddings_onnx.h"
#endif

#include <string.h>

#define LOG_TAG "RAG.Register"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

extern "C" {

rac_result_t rac_backend_rag_register(void) {
    LOGI("Registering RAG pipeline module...");

#ifdef RAG_HAS_ONNX_PROVIDER
    rac_result_t result = rac_backend_onnx_embeddings_register();
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        LOGE("Failed to register ONNX embeddings provider: %d", result);
    } else {
        LOGI("ONNX embeddings provider registered");
    }
#endif

    LOGI("RAG pipeline module registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_rag_unregister(void) {
    LOGI("Unregistering RAG pipeline module...");

#ifdef RAG_HAS_ONNX_PROVIDER
    rac_backend_onnx_embeddings_unregister();
#endif

    LOGI("RAG pipeline module unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
