/**
 * @file embeddings_component.cpp
 * @brief Embeddings Capability Component Implementation
 *
 * Embeddings component that owns model lifecycle and embedding generation.
 * Uses lifecycle manager for unified lifecycle + analytics handling.
 *
 * Follows the same pattern as vlm_component.cpp.
 */

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_component.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

static const char* LOG_CAT = "Embeddings.Component";

// =============================================================================
// INTERNAL STRUCTURES
// =============================================================================

struct rac_embeddings_component {
    /** Lifecycle manager handle */
    rac_handle_t lifecycle;

    /** Current configuration */
    rac_embeddings_config_t config;

    /** Mutex for thread safety */
    std::mutex mtx;

    rac_embeddings_component() : lifecycle(nullptr) {
        config = RAC_EMBEDDINGS_CONFIG_DEFAULT;
    }
};

// =============================================================================
// LIFECYCLE CALLBACKS
// =============================================================================

/**
 * Service creation callback for lifecycle manager.
 */
static rac_result_t embeddings_create_service(const char* model_id, void* user_data,
                                               rac_handle_t* out_service) {
    (void)user_data;

    RAC_LOG_INFO(LOG_CAT, "Creating embeddings service for model: %s", model_id ? model_id : "");

    // Create embeddings service
    rac_result_t result = rac_embeddings_create(model_id, out_service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create embeddings service: %d", result);
        return result;
    }

    // Initialize with model path
    result = rac_embeddings_initialize(*out_service, model_id);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to initialize embeddings service: %d", result);
        rac_embeddings_destroy(*out_service);
        *out_service = nullptr;
        return result;
    }

    RAC_LOG_INFO(LOG_CAT, "Embeddings service created successfully");
    return RAC_SUCCESS;
}

/**
 * Service destruction callback for lifecycle manager.
 */
static void embeddings_destroy_service(rac_handle_t service, void* user_data) {
    (void)user_data;

    if (service) {
        RAC_LOG_DEBUG(LOG_CAT, "Destroying embeddings service");
        rac_embeddings_cleanup(service);
        rac_embeddings_destroy(service);
    }
}

// =============================================================================
// LIFECYCLE API
// =============================================================================

extern "C" rac_result_t rac_embeddings_component_create(rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    auto* component = new (std::nothrow) rac_embeddings_component();
    if (!component) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Create lifecycle manager
    rac_lifecycle_config_t lifecycle_config = {};
    lifecycle_config.resource_type = RAC_RESOURCE_TYPE_LLM_MODEL;  // Reuse LLM model type (embedding models are LLMs)
    lifecycle_config.logger_category = "Embeddings.Lifecycle";
    lifecycle_config.user_data = component;

    rac_result_t result = rac_lifecycle_create(&lifecycle_config, embeddings_create_service,
                                               embeddings_destroy_service, &component->lifecycle);

    if (result != RAC_SUCCESS) {
        delete component;
        return result;
    }

    *out_handle = reinterpret_cast<rac_handle_t>(component);

    RAC_LOG_INFO(LOG_CAT, "Embeddings component created");

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_embeddings_component_configure(rac_handle_t handle,
                                                            const rac_embeddings_config_t* config) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!config)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    component->config = *config;

    RAC_LOG_INFO(LOG_CAT, "Embeddings component configured (max_tokens=%d, normalize=%d, pooling=%d)",
                 config->max_tokens, static_cast<int>(config->normalize),
                 static_cast<int>(config->pooling));

    return RAC_SUCCESS;
}

extern "C" rac_bool_t rac_embeddings_component_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

extern "C" const char* rac_embeddings_component_get_model_id(rac_handle_t handle) {
    if (!handle)
        return nullptr;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

extern "C" void rac_embeddings_component_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);

    if (component->lifecycle) {
        rac_lifecycle_destroy(component->lifecycle);
    }

    RAC_LOG_INFO(LOG_CAT, "Embeddings component destroyed");

    delete component;
}

// =============================================================================
// MODEL LIFECYCLE
// =============================================================================

extern "C" rac_result_t rac_embeddings_component_load_model(rac_handle_t handle,
                                                             const char* model_path,
                                                             const char* model_id,
                                                             const char* model_name) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!model_path)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

extern "C" rac_result_t rac_embeddings_component_unload(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_unload(component->lifecycle);
}

extern "C" rac_result_t rac_embeddings_component_cleanup(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    return rac_lifecycle_reset(component->lifecycle);
}

// =============================================================================
// EMBEDDING GENERATION API
// =============================================================================

extern "C" rac_result_t rac_embeddings_component_embed(rac_handle_t handle,
                                                        const char* text,
                                                        const rac_embeddings_options_t* options,
                                                        rac_embeddings_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!text || !out_result)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    // Get service from lifecycle manager
    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded - cannot embed");
        return result;
    }

    auto start_time = std::chrono::steady_clock::now();

    result = rac_embeddings_embed(service, text, options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Embedding generation failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "embed");
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    out_result->processing_time_ms = duration.count();

    RAC_LOG_INFO(LOG_CAT, "Embedding generated: dim=%zu, time=%lldms",
                 out_result->dimension, static_cast<long long>(out_result->processing_time_ms));

    return RAC_SUCCESS;
}

extern "C" rac_result_t rac_embeddings_component_embed_batch(rac_handle_t handle,
                                                              const char* const* texts,
                                                              size_t num_texts,
                                                              const rac_embeddings_options_t* options,
                                                              rac_embeddings_result_t* out_result) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!texts || !out_result || num_texts == 0)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    std::lock_guard<std::mutex> lock(component->mtx);

    rac_handle_t service = nullptr;
    rac_result_t result = rac_lifecycle_require_service(component->lifecycle, &service);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded - cannot embed batch");
        return result;
    }

    auto start_time = std::chrono::steady_clock::now();

    result = rac_embeddings_embed_batch(service, texts, num_texts, options, out_result);

    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "Batch embedding failed: %d", result);
        rac_lifecycle_track_error(component->lifecycle, result, "embedBatch");
        return result;
    }

    auto end_time = std::chrono::steady_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
    out_result->processing_time_ms = duration.count();

    RAC_LOG_INFO(LOG_CAT, "Batch embedding generated: n=%zu, dim=%zu, time=%lldms",
                 out_result->num_embeddings, out_result->dimension,
                 static_cast<long long>(out_result->processing_time_ms));

    return RAC_SUCCESS;
}

// =============================================================================
// STATE QUERY API
// =============================================================================

extern "C" rac_lifecycle_state_t rac_embeddings_component_get_state(rac_handle_t handle) {
    if (!handle)
        return RAC_LIFECYCLE_STATE_IDLE;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    return rac_lifecycle_get_state(component->lifecycle);
}

extern "C" rac_result_t rac_embeddings_component_get_metrics(rac_handle_t handle,
                                                              rac_lifecycle_metrics_t* out_metrics) {
    if (!handle)
        return RAC_ERROR_INVALID_HANDLE;
    if (!out_metrics)
        return RAC_ERROR_INVALID_ARGUMENT;

    auto* component = reinterpret_cast<rac_embeddings_component*>(handle);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}
