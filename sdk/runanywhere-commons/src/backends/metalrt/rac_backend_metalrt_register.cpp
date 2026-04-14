/**
 * @file rac_backend_metalrt_register.cpp
 * @brief RunAnywhere Core - MetalRT Backend Registration
 *
 * Registers the MetalRT backend with the module and service registries.
 * Provides vtable implementations for LLM, STT, TTS, and VLM service interfaces.
 *
 * MetalRT uses custom Metal GPU kernels for high-performance inference on Apple
 * silicon. Only handles models registered with RAC_FRAMEWORK_METALRT.
 */

#include "rac_llm_metalrt.h"
#include "rac_stt_metalrt.h"
#include "rac_tts_metalrt.h"
#include "rac_vlm_metalrt.h"

#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <mutex>
#include <string>
#include <sys/stat.h>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"

static const char* LOG_CAT = "MetalRT";

// =============================================================================
// PATH RESOLUTION — handle nested directories from tar.gz extraction
// =============================================================================

static std::string resolve_metalrt_model_path(const char* base_path) {
    if (!base_path || base_path[0] == '\0') return {};

    struct stat st;
    std::string config_at_root = std::string(base_path) + "/config.json";
    if (stat(config_at_root.c_str(), &st) == 0 && S_ISREG(st.st_mode)) {
        return std::string(base_path);
    }

    DIR* dir = opendir(base_path);
    if (!dir) return std::string(base_path);

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
#ifdef _DIRENT_HAVE_D_TYPE
        if (entry->d_type != DT_DIR && entry->d_type != DT_UNKNOWN) continue;
#endif
        std::string nested_config = std::string(base_path) + "/" + entry->d_name + "/config.json";
        if (stat(nested_config.c_str(), &st) == 0 && S_ISREG(st.st_mode)) {
            std::string resolved = std::string(base_path) + "/" + entry->d_name;
            closedir(dir);
            RAC_LOG_INFO(LOG_CAT, "Resolved nested model dir: %s -> %s", base_path, resolved.c_str());
            return resolved;
        }
    }
    closedir(dir);

    return std::string(base_path);
}

// =============================================================================
// LLM VTABLE
// =============================================================================

