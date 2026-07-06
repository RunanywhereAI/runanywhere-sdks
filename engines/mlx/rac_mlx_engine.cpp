/**
 * @file rac_mlx_engine.cpp
 * @brief MLX engine implementation backed by Swift callbacks.
 */

#include "rac_mlx_callbacks_internal.h"

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <new>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_plugin_entry_mlx.h"

#define LOG_CAT "MLX"

namespace {

std::mutex g_callbacks_mutex;
rac_mlx_callbacks_t g_callbacks = {};
bool g_callbacks_set = false;

struct MlxSession {
    rac_mlx_session_kind_t kind = RAC_MLX_SESSION_KIND_LLM;
    rac_handle_t swift_handle = nullptr;
    std::string model_id;
    std::string model_path;
    bool initialized = false;
};

MlxSession* as_session(void* impl) {
    return static_cast<MlxSession*>(impl);
}

rac_result_t require_session(void* impl, MlxSession** out) {
    if (!impl || !out) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out = as_session(impl);
    if (*out == nullptr || (*out)->swift_handle == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    return RAC_SUCCESS;
}

rac_result_t create_session(rac_mlx_session_kind_t kind, const char* model_id,
                            const char* config_json, void** out_impl) {
    if (!out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;

    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) || callbacks.create == nullptr) {
        RAC_LOG_WARNING(LOG_CAT, "MLX callbacks are not registered");
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    rac_handle_t swift_handle = nullptr;
    rac_result_t rc =
        callbacks.create(kind, model_id, config_json, &swift_handle, callbacks.user_data);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (swift_handle == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    auto* session = new (std::nothrow) MlxSession();
    if (!session) {
        if (callbacks.destroy) {
            callbacks.destroy(swift_handle, callbacks.user_data);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    session->kind = kind;
    session->swift_handle = swift_handle;
    session->model_id = model_id ? model_id : "";
    *out_impl = session;
    return RAC_SUCCESS;
}

rac_result_t mlx_initialize(void* impl, const char* model_path) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!model_path || model_path[0] == '\0') {
        return RAC_ERROR_INVALID_PATH;
    }

    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.initialize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    std::string load_path = model_path;
    const std::filesystem::path path(load_path);
    if (path.has_extension()) {
        const std::string extension = path.extension().string();
        if (extension == ".safetensors" || extension == ".json") {
            load_path = path.parent_path().empty() ? load_path : path.parent_path().string();
        }
    }

    rc = callbacks.initialize(session->swift_handle, load_path.c_str(), callbacks.user_data);
    if (rc == RAC_SUCCESS) {
        session->model_path = load_path;
        session->initialized = true;
    }
    return rc;
}

rac_result_t mlx_cancel(void* impl) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) || callbacks.cancel == nullptr) {
        return RAC_SUCCESS;
    }
    return callbacks.cancel(session->swift_handle, callbacks.user_data);
}

rac_result_t mlx_cleanup(void* impl) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.cleanup == nullptr) {
        session->initialized = false;
        return RAC_SUCCESS;
    }
    rc = callbacks.cleanup(session->swift_handle, callbacks.user_data);
    if (rc == RAC_SUCCESS) {
        session->initialized = false;
    }
    return rc;
}

void mlx_destroy(void* impl) {
    auto* session = as_session(impl);
    if (!session) {
        return;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) && callbacks.destroy) {
        callbacks.destroy(session->swift_handle, callbacks.user_data);
    }
    delete session;
}

rac_result_t llm_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t llm_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                          rac_llm_result_t* out_result) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.llm_generate == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.llm_generate(session->swift_handle, prompt, options, out_result,
                                  callbacks.user_data);
}

rac_result_t llm_generate_stream(void* impl, const char* prompt, const rac_llm_options_t* options,
                                 rac_llm_stream_callback_fn callback, void* user_data) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.llm_generate_stream == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.llm_generate_stream(session->swift_handle, prompt, options, callback,
                                         user_data, callbacks.user_data);
}

rac_result_t llm_get_info(void* impl, rac_llm_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model =
        session && !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->context_length = 0;
    return RAC_SUCCESS;
}

rac_result_t llm_create(const char* model_id, const char* config_json, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_LLM, model_id, config_json, out_impl);
}

rac_result_t vlm_initialize(void* impl, const char* model_path, const char* mmproj_path) {
    (void)mmproj_path;
    return mlx_initialize(impl, model_path);
}

rac_result_t vlm_process(void* impl, const rac_vlm_image_t* image, const char* prompt,
                         const rac_vlm_options_t* options, rac_vlm_result_t* out_result) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!image || !prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.vlm_process == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.vlm_process(session->swift_handle, image, prompt, options, out_result,
                                 callbacks.user_data);
}

rac_result_t vlm_process_stream(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                const rac_vlm_options_t* options,
                                rac_vlm_stream_callback_fn callback, void* user_data) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!image || !prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.vlm_process_stream == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.vlm_process_stream(session->swift_handle, image, prompt, options, callback,
                                        user_data, callbacks.user_data);
}

