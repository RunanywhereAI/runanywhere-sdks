/**
 * @file rac_backend_platform_register.cpp
 * @brief RunAnywhere Commons - Platform Backend Registration
 *
 * Registers the Platform backend (Apple Foundation Models + System TTS) with
 * the module and service registries. Provides vtable implementations for
 * the generic service APIs.
 */

#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/platform/rac_llm_platform.h"
#include "rac/features/platform/rac_tts_platform.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

static const char* LOG_CAT = "Platform";

// =============================================================================
// LLM VTABLE IMPLEMENTATION - Foundation Models
// =============================================================================

namespace {

// Initialize (no-op for Foundation Models - already initialized during create)
static rac_result_t platform_llm_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    RAC_LOG_DEBUG(LOG_CAT, "LLM initialize (no-op for Foundation Models)");
    return RAC_SUCCESS;
}

// Generate (blocking)
static rac_result_t platform_llm_vtable_generate(void* impl, const char* prompt,
                                                 const rac_llm_options_t* options,
                                                 rac_llm_result_t* out_result) {
    if (!impl || !prompt || !out_result)
        return RAC_ERROR_NULL_POINTER;

    RAC_LOG_DEBUG(LOG_CAT, "LLM generate via Swift");

    // Convert options
    rac_llm_platform_options_t platform_options = {};
    if (options) {
        platform_options.temperature = options->temperature;
        platform_options.max_tokens = options->max_tokens;
    } else {
        platform_options.temperature = 0.7f;
        platform_options.max_tokens = 1000;
    }

    auto handle = static_cast<rac_llm_platform_handle_t>(impl);
    char* response = nullptr;
    rac_result_t result = rac_llm_platform_generate(handle, prompt, &platform_options, &response);

    if (result == RAC_SUCCESS && response) {
        out_result->text = response;
        out_result->prompt_tokens = 0;
        out_result->completion_tokens = 0;
    }

    return result;
}