namespace {

static rac_result_t llm_vtable_initialize(void* impl, const char* model_path) {
    // Model already loaded during create
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

static rac_result_t llm_vtable_generate(void* impl, const char* prompt,
                                         const rac_llm_options_t* options,
                                         rac_llm_result_t* out_result) {
    return rac_llm_metalrt_generate(impl, prompt, options, out_result);
}

// Stream adapter: bridge RAC's callback (token, user_data) to MetalRT's (token, is_final, user_data)
struct LLMStreamAdapter {
    rac_llm_stream_callback_fn callback;
    void* user_data;
};

static rac_bool_t llm_stream_adapter_cb(const char* token, rac_bool_t is_final, void* ctx) {
    auto* adapter = static_cast<LLMStreamAdapter*>(ctx);
    (void)is_final;
    if (adapter && adapter->callback) {
        return adapter->callback(token, adapter->user_data);
    }
    return RAC_TRUE;
}

static rac_result_t llm_vtable_generate_stream(void* impl, const char* prompt,
                                                const rac_llm_options_t* options,
                                                rac_llm_stream_callback_fn callback,
                                                void* user_data) {
    LLMStreamAdapter adapter = {callback, user_data};
    return rac_llm_metalrt_generate_stream(impl, prompt, options, llm_stream_adapter_cb, &adapter);
}

static rac_result_t llm_vtable_get_info(void* impl, rac_llm_info_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
    out_info->is_ready = rac_llm_metalrt_is_loaded(impl);
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model = nullptr;
    out_info->context_length = rac_llm_metalrt_context_size(impl);
    return RAC_SUCCESS;
}

static rac_result_t llm_vtable_cancel(void* /*impl*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t llm_vtable_cleanup(void* impl) {
    rac_llm_metalrt_reset(impl);
    return RAC_SUCCESS;
}

static void llm_vtable_destroy(void* impl) {
    rac_llm_metalrt_destroy(impl);
}

static rac_result_t llm_vtable_inject_system_prompt(void* impl, const char* prompt) {
    return rac_llm_metalrt_inject_system_prompt(impl, prompt);
}

static rac_result_t llm_vtable_append_context(void* impl, const char* text) {
    return rac_llm_metalrt_append_context(impl, text);
}

static rac_result_t llm_vtable_generate_from_context(void* impl, const char* query,
                                                      const rac_llm_options_t* options,
                                                      rac_llm_result_t* out_result) {
    return rac_llm_metalrt_generate_from_context(impl, query, options, out_result);
}

static rac_result_t llm_vtable_clear_context(void* impl) {
    return rac_llm_metalrt_clear_context(impl);
}

static const rac_llm_service_ops_t g_metalrt_llm_ops = {
    .initialize = llm_vtable_initialize,
    .generate = llm_vtable_generate,
    .generate_stream = llm_vtable_generate_stream,
    .get_info = llm_vtable_get_info,
    .cancel = llm_vtable_cancel,
    .cleanup = llm_vtable_cleanup,
    .destroy = llm_vtable_destroy,
    .load_lora = nullptr,
    .remove_lora = nullptr,
    .clear_lora = nullptr,
    .get_lora_info = nullptr,
    .inject_system_prompt = llm_vtable_inject_system_prompt,
    .append_context = llm_vtable_append_context,
    .generate_from_context = llm_vtable_generate_from_context,
    .clear_context = llm_vtable_clear_context,
};

// =============================================================================
// STT VTABLE
// =============================================================================

static rac_result_t stt_vtable_initialize(void* impl, const char* model_path) {
    (void)impl;
    (void)model_path;
    return RAC_SUCCESS;
}

static rac_result_t stt_vtable_transcribe(void* impl, const void* audio_data, size_t audio_size,
                                           const rac_stt_options_t* options,
                                           rac_stt_result_t* out_result) {
    return rac_stt_metalrt_transcribe(impl, audio_data, audio_size, options, out_result);
}

static rac_result_t stt_vtable_get_info(void* /*impl*/, rac_stt_info_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = RAC_FALSE;
    return RAC_SUCCESS;
}

static rac_result_t stt_vtable_cleanup(void* /*impl*/) {
    return RAC_SUCCESS;
}

static void stt_vtable_destroy(void* impl) {
    rac_stt_metalrt_destroy(impl);
}

static const rac_stt_service_ops_t g_metalrt_stt_ops = {
    .initialize = stt_vtable_initialize,
    .transcribe = stt_vtable_transcribe,
    .transcribe_stream = nullptr,
    .get_info = stt_vtable_get_info,
    .cleanup = stt_vtable_cleanup,
    .destroy = stt_vtable_destroy,
};

// =============================================================================
// TTS VTABLE
// =============================================================================

static rac_result_t tts_vtable_initialize(void* /*impl*/) {
    return RAC_SUCCESS;
}

static rac_result_t tts_vtable_synthesize(void* impl, const char* text,
                                           const rac_tts_options_t* options,
                                           rac_tts_result_t* out_result) {
    return rac_tts_metalrt_synthesize(impl, text, options, out_result);
}

static rac_result_t tts_vtable_stop(void* /*impl*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t tts_vtable_get_info(void* /*impl*/, rac_tts_info_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;
    return RAC_SUCCESS;
}

static rac_result_t tts_vtable_cleanup(void* /*impl*/) {
    return RAC_SUCCESS;
}

static void tts_vtable_destroy(void* impl) {
    rac_tts_metalrt_destroy(impl);
}

static const rac_tts_service_ops_t g_metalrt_tts_ops = {
    .initialize = tts_vtable_initialize,
    .synthesize = tts_vtable_synthesize,
    .synthesize_stream = nullptr,
    .stop = tts_vtable_stop,
    .get_info = tts_vtable_get_info,
    .cleanup = tts_vtable_cleanup,
    .destroy = tts_vtable_destroy,
};

// =============================================================================
// VLM VTABLE
// =============================================================================

static rac_result_t vlm_vtable_initialize(void* impl, const char* model_path,
                                           const char* mmproj_path) {
    (void)impl;
    (void)model_path;
    (void)mmproj_path;
    return RAC_SUCCESS;
}

static rac_result_t vlm_vtable_process(void* impl, const rac_vlm_image_t* image,
                                        const char* prompt, const rac_vlm_options_t* options,
                                        rac_vlm_result_t* out_result) {
    return rac_vlm_metalrt_process(impl, image, prompt, options, out_result);
}

static rac_result_t vlm_vtable_process_stream(void* impl, const rac_vlm_image_t* image,
                                               const char* prompt,
                                               const rac_vlm_options_t* options,
                                               rac_vlm_stream_callback_fn callback,
                                               void* user_data) {
    return rac_vlm_metalrt_process_stream(impl, image, prompt, options, callback, user_data);
}

static rac_result_t vlm_vtable_get_info(void* /*impl*/, rac_vlm_info_t* out_info) {
    if (!out_info) return RAC_ERROR_NULL_POINTER;
    out_info->is_ready = RAC_TRUE;
    out_info->supports_streaming = RAC_TRUE;
    out_info->supports_multiple_images = RAC_FALSE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    out_info->vision_encoder_type = nullptr;
    return RAC_SUCCESS;
}

static rac_result_t vlm_vtable_cancel(void* /*impl*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t vlm_vtable_cleanup(void* impl) {
    rac_vlm_metalrt_reset(impl);
    return RAC_SUCCESS;
}

static void vlm_vtable_destroy(void* impl) {
    rac_vlm_metalrt_destroy(impl);
}

static const rac_vlm_service_ops_t g_metalrt_vlm_ops = {
    .initialize = vlm_vtable_initialize,
    .process = vlm_vtable_process,
    .process_stream = vlm_vtable_process_stream,
    .get_info = vlm_vtable_get_info,
    .cancel = vlm_vtable_cancel,
    .cleanup = vlm_vtable_cleanup,
    .destroy = vlm_vtable_destroy,
};

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct MetalRTRegistryState {
    std::mutex mutex;
    bool registered = false;
    char module_id[16] = "metalrt";
    char llm_provider[32] = "MetalRTLLM";
    char stt_provider[32] = "MetalRTSTT";
    char tts_provider[32] = "MetalRTTTS";
    char vlm_provider[32] = "MetalRTVLM";
};

MetalRTRegistryState& get_state() {
    static MetalRTRegistryState state;
    return state;
}

// =============================================================================
// CAN_HANDLE — framework-hint only (RAC_FRAMEWORK_METALRT)
// =============================================================================

rac_bool_t metalrt_can_handle(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return RAC_FALSE;

    if (request->framework == RAC_FRAMEWORK_METALRT) {
        RAC_LOG_DEBUG(LOG_CAT, "can_handle: YES (framework=METALRT)");
        return RAC_TRUE;
    }

    RAC_LOG_DEBUG(LOG_CAT, "can_handle: NO (framework=%d, want METALRT=%d)",
                  static_cast<int>(request->framework), RAC_FRAMEWORK_METALRT);
    return RAC_FALSE;
}

// =============================================================================
// SERVICE FACTORIES
// =============================================================================

rac_handle_t metalrt_llm_create(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return nullptr;

    const char* raw_path = request->model_path ? request->model_path : request->identifier;
    if (!raw_path || raw_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "LLM: no model path");
        return nullptr;
    }

    std::string resolved = resolve_metalrt_model_path(raw_path);
    const char* model_path = resolved.c_str();
    RAC_LOG_INFO(LOG_CAT, "Creating LLM service for: %s", model_path);

    rac_handle_t backend = nullptr;
    if (rac_llm_metalrt_create(model_path, &backend) != RAC_SUCCESS) {
        RAC_LOG_ERROR(LOG_CAT, "LLM: failed to create backend");
        return nullptr;
    }

    auto* service = static_cast<rac_llm_service_t*>(malloc(sizeof(rac_llm_service_t)));
    if (!service) {
        rac_llm_metalrt_destroy(backend);
        return nullptr;
    }

    service->ops = &g_metalrt_llm_ops;
    service->impl = backend;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;
    return service;
}

rac_handle_t metalrt_stt_create(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return nullptr;

    const char* raw_path = request->model_path ? request->model_path : request->identifier;
    if (!raw_path || raw_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "STT: no model path");
        return nullptr;
    }

    std::string resolved = resolve_metalrt_model_path(raw_path);
    const char* model_path = resolved.c_str();
    RAC_LOG_INFO(LOG_CAT, "Creating STT service for: %s", model_path);

    rac_handle_t backend = nullptr;
    if (rac_stt_metalrt_create(model_path, &backend) != RAC_SUCCESS) {
        return nullptr;
    }

    auto* service = static_cast<rac_stt_service_t*>(malloc(sizeof(rac_stt_service_t)));
    if (!service) {
        rac_stt_metalrt_destroy(backend);
        return nullptr;
    }

    service->ops = &g_metalrt_stt_ops;
    service->impl = backend;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;
    return service;
}

rac_handle_t metalrt_tts_create(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return nullptr;

    const char* raw_path = request->model_path ? request->model_path : request->identifier;
    if (!raw_path || raw_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "TTS: no model path");
        return nullptr;
    }

    std::string resolved = resolve_metalrt_model_path(raw_path);
    const char* model_path = resolved.c_str();
    RAC_LOG_INFO(LOG_CAT, "Creating TTS service for: %s", model_path);

    rac_handle_t backend = nullptr;
    if (rac_tts_metalrt_create(model_path, &backend) != RAC_SUCCESS) {
        return nullptr;
    }

    auto* service = static_cast<rac_tts_service_t*>(malloc(sizeof(rac_tts_service_t)));
    if (!service) {
        rac_tts_metalrt_destroy(backend);
        return nullptr;
    }

    service->ops = &g_metalrt_tts_ops;
    service->impl = backend;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;
    return service;
}

rac_handle_t metalrt_vlm_create(const rac_service_request_t* request, void* /*user_data*/) {
    if (!request) return nullptr;

    const char* raw_path = request->model_path ? request->model_path : request->identifier;
    if (!raw_path || raw_path[0] == '\0') {
        RAC_LOG_ERROR(LOG_CAT, "VLM: no model path");
        return nullptr;
    }

    std::string resolved = resolve_metalrt_model_path(raw_path);
    const char* model_path = resolved.c_str();
    RAC_LOG_INFO(LOG_CAT, "Creating VLM service for: %s", model_path);

    rac_handle_t backend = nullptr;
    if (rac_vlm_metalrt_create(model_path, &backend) != RAC_SUCCESS) {
        return nullptr;
    }

    auto* service = static_cast<rac_vlm_service_t*>(malloc(sizeof(rac_vlm_service_t)));
    if (!service) {
        rac_vlm_metalrt_destroy(backend);
        return nullptr;
    }

    service->ops = &g_metalrt_vlm_ops;
    service->impl = backend;
    service->model_id = request->identifier ? strdup(request->identifier) : nullptr;
    return service;
}

}  // namespace

// =============================================================================
// REGISTRATION API
// =============================================================================

extern "C" {

rac_result_t rac_backend_metalrt_register(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (state.registered) {
        return RAC_ERROR_MODULE_ALREADY_REGISTERED;
    }

    // Register module
    rac_module_info_t module_info = {};
    module_info.id = state.module_id;
    module_info.name = "MetalRT";
    module_info.version = "1.0.0";
    module_info.description = "High-performance inference using custom Metal GPU kernels (Apple only)";

    rac_capability_t capabilities[] = {
        RAC_CAPABILITY_TEXT_GENERATION,
        RAC_CAPABILITY_STT,
        RAC_CAPABILITY_TTS,
        RAC_CAPABILITY_VISION_LANGUAGE,
    };
    module_info.capabilities = capabilities;
    module_info.num_capabilities = 4;

    rac_result_t result = rac_module_register(&module_info);
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return result;
    }

    // Register LLM provider
    {
        rac_service_provider_t provider = {};
        provider.name = state.llm_provider;
        provider.capability = RAC_CAPABILITY_TEXT_GENERATION;
        provider.priority = 100;
        provider.can_handle = metalrt_can_handle;
        provider.create = metalrt_llm_create;
        provider.user_data = nullptr;

        result = rac_service_register_provider(&provider);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to register LLM provider: %d", result);
        }
    }