rac_result_t vlm_get_info(void* impl, rac_vlm_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->current_model =
        session && !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    out_info->supports_multiple_images = RAC_TRUE;
    out_info->vision_encoder_type = "mlx";
    return RAC_SUCCESS;
}

rac_result_t vlm_create(const char* model_id, const char* config_json, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_VLM, model_id, config_json, out_impl);
}

rac_result_t embedding_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t embedding_embed_batch(void* impl, const char* const* texts, size_t num_texts,
                                   const rac_embeddings_options_t* options,
                                   rac_embeddings_result_t* out_result) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!texts || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.embed_batch == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.embed_batch(session->swift_handle, texts, num_texts, options, out_result,
                                 callbacks.user_data);
}

rac_result_t embedding_embed(void* impl, const char* text, const rac_embeddings_options_t* options,
                             rac_embeddings_result_t* out_result) {
    if (!text) {
        return RAC_ERROR_NULL_POINTER;
    }
    const char* texts[] = {text};
    return embedding_embed_batch(impl, texts, 1, options, out_result);
}

rac_result_t embedding_get_info(void* impl, rac_embeddings_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    if (!session || !session->swift_handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
        callbacks.embedding_info != nullptr) {
        return callbacks.embedding_info(session->swift_handle, out_info, callbacks.user_data);
    }
    out_info->is_ready = session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->dimension = 0;
    out_info->max_tokens = RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS;
    return RAC_SUCCESS;
}

rac_result_t embedding_create(const char* model_id, const char* config_json, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_EMBEDDINGS, model_id, config_json, out_impl);
}

rac_result_t stt_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t stt_transcribe(void* impl, const void* audio_data, size_t audio_size,
                            const rac_stt_options_t* options, rac_stt_result_t* out_result) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!audio_data || audio_size == 0 || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.stt_transcribe == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.stt_transcribe(session->swift_handle, audio_data, audio_size, options,
                                    out_result, callbacks.user_data);
}

rac_result_t stt_transcribe_stream(void* impl, const void* audio_data, size_t audio_size,
                                   const rac_stt_options_t* options,
                                   rac_stt_stream_callback_t callback, void* user_data) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!audio_data || audio_size == 0 || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.stt_transcribe_stream == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return callbacks.stt_transcribe_stream(session->swift_handle, audio_data, audio_size, options,
                                           callback, user_data, callbacks.user_data);
}

rac_result_t stt_get_info(void* impl, rac_stt_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    if (session && session->swift_handle) {
        rac_mlx_callbacks_t callbacks = {};
        if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
            callbacks.stt_info != nullptr) {
            return callbacks.stt_info(session->swift_handle, out_info, callbacks.user_data);
        }
    }
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->current_model =
        session && !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t stt_create(const char* model_id, const char* config_json, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_STT, model_id, config_json, out_impl);
}

rac_result_t tts_initialize(void* impl) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    const std::string& load_path = !session->model_path.empty() ? session->model_path
                                                                : session->model_id;
    if (load_path.empty()) {
        return RAC_ERROR_INVALID_PATH;
    }
    return mlx_initialize(impl, load_path.c_str());
}

rac_result_t tts_synthesize(void* impl, const char* text, const rac_tts_options_t* options,
                            rac_tts_result_t* out_result) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!text || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.tts_synthesize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    return callbacks.tts_synthesize(session->swift_handle, text, options, out_result,
                                    callbacks.user_data);
}

rac_result_t tts_synthesize_stream(void* impl, const char* text, const rac_tts_options_t* options,
                                   rac_tts_stream_callback_t callback, void* user_data) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!text || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.tts_synthesize_stream == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    return callbacks.tts_synthesize_stream(session->swift_handle, text, options, callback,
                                           user_data, callbacks.user_data);
}

rac_result_t tts_stop(void* impl) {
    MlxSession* session = nullptr;
    rac_result_t rc = require_session(impl, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
        callbacks.tts_stop != nullptr) {
        return callbacks.tts_stop(session->swift_handle, callbacks.user_data);
    }
    return mlx_cancel(impl);
}

rac_result_t tts_get_info(void* impl, rac_tts_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    if (session && session->swift_handle) {
        rac_mlx_callbacks_t callbacks = {};
        if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
            callbacks.tts_info != nullptr) {
            return callbacks.tts_info(session->swift_handle, out_info, callbacks.user_data);
        }
    }
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;
    return RAC_SUCCESS;
}

rac_result_t tts_create(const char* model_id, const char* config_json, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_TTS, model_id, config_json, out_impl);
}

rac_result_t mlx_capability_check(void) {
#if !defined(__APPLE__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#else
    return rac_mlx_is_available() == RAC_TRUE ? RAC_SUCCESS : RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

}  // namespace