// Generate stream - Platform handles streaming at Swift level
static rac_result_t platform_llm_vtable_generate_stream(void* impl, const char* prompt,
                                                        const rac_llm_options_t* options,
                                                        rac_llm_stream_callback_fn callback,
                                                        void* user_data) {
    if (!impl || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;

    RAC_LOG_DEBUG(LOG_CAT, "LLM generate_stream via Swift");

    // Convert options
    rac_llm_platform_options_t platform_options = {};
    if (options) {
        platform_options.temperature = options->temperature;
        platform_options.max_tokens = options->max_tokens;
    } else {
        platform_options.temperature = 0.7f;
        platform_options.max_tokens = 1000;
    }

    // For Foundation Models, streaming is handled at Swift level
    // We call generate and emit the response
    auto handle = static_cast<rac_llm_platform_handle_t>(impl);
    char* response = nullptr;
    rac_result_t result = rac_llm_platform_generate(handle, prompt, &platform_options, &response);

    if (result == RAC_SUCCESS && response) {
        callback(response, user_data);
        free(response);
    }

    return result;
}

// Get info
static rac_result_t platform_llm_vtable_get_info(void* impl, rac_llm_info_t* out_info) {
    (void)impl;
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;  // Always ready (built-in)
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model = nullptr;
    out_info->context_length = 4096;

    return RAC_SUCCESS;
}

// Cancel (handled at Swift level)
static rac_result_t platform_llm_vtable_cancel(void* impl) {
    (void)impl;
    RAC_LOG_DEBUG(LOG_CAT, "LLM cancel (handled at Swift level)");
    return RAC_SUCCESS;
}

// Cleanup (no-op)
static rac_result_t platform_llm_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void platform_llm_vtable_destroy(void* impl) {
    if (impl) {
        RAC_LOG_DEBUG(LOG_CAT, "LLM destroy via Swift");
        rac_llm_platform_destroy(static_cast<rac_llm_platform_handle_t>(impl));
    }
}

// Static vtable for Platform LLM
static const rac_llm_service_ops_t g_platform_llm_ops = {
    .initialize = platform_llm_vtable_initialize,
    .generate = platform_llm_vtable_generate,
    .generate_stream = platform_llm_vtable_generate_stream,
    .get_info = platform_llm_vtable_get_info,
    .cancel = platform_llm_vtable_cancel,
    .cleanup = platform_llm_vtable_cleanup,
    .destroy = platform_llm_vtable_destroy,
};

// =============================================================================
// TTS VTABLE IMPLEMENTATION - System TTS
// =============================================================================

// Initialize (no-op - System TTS is always ready)
static rac_result_t platform_tts_vtable_initialize(void* impl) {
    (void)impl;
    RAC_LOG_DEBUG(LOG_CAT, "TTS initialize (no-op for System TTS)");
    return RAC_SUCCESS;
}

// Synthesize (blocking)
static rac_result_t platform_tts_vtable_synthesize(void* impl, const char* text,
                                                   const rac_tts_options_t* options,
                                                   rac_tts_result_t* out_result) {
    if (!impl || !text || !out_result)
        return RAC_ERROR_NULL_POINTER;

    RAC_LOG_DEBUG(LOG_CAT, "TTS synthesize via Swift");

    // Convert options
    rac_tts_platform_options_t platform_options = {};
    if (options) {
        platform_options.rate = options->rate;
        platform_options.pitch = options->pitch;
        platform_options.volume = options->volume;
        platform_options.voice_id = options->voice;
    } else {
        platform_options.rate = 1.0f;
        platform_options.pitch = 1.0f;
        platform_options.volume = 1.0f;
    }

    const auto* callbacks = rac_platform_tts_get_callbacks();
    if (!callbacks || !callbacks->synthesize) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac_result_t result =
        callbacks->synthesize(impl, text, &platform_options, callbacks->user_data);

    // System TTS doesn't return audio data - it plays directly
    // Set result to indicate success but no audio data
    out_result->audio_data = nullptr;
    out_result->audio_size = 0;

    return result;
}

// Stream synthesis (System TTS handles streaming internally)
static rac_result_t platform_tts_vtable_synthesize_stream(void* impl, const char* text,
                                                          const rac_tts_options_t* options,
                                                          rac_tts_stream_callback_t callback,
                                                          void* user_data) {
    (void)callback;
    (void)user_data;

    // System TTS doesn't support streaming to a callback - it plays directly
    // Fall back to regular synthesis
    rac_tts_result_t result = {};
    return platform_tts_vtable_synthesize(impl, text, options, &result);
}

// Stop
static rac_result_t platform_tts_vtable_stop(void* impl) {
    if (!impl)
        return RAC_ERROR_NULL_POINTER;

    const auto* callbacks = rac_platform_tts_get_callbacks();
    if (callbacks && callbacks->stop) {
        callbacks->stop(impl, callbacks->user_data);
    }

    return RAC_SUCCESS;
}

// Get info
static rac_result_t platform_tts_vtable_get_info(void* impl, rac_tts_info_t* out_info) {
    (void)impl;
    if (!out_info)
        return RAC_ERROR_NULL_POINTER;

    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;

    return RAC_SUCCESS;
}

// Cleanup (no-op)
static rac_result_t platform_tts_vtable_cleanup(void* impl) {
    (void)impl;
    return RAC_SUCCESS;
}

// Destroy
static void platform_tts_vtable_destroy(void* impl) {
    if (!impl)
        return;

    RAC_LOG_DEBUG(LOG_CAT, "TTS destroy via Swift");

    const auto* callbacks = rac_platform_tts_get_callbacks();
    if (callbacks && callbacks->destroy) {
        callbacks->destroy(impl, callbacks->user_data);
    }
}

// Static vtable for Platform TTS
static const rac_tts_service_ops_t g_platform_tts_ops = {
    .initialize = platform_tts_vtable_initialize,
    .synthesize = platform_tts_vtable_synthesize,
    .synthesize_stream = platform_tts_vtable_synthesize_stream,
    .stop = platform_tts_vtable_stop,
    .get_info = platform_tts_vtable_get_info,
    .cleanup = platform_tts_vtable_cleanup,
    .destroy = platform_tts_vtable_destroy,
};

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct PlatformRegistryState {
    std::mutex mutex;
    bool registered = false;
    char provider_llm_name[32] = "AppleFoundationModels";
    char provider_tts_name[32] = "SystemTTS";
    char module_id[16] = "platform";
};

PlatformRegistryState& get_state() {
    static PlatformRegistryState state;
    return state;
}

// =============================================================================
// LLM SERVICE PROVIDER - Apple Foundation Models
// =============================================================================

rac_bool_t platform_llm_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Check framework hint first
    if (request->framework == RAC_FRAMEWORK_FOUNDATION_MODELS) {
        RAC_LOG_DEBUG(LOG_CAT, "LLM can_handle: framework match -> true");
        return RAC_TRUE;
    }

    // If framework explicitly set to something else, don't handle
    if (request->framework != RAC_FRAMEWORK_UNKNOWN) {
        return RAC_FALSE;
    }

    // Check if Swift callbacks are available
    const auto* callbacks = rac_platform_llm_get_callbacks();
    if (callbacks == nullptr || callbacks->can_handle == nullptr) {
        return RAC_FALSE;
    }

    // Delegate to Swift
    return callbacks->can_handle(request->identifier, callbacks->user_data);
}