    // Register STT provider
    {
        rac_service_provider_t provider = {};
        provider.name = state.stt_provider;
        provider.capability = RAC_CAPABILITY_STT;
        provider.priority = 100;
        provider.can_handle = metalrt_can_handle;
        provider.create = metalrt_stt_create;
        provider.user_data = nullptr;

        result = rac_service_register_provider(&provider);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to register STT provider: %d", result);
        }
    }

    // Register TTS provider
    {
        rac_service_provider_t provider = {};
        provider.name = state.tts_provider;
        provider.capability = RAC_CAPABILITY_TTS;
        provider.priority = 100;
        provider.can_handle = metalrt_can_handle;
        provider.create = metalrt_tts_create;
        provider.user_data = nullptr;

        result = rac_service_register_provider(&provider);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to register TTS provider: %d", result);
        }
    }

    // Register VLM provider
    {
        rac_service_provider_t provider = {};
        provider.name = state.vlm_provider;
        provider.capability = RAC_CAPABILITY_VISION_LANGUAGE;
        provider.priority = 100;
        provider.can_handle = metalrt_can_handle;
        provider.create = metalrt_vlm_create;
        provider.user_data = nullptr;

        result = rac_service_register_provider(&provider);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to register VLM provider: %d", result);
        }
    }

    state.registered = true;
    RAC_LOG_INFO(LOG_CAT, "Backend registered successfully (LLM, STT, TTS, VLM)");
    return RAC_SUCCESS;
}

rac_result_t rac_backend_metalrt_unregister(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);

    if (!state.registered) {
        return RAC_ERROR_MODULE_NOT_FOUND;
    }

    rac_service_unregister_provider(state.llm_provider, RAC_CAPABILITY_TEXT_GENERATION);
    rac_service_unregister_provider(state.stt_provider, RAC_CAPABILITY_STT);
    rac_service_unregister_provider(state.tts_provider, RAC_CAPABILITY_TTS);
    rac_service_unregister_provider(state.vlm_provider, RAC_CAPABILITY_VISION_LANGUAGE);
    rac_module_unregister(state.module_id);

    state.registered = false;
    RAC_LOG_INFO(LOG_CAT, "Backend unregistered");
    return RAC_SUCCESS;
}

}  // extern "C"