namespace runanywhere::commons::mlx {

bool snapshot_callbacks(rac_mlx_callbacks_t* out) {
    if (!out) {
        return false;
    }
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    if (!g_callbacks_set) {
        return false;
    }
    *out = g_callbacks;
    return true;
}

}  // namespace runanywhere::commons::mlx

extern "C" {

rac_result_t rac_mlx_set_callbacks(const rac_mlx_callbacks_t* callbacks) {
    if (!callbacks || callbacks->struct_size != sizeof(rac_mlx_callbacks_t) ||
        callbacks->create == nullptr || callbacks->initialize == nullptr ||
        callbacks->llm_generate == nullptr || callbacks->llm_generate_stream == nullptr ||
        callbacks->vlm_process == nullptr || callbacks->vlm_process_stream == nullptr ||
        callbacks->embed_batch == nullptr || callbacks->stt_transcribe == nullptr ||
        callbacks->tts_synthesize == nullptr || callbacks->destroy == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_callbacks = *callbacks;
    g_callbacks_set = true;
    RAC_LOG_INFO(LOG_CAT, "Swift callbacks registered for MLX");
    return RAC_SUCCESS;
}

rac_bool_t rac_mlx_is_available(void) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    return g_callbacks_set && g_callbacks.create != nullptr && g_callbacks.initialize != nullptr
               ? RAC_TRUE
               : RAC_FALSE;
}

const rac_llm_service_ops_t g_mlx_llm_ops = {
    .initialize = llm_initialize,
    .generate = llm_generate,
    .generate_stream = llm_generate_stream,
    .get_info = llm_get_info,
    .cancel = mlx_cancel,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .load_lora = nullptr,
    .remove_lora = nullptr,
    .clear_lora = nullptr,
    .get_lora_info = nullptr,
    .inject_system_prompt = nullptr,
    .append_context = nullptr,
    .generate_from_context = nullptr,
    .clear_context = nullptr,
    .create = llm_create,
};

const rac_vlm_service_ops_t g_mlx_vlm_ops = {
    .initialize = vlm_initialize,
    .process = vlm_process,
    .process_stream = vlm_process_stream,
    .get_info = vlm_get_info,
    .cancel = mlx_cancel,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .create = vlm_create,
};

const rac_embeddings_service_ops_t g_mlx_embeddings_ops = {
    .initialize = embedding_initialize,
    .embed = embedding_embed,
    .embed_batch = embedding_embed_batch,
    .get_info = embedding_get_info,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .create = embedding_create,
};

const rac_stt_service_ops_t g_mlx_stt_ops = {
    .initialize = stt_initialize,
    .transcribe = stt_transcribe,
    .transcribe_stream = stt_transcribe_stream,
    .get_info = stt_get_info,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .create = stt_create,
    .get_languages = nullptr,
    .detect_language = nullptr,
    .stream_create = nullptr,
    .stream_feed_audio_chunk = nullptr,
    .stream_destroy = nullptr,
};

const rac_tts_service_ops_t g_mlx_tts_ops = {
    .initialize = tts_initialize,
    .synthesize = tts_synthesize,
    .synthesize_stream = tts_synthesize_stream,
    .stop = tts_stop,
    .get_info = tts_get_info,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .create = tts_create,
    .get_languages = nullptr,
};

static const rac_runtime_id_t k_mlx_runtimes[] = {
    RAC_RUNTIME_CPU,
    RAC_RUNTIME_METAL,
};

static const uint32_t k_mlx_formats[] = {
    RAC_MODEL_FORMAT_ID_SAFETENSORS,
    RAC_MODEL_FORMAT_ID_FOLDER,
};

static const rac_primitive_t k_mlx_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_EMBED,
    RAC_PRIMITIVE_VLM,
};

static const rac_engine_manifest_t k_mlx_manifest = {
    .name = "mlx",
    .display_name = "MLX",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_mlx",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 100,
    .capability_flags = 0,
    .primitives = k_mlx_primitives,
    .primitives_count = sizeof(k_mlx_primitives) / sizeof(k_mlx_primitives[0]),
    .runtimes = k_mlx_runtimes,
    .runtimes_count = sizeof(k_mlx_runtimes) / sizeof(k_mlx_runtimes[0]),
    .formats = k_mlx_formats,
    .formats_count = sizeof(k_mlx_formats) / sizeof(k_mlx_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_mlx_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_mlx_manifest),
    /* capability_check */ mlx_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_mlx_llm_ops,
    /* stt_ops          */ &g_mlx_stt_ops,
    /* tts_ops          */ &g_mlx_tts_ops,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ &g_mlx_embeddings_ops,
    /* vlm_ops          */ &g_mlx_vlm_ops,
    /* diffusion_ops    */ nullptr,

    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(mlx) {
    return rac_engine_entry_with_manifest(&k_mlx_manifest, &g_mlx_engine_vtable);
}

}  // extern "C"