/**
 * Create Foundation Models LLM service with vtable.
 * Returns an rac_llm_service_t* that the generic API can dispatch through.
 */
rac_handle_t platform_llm_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "LLM create: null request");
        return nullptr;
    }

    const auto* callbacks = rac_platform_llm_get_callbacks();
    if (callbacks == nullptr || callbacks->create == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "LLM create: Swift callbacks not registered");
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating Foundation Models LLM service via Swift");

    const char* model_path = request->model_path ? request->model_path : request->identifier;
    rac_llm_platform_config_t config = {};

    // Create backend-specific handle via Swift
    rac_handle_t backend_handle = callbacks->create(model_path, &config, callbacks->user_data);
    if (!backend_handle) {
        RAC_LOG_ERROR(LOG_CAT, "Swift create callback returned null");
        return nullptr;
    }

    // Allocate service struct with vtable
    auto* service = static_cast<rac_llm_service_t*>(malloc(sizeof(rac_llm_service_t)));
    if (!service) {
        rac_llm_platform_destroy(static_cast<rac_llm_platform_handle_t>(backend_handle));
        return nullptr;
    }

    service->ops = &g_platform_llm_ops;
    service->impl = backend_handle;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "Foundation Models LLM service created successfully");
    return service;
}

// =============================================================================
// TTS SERVICE PROVIDER - System TTS
// =============================================================================

rac_bool_t platform_tts_can_handle(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    if (request == nullptr) {
        return RAC_FALSE;
    }

    // Check framework hint first
    if (request->framework == RAC_FRAMEWORK_SYSTEM_TTS) {
        RAC_LOG_DEBUG(LOG_CAT, "TTS can_handle: framework match -> true");
        return RAC_TRUE;
    }

    // If framework explicitly set to something else, don't handle
    if (request->framework != RAC_FRAMEWORK_UNKNOWN) {
        return RAC_FALSE;
    }

    // Check if Swift callbacks are available
    const auto* callbacks = rac_platform_tts_get_callbacks();
    if (callbacks == nullptr || callbacks->can_handle == nullptr) {
        return RAC_FALSE;
    }

    // Delegate to Swift
    return callbacks->can_handle(request->identifier, callbacks->user_data);
}

/**
 * Create System TTS service with vtable.
 * Returns an rac_tts_service_t* that the generic API can dispatch through.
 */
rac_handle_t platform_tts_create(const rac_service_request_t* request, void* user_data) {
    (void)user_data;

    const auto* callbacks = rac_platform_tts_get_callbacks();
    if (callbacks == nullptr || callbacks->create == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "TTS create: Swift callbacks not registered");
        return nullptr;
    }

    RAC_LOG_INFO(LOG_CAT, "Creating System TTS service via Swift");

    rac_tts_platform_config_t config = {};
    if (request != nullptr && request->identifier != nullptr) {
        config.voice_id = request->identifier;
    }

    // Create backend-specific handle via Swift
    rac_handle_t backend_handle = callbacks->create(&config, callbacks->user_data);
    if (!backend_handle) {
        RAC_LOG_ERROR(LOG_CAT, "Swift TTS create callback returned null");
        return nullptr;
    }

    // Allocate service struct with vtable
    auto* service = static_cast<rac_tts_service_t*>(malloc(sizeof(rac_tts_service_t)));
    if (!service) {
        if (callbacks->destroy) {
            callbacks->destroy(backend_handle, callbacks->user_data);
        }
        return nullptr;
    }

    service->ops = &g_platform_tts_ops;
    service->impl = backend_handle;
    service->model_id = (request && request->identifier) ? strdup(request->identifier) : nullptr;

    RAC_LOG_INFO(LOG_CAT, "System TTS service created successfully");
    return service;
}

// =============================================================================
// BUILT-IN MODEL REGISTRATION
// =============================================================================

