/**
 * @file rac_mlx_engine.cpp
 * @brief MLX engine implementation backed by Swift callbacks.
 */

#include "rac_mlx_callbacks_internal.h"

#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <new>
#include <string>

#include "common/rac_engine_unavailable.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diarization/rac_diarization_service.h"
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
ra_mlx_clear_cancel_fn g_clear_cancel = nullptr;
void* g_clear_cancel_user_data = nullptr;

struct MlxSession {
    // Normal operations remain serialized, but interrupt callbacks must not
    // take this mutex: an active Swift inference callback owns it until the
    // callback returns and relies on cancel/stop being callable concurrently.
    std::mutex operation_mutex;
    std::mutex state_mutex;
    std::condition_variable interrupts_finished;
    rac_mlx_session_kind_t kind = RAC_MLX_SESSION_KIND_LLM;
    rac_handle_t swift_handle = nullptr;
    std::string model_id;
    std::string model_path;
    size_t interrupts_in_flight = 0;
    bool initialized = false;
    bool operation_active = false;
    bool closing = false;
};

MlxSession* as_session(void* impl) {
    return static_cast<MlxSession*>(impl);
}

rac_result_t lock_session(void* impl, std::unique_lock<std::mutex>& lock, MlxSession** out) {
    if (!impl || !out) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* session = as_session(impl);
    if (session == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    lock = std::unique_lock<std::mutex>(session->operation_mutex);
    {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        if (session->closing || session->swift_handle == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
    }
    *out = session;
    return RAC_SUCCESS;
}

class MlxCancellableOperation {
   public:
    MlxCancellableOperation() = default;

    rac_result_t begin(void* impl) {
        if (!impl) {
            return RAC_ERROR_NULL_POINTER;
        }
        session_ = as_session(impl);
        operation_lock_ = std::unique_lock<std::mutex>(session_->operation_mutex);
        {
            std::lock_guard<std::mutex> state_lock(session_->state_mutex);
            if (session_->closing || session_->swift_handle == nullptr) {
                session_ = nullptr;
                return RAC_ERROR_INVALID_HANDLE;
            }
            swift_handle_ = session_->swift_handle;
        }
        // Clear only while interrupts are filtered. Once operation_active is
        // published, every cancellation belongs to this admitted operation
        // and Swift must not reset it at inference entry.
        runanywhere::commons::mlx::clear_cancel(swift_handle_);
        {
            std::lock_guard<std::mutex> state_lock(session_->state_mutex);
            if (session_->closing) {
                session_ = nullptr;
                return RAC_ERROR_INVALID_HANDLE;
            }
            session_->operation_active = true;
        }
        return RAC_SUCCESS;
    }

    ~MlxCancellableOperation() {
        if (!session_) {
            return;
        }
        {
            std::unique_lock<std::mutex> state_lock(session_->state_mutex);
            session_->operation_active = false;
            session_->interrupts_finished.wait(state_lock,
                                               [&] { return session_->interrupts_in_flight == 0; });
        }
        // All interrupts admitted for the completed callback have returned,
        // and new ones are filtered by operation_active=false. Resetting here
        // cannot erase a current operation or leak cancellation to a successor.
        runanywhere::commons::mlx::clear_cancel(swift_handle_);
    }

    rac_handle_t swift_handle() const { return swift_handle_; }

    MlxCancellableOperation(const MlxCancellableOperation&) = delete;
    MlxCancellableOperation& operator=(const MlxCancellableOperation&) = delete;

   private:
    MlxSession* session_ = nullptr;
    rac_handle_t swift_handle_ = nullptr;
    std::unique_lock<std::mutex> operation_lock_;
};

template <typename Callback>
rac_result_t dispatch_interrupt(void* impl, Callback callback, void* user_data) {
    if (!impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (callback == nullptr) {
        return RAC_SUCCESS;
    }

    auto* session = as_session(impl);
    rac_handle_t swift_handle = nullptr;
    {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        if (session->closing || session->swift_handle == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        // A late interrupt after the Swift callback returned belongs to the
        // completed operation. Ignoring it here prevents poisoning the next
        // inference on this session.
        if (!session->operation_active) {
            return RAC_SUCCESS;
        }
        swift_handle = session->swift_handle;
        session->interrupts_in_flight += 1;
    }

    const rac_result_t rc = callback(swift_handle, user_data);

    {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        session->interrupts_in_flight -= 1;
    }
    session->interrupts_finished.notify_all();
    return rc;
}

std::string normalized_load_path(const char* model_path) {
    std::string load_path = model_path ? model_path : "";
    const std::filesystem::path path(load_path);
    if (path.has_extension()) {
        const std::string extension = path.extension().string();
        if (extension == ".safetensors" || extension == ".json") {
            load_path = path.parent_path().empty() ? load_path : path.parent_path().string();
        }
    }
    return load_path;
}

rac_result_t create_session(rac_mlx_session_kind_t kind, const char* model_id, void** out_impl) {
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
    rac_result_t rc = callbacks.create(kind, model_id, &swift_handle, callbacks.user_data);
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
    if (!model_path || model_path[0] == '\0') {
        return RAC_ERROR_INVALID_PATH;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.initialize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    const std::string load_path = normalized_load_path(model_path);
    rc = callbacks.initialize(session->swift_handle, load_path.c_str(), callbacks.user_data);
    if (rc == RAC_SUCCESS) {
        session->model_path = load_path;
        session->initialized = true;
    }
    return rc;
}

rac_result_t mlx_cancel(void* impl) {
    if (!impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) || callbacks.cancel == nullptr) {
        return RAC_SUCCESS;
    }
    return dispatch_interrupt(impl, callbacks.cancel, callbacks.user_data);
}

rac_result_t mlx_cleanup(void* impl) {
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
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
    rac_handle_t swift_handle = nullptr;
    {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        session->closing = true;
    }
    {
        std::unique_lock<std::mutex> operation_lock(session->operation_mutex);
        std::unique_lock<std::mutex> state_lock(session->state_mutex);
        session->interrupts_finished.wait(state_lock,
                                          [&] { return session->interrupts_in_flight == 0; });
        swift_handle = session->swift_handle;
        session->swift_handle = nullptr;
        session->initialized = false;
        session->model_path.clear();
    }
    if (swift_handle != nullptr && runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
        callbacks.destroy) {
        callbacks.destroy(swift_handle, callbacks.user_data);
    }
    delete session;
}

rac_result_t llm_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t llm_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                          rac_llm_result_t* out_result) {
    if (!prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.llm_generate == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.llm_generate(operation.swift_handle(), prompt, options, out_result,
                                  callbacks.user_data);
}

rac_result_t llm_generate_stream(void* impl, const char* prompt, const rac_llm_options_t* options,
                                 rac_llm_stream_callback_fn callback, void* user_data) {
    if (!prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.llm_generate_stream == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.llm_generate_stream(operation.swift_handle(), prompt, options, callback,
                                         user_data, callbacks.user_data);
}

rac_result_t llm_get_info(void* impl, rac_llm_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    std::unique_lock<std::mutex> lock;
    if (session) {
        lock = std::unique_lock<std::mutex>(session->operation_mutex);
    }
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->supports_streaming = RAC_TRUE;
    out_info->current_model =
        session && !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->context_length = 0;
    return RAC_SUCCESS;
}

rac_result_t llm_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_LLM, model_id, out_impl);
}

rac_result_t vlm_initialize(void* impl, const char* model_path, const char* mmproj_path) {
    (void)mmproj_path;
    return mlx_initialize(impl, model_path);
}

rac_result_t vlm_process(void* impl, const rac_vlm_image_t* image, const char* prompt,
                         const rac_vlm_options_t* options, rac_vlm_result_t* out_result) {
    if (!image || !prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.vlm_process == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.vlm_process(operation.swift_handle(), image, prompt, options, out_result,
                                 callbacks.user_data);
}

rac_result_t vlm_process_stream(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                const rac_vlm_options_t* options,
                                rac_vlm_stream_callback_fn callback, void* user_data) {
    if (!image || !prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.vlm_process_stream == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.vlm_process_stream(operation.swift_handle(), image, prompt, options, callback,
                                        user_data, callbacks.user_data);
}

rac_result_t vlm_get_info(void* impl, rac_vlm_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    std::unique_lock<std::mutex> lock;
    if (session) {
        lock = std::unique_lock<std::mutex>(session->operation_mutex);
    }
    out_info->is_ready = session && session->initialized ? RAC_TRUE : RAC_FALSE;
    out_info->current_model =
        session && !session->model_id.empty() ? session->model_id.c_str() : nullptr;
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    out_info->supports_multiple_images = RAC_TRUE;
    out_info->vision_encoder_type = "mlx";
    return RAC_SUCCESS;
}

rac_result_t vlm_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_VLM, model_id, out_impl);
}

rac_result_t embedding_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t embedding_embed_batch(void* impl, const char* const* texts, size_t num_texts,
                                   const rac_embeddings_options_t* options,
                                   rac_embeddings_result_t* out_result) {
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
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
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
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

rac_result_t embedding_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_EMBEDDINGS, model_id, out_impl);
}

rac_result_t diarization_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t diarization_diarize(void* impl, const float* samples, size_t sample_count,
                                 const rac_diarization_options_t* options,
                                 rac_diarization_result_t* out_result) {
    if (!samples || sample_count == 0 || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.diarize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    const rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.diarize(session->swift_handle, samples, sample_count, options, out_result,
                             callbacks.user_data);
}

rac_result_t diarization_stream_create(void* impl, const rac_diarization_options_t* options,
                                       rac_handle_t* out_stream_handle) {
    if (!out_stream_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_stream_handle = nullptr;
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.diarization_stream_create == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    const rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.diarization_stream_create(session->swift_handle, options, out_stream_handle,
                                                callbacks.user_data);
}

rac_result_t diarization_stream_feed(void* impl, rac_handle_t stream_handle,
                                     const float* samples, size_t sample_count,
                                     rac_diarization_stream_callback_t callback, void* user_data) {
    if (!stream_handle || !callback || (sample_count > 0 && !samples)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.diarization_stream_feed == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    const rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.diarization_stream_feed(session->swift_handle, stream_handle, samples,
                                              sample_count, callback, user_data,
                                              callbacks.user_data);
}

rac_result_t diarization_stream_destroy(void* impl, rac_handle_t stream_handle) {
    if (!stream_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.diarization_stream_destroy == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    const rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.diarization_stream_destroy(session->swift_handle, stream_handle,
                                                 callbacks.user_data);
}

rac_result_t diarization_create(const char* model_id, const char* /*config_json*/,
                                void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_DIARIZATION, model_id, out_impl);
}

rac_result_t stt_initialize(void* impl, const char* model_path) {
    return mlx_initialize(impl, model_path);
}

rac_result_t stt_transcribe(void* impl, const void* audio_data, size_t audio_size,
                            const rac_stt_options_t* options, rac_stt_result_t* out_result) {
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
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
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
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
    std::unique_lock<std::mutex> lock;
    if (session) {
        lock = std::unique_lock<std::mutex>(session->operation_mutex);
    }
    bool session_available = false;
    if (session) {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        session_available = !session->closing && session->swift_handle != nullptr;
    }
    if (session_available) {
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

rac_result_t stt_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_STT, model_id, out_impl);
}

rac_result_t tts_initialize(void* impl) {
    MlxSession* session = nullptr;
    std::unique_lock<std::mutex> lock;
    rac_result_t rc = lock_session(impl, lock, &session);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    const std::string& load_path =
        !session->model_path.empty() ? session->model_path : session->model_id;
    if (load_path.empty()) {
        return RAC_ERROR_INVALID_PATH;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.initialize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    rc = callbacks.initialize(session->swift_handle, load_path.c_str(), callbacks.user_data);
    if (rc == RAC_SUCCESS) {
        session->model_path = load_path;
        session->initialized = true;
    }
    return rc;
}

rac_result_t tts_synthesize(void* impl, const char* text, const rac_tts_options_t* options,
                            rac_tts_result_t* out_result) {
    if (!text || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.tts_synthesize == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.tts_synthesize(operation.swift_handle(), text, options, out_result,
                                    callbacks.user_data);
}

rac_result_t tts_synthesize_stream(void* impl, const char* text, const rac_tts_options_t* options,
                                   rac_tts_stream_callback_t callback, void* user_data) {
    if (!text || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (!runanywhere::commons::mlx::snapshot_callbacks(&callbacks) ||
        callbacks.tts_synthesize_stream == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    MlxCancellableOperation operation;
    const rac_result_t rc = operation.begin(impl);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    return callbacks.tts_synthesize_stream(operation.swift_handle(), text, options, callback,
                                           user_data, callbacks.user_data);
}

rac_result_t tts_stop(void* impl) {
    if (!impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_mlx_callbacks_t callbacks = {};
    if (runanywhere::commons::mlx::snapshot_callbacks(&callbacks) &&
        callbacks.tts_stop != nullptr) {
        return dispatch_interrupt(impl, callbacks.tts_stop, callbacks.user_data);
    }
    if (callbacks.cancel != nullptr) {
        return dispatch_interrupt(impl, callbacks.cancel, callbacks.user_data);
    }
    return RAC_SUCCESS;
}

rac_result_t tts_get_info(void* impl, rac_tts_info_t* out_info) {
    if (!out_info) {
        return RAC_ERROR_NULL_POINTER;
    }
    MlxSession* session = as_session(impl);
    std::unique_lock<std::mutex> lock;
    if (session) {
        lock = std::unique_lock<std::mutex>(session->operation_mutex);
    }
    bool session_available = false;
    if (session) {
        std::lock_guard<std::mutex> state_lock(session->state_mutex);
        session_available = !session->closing && session->swift_handle != nullptr;
    }
    if (session_available) {
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

rac_result_t tts_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    return create_session(RAC_MLX_SESSION_KIND_TTS, model_id, out_impl);
}

rac_result_t mlx_capability_check(void) {
    return rac_engine_unavailable_capability(
#if defined(__APPLE__)
        1,
#else
        0,
#endif
        rac_mlx_is_available() == RAC_TRUE ? 1 : 0);
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

void clear_cancel(rac_handle_t handle) {
    ra_mlx_clear_cancel_fn callback = nullptr;
    void* user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_callbacks_mutex);
        callback = g_clear_cancel;
        user_data = g_clear_cancel_user_data;
    }
    if (callback) {
        callback(handle, user_data);
    }
}

}  // namespace runanywhere::commons::mlx

extern "C" {

rac_result_t ra_mlx_set_clear_cancel_callback(ra_mlx_clear_cancel_fn callback, void* user_data) {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_clear_cancel = callback;
    g_clear_cancel_user_data = user_data;
    return RAC_SUCCESS;
}

rac_result_t rac_mlx_set_callbacks(const rac_mlx_callbacks_t* callbacks) {
    if (!callbacks || callbacks->struct_size != sizeof(rac_mlx_callbacks_t) ||
        callbacks->create == nullptr || callbacks->initialize == nullptr ||
        callbacks->llm_generate == nullptr || callbacks->llm_generate_stream == nullptr ||
        callbacks->vlm_process == nullptr || callbacks->vlm_process_stream == nullptr ||
        callbacks->embed_batch == nullptr || callbacks->stt_transcribe == nullptr ||
        callbacks->tts_synthesize == nullptr || callbacks->diarize == nullptr ||
        callbacks->diarization_stream_create == nullptr ||
        callbacks->diarization_stream_feed == nullptr ||
        callbacks->diarization_stream_destroy == nullptr || callbacks->destroy == nullptr) {
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

const rac_diarization_service_ops_t g_mlx_diarization_ops = {
    .initialize = diarization_initialize,
    .diarize = diarization_diarize,
    .stream_create = diarization_stream_create,
    .stream_feed_audio_chunk = diarization_stream_feed,
    .stream_destroy = diarization_stream_destroy,
    .cleanup = mlx_cleanup,
    .destroy = mlx_destroy,
    .create = diarization_create,
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
    RAC_PRIMITIVE_GENERATE_TEXT, RAC_PRIMITIVE_TRANSCRIBE, RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_EMBED,         RAC_PRIMITIVE_VLM,        RAC_PRIMITIVE_DIARIZE,
};

static const rac_engine_manifest_t k_mlx_manifest = {
    .name = "mlx",
    .display_name = "MLX",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_mlx",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 110,
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
    /* diarization_ops  */ &g_mlx_diarization_ops,
    /* segmentation_ops */ nullptr,

    /* reserved_slot_2..9 */
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