void register_foundation_models_entry() {
    rac_model_registry* registry = rac_get_model_registry();
    if (registry == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "Cannot register built-in model: registry not available");
        return;
    }

    rac_model_info_t model = {};
    model.id = strdup("foundation-models-default");
    model.name = strdup("Platform LLM");
    model.category = RAC_MODEL_CATEGORY_LANGUAGE;
    model.format = RAC_MODEL_FORMAT_UNKNOWN;
    model.framework = RAC_FRAMEWORK_FOUNDATION_MODELS;
    model.download_url = nullptr;
    model.local_path = strdup("builtin://foundation-models");
    model.artifact_info.kind = RAC_ARTIFACT_KIND_BUILT_IN;
    model.download_size = 0;
    model.memory_required = 0;
    model.context_length = 4096;
    model.supports_thinking = RAC_FALSE;
    model.tags = nullptr;
    model.tag_count = 0;
    model.description = strdup(
        "Platform's built-in language model. "
        "Uses the device's native AI capabilities when available.");
    model.source = RAC_MODEL_SOURCE_LOCAL;

    rac_result_t result = rac_model_registry_save(registry, &model);
    if (result == RAC_SUCCESS) {
        RAC_LOG_INFO(LOG_CAT, "Registered built-in model: %s", model.id);
    }

    free(model.id);
    free(model.name);
    free(model.local_path);
    free(model.description);
}

void register_system_tts_entry() {
    rac_model_registry* registry = rac_get_model_registry();
    if (registry == nullptr) {
        return;
    }

    rac_model_info_t model = {};
    model.id = strdup("system-tts");
    model.name = strdup("Platform TTS");
    model.category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS;
    model.format = RAC_MODEL_FORMAT_UNKNOWN;
    model.framework = RAC_FRAMEWORK_SYSTEM_TTS;
    model.download_url = nullptr;
    model.local_path = strdup("builtin://system-tts");
    model.artifact_info.kind = RAC_ARTIFACT_KIND_BUILT_IN;
    model.download_size = 0;
    model.memory_required = 0;
    model.context_length = 0;
    model.supports_thinking = RAC_FALSE;
    model.tags = nullptr;
    model.tag_count = 0;
    model.description = strdup("Platform's built-in Text-to-Speech using native synthesis.");
    model.source = RAC_MODEL_SOURCE_LOCAL;

    rac_result_t result = rac_model_registry_save(registry, &model);
    if (result == RAC_SUCCESS) {
        RAC_LOG_INFO(LOG_CAT, "Registered built-in model: %s", model.id);
    }

    free(model.id);
    free(model.name);
    free(model.local_path);
    free(model.description);
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_platform_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "Platform Services";
    module_info.version = "1.0.0";
    module_info.description = "Apple platform services (Foundation Models, System TTS)";

    rac_capability_t capabilities[] = {RAC_CAPABILITY_TEXT_GENERATION, RAC_CAPABILITY_TTS};
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 2;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register LLM provider
    rac_service_provider_t llm_provider = {};
    llm_provider.name = state.provider_llm_name;
    llm_provider.capability = RAC_CAPABILITY_TEXT_GENERATION;
    llm_provider.priority = 50;
    llm_provider.can_handle = platform_llm_can_handle;
    llm_provider.create = platform_llm_create;
    llm_provider.user_data = nullptr;

    result = rac_service_register_provider(&llm_provider);
    if (result != RAC_SUCCESS) {
        rac_module_unregister(state.module_id);
        return result;
    }

    // Register TTS provider
    rac_service_provider_t tts_provider = {};
    tts_provider.name = state.provider_tts_name;
    tts_provider.capability = RAC_CAPABILITY_TTS;
    tts_provider.priority = 10;
    tts_provider.can_handle = platform_tts_can_handle;
    tts_provider.create = platform_tts_create;
    tts_provider.user_data = nullptr;

    result = rac_service_register_provider(&tts_provider);
    if (result != RAC_SUCCESS) {
        rac_service_unregister_provider(state.provider_llm_name, RAC_CAPABILITY_TEXT_GENERATION);
        rac_module_unregister(state.module_id);
        return result;
    }

    // Register built-in models
    register_foundation_models_entry();
    register_system_tts_entry();

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Platform backend registered successfully");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_platform_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(state.provider_tts_name, RAC_CAPABILITY_TTS);
    rac_service_unregister_provider(state.provider_llm_name, RAC_CAPABILITY_TEXT_GENERATION);
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Platform backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
