/**
 * @file qhexrt_tts_ops.cpp
 * @brief TTS (RAC_PRIMITIVE_SYNTHESIZE) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in routable builds. Maps `rac_tts_service_ops_t` onto
 * `qhx_generate_ex` with a text input (QHexRT MeloTTS family). QHexRT returns the
 * full mono float32 waveform; output is emitted as RAC_AUDIO_FORMAT_PCM. QHexRT
 * produces the waveform in one shot, so synthesize_stream delivers it as a
 * single callback invocation rather than incremental chunks.
 */

#include "qhexrt_session.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) {
    return static_cast<Session*>(impl);
}

// Copies the QHexRT float32 waveform into a fresh rac_alloc buffer (freed by
// the caller via rac_free). Returns false on allocation failure.
bool copy_waveform(const qhx_output& o, void** out_data, size_t* out_bytes) {
    *out_data = nullptr;
    *out_bytes = 0;
    if (o.audio == nullptr || o.n_audio <= 0) {
        return true;  // empty waveform is valid (NULL/0)
    }
    size_t bytes = static_cast<size_t>(o.n_audio) * sizeof(float);
    void* buf = rac_alloc(bytes);
    if (buf == nullptr) {
        return false;
    }
    std::memcpy(buf, o.audio, bytes);
    *out_data = buf;
    *out_bytes = bytes;
    return true;
}

int64_t duration_ms(const qhx_output& o) {
    if (o.n_audio <= 0 || o.sample_rate == 0) {
        return 0;
    }
    return static_cast<int64_t>(o.n_audio) * 1000 / static_cast<int64_t>(o.sample_rate);
}

struct StopCtx {
    Session* session;
    uint64_t request_id;
    bool cancelled = false;
};

int should_cancel_trampoline(void* user) {
    auto* c = static_cast<StopCtx*>(user);
    return c != nullptr && c->session != nullptr &&
                   c->session->tts_requests.is_cancelled(c->request_id)
               ? 1
               : 0;
}

int stop_trampoline(void* user, const char* /*utf8*/, int /*len*/, int /*tok*/, int /*is_final*/) {
    auto* c = static_cast<StopCtx*>(user);
    if (c != nullptr && c->session != nullptr &&
        c->session->tts_requests.is_cancelled(c->request_id)) {
        c->cancelled = true;
        return 0;  // honor stop()
    }
    return 1;
}

class TtsRequestScope {
   public:
    explicit TtsRequestScope(Session* session)
        : session_(session), id_(session != nullptr ? session->tts_requests.begin() : 0) {}
    ~TtsRequestScope() {
        if (session_ != nullptr)
            session_->tts_requests.finish(id_);
    }

    uint64_t id() const { return id_; }
    bool cancelled() const {
        return session_ != nullptr && session_->tts_requests.is_cancelled(id_);
    }

   private:
    Session* session_;
    uint64_t id_;
};

// ───────────────────────────────── vtable ops ───────────────────────────────

rac_result_t qhexrt_tts_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_tts_create: manifest=%s", model_id);
    Session* s = session_open(model_id);
    if (s == nullptr) {
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }
    *out_impl = s;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_tts_initialize(void* /*impl*/) {
    return RAC_SUCCESS;
}

rac_result_t qhexrt_tts_synthesize(void* impl, const char* text,
                                   const rac_tts_options_t* /*options*/,
                                   rac_tts_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        TtsRequestScope request(c);
        qhx_session_reset(c->sess);  // public SDK synthesize calls are independent requests
        if (request.cancelled()) {
            return RAC_ERROR_CANCELLED;
        }
        qhx_inputs in{};
        in.text = text;
        qhx_gen_cfg cfg;
        qhx_gen_cfg_default(&cfg);
        StopCtx ctx{c, request.id()};
        qhx_generate_options generate_options;
        qhx_generate_options_default(&generate_options);
        generate_options.should_cancel = should_cancel_trampoline;
        generate_options.should_cancel_user = &ctx;
        qhx_output out{};
        qhx_status st =
            qhx_generate_ex(c->sess, &in, &cfg, &generate_options, stop_trampoline, &ctx, &out);
        if (ctx.cancelled || request.cancelled()) {
            RAC_LOG_INFO(LOG_CAT, "TTS request %llu cancelled during batch generation",
                         static_cast<unsigned long long>(request.id()));
            return RAC_ERROR_CANCELLED;
        }
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate_ex(tts) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        void* audio = nullptr;
        size_t bytes = 0;
        if (!copy_waveform(out, &audio, &bytes)) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        out_result->audio_data = audio;
        out_result->audio_size = bytes;
        out_result->audio_format = RAC_AUDIO_FORMAT_PCM;  // mono float32
        out_result->sample_rate = static_cast<int32_t>(out.sample_rate);
        out_result->duration_ms = duration_ms(out);
        out_result->processing_time_ms = static_cast<int64_t>(out.prefill_ms + out.decode_ms);
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_tts_synthesize_stream(void* impl, const char* text,
                                          const rac_tts_options_t* /*options*/,
                                          rac_tts_stream_callback_t callback, void* user_data) {
    auto* c = as_session(impl);
    if (c == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (text == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        TtsRequestScope request(c);
        qhx_session_reset(c->sess);  // public SDK stream calls are independent requests
        if (request.cancelled()) {
            return RAC_ERROR_CANCELLED;
        }
        qhx_inputs in{};
        in.text = text;
        qhx_gen_cfg cfg;
        qhx_gen_cfg_default(&cfg);
        StopCtx ctx{c, request.id()};
        qhx_generate_options generate_options;
        qhx_generate_options_default(&generate_options);
        generate_options.should_cancel = should_cancel_trampoline;
        generate_options.should_cancel_user = &ctx;
        qhx_output out{};
        qhx_status st =
            qhx_generate_ex(c->sess, &in, &cfg, &generate_options, stop_trampoline, &ctx, &out);
        if (ctx.cancelled || request.cancelled()) {
            RAC_LOG_INFO(LOG_CAT, "TTS request %llu cancelled during streaming generation",
                         static_cast<unsigned long long>(request.id()));
            return RAC_ERROR_CANCELLED;
        }
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate_ex(tts stream) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        // qhx_output.audio is session-owned and only valid until the next
        // qhx_generate_ex()/free on this session — hand the callback a copy so a
        // consumer that retains the buffer past this call can't use-after-free
        // (mirrors the non-stream path).
        if (callback != nullptr && out.audio != nullptr && out.n_audio > 0) {
            void* audio = nullptr;
            size_t bytes = 0;
            if (!copy_waveform(out, &audio, &bytes)) {
                return RAC_ERROR_OUT_OF_MEMORY;
            }
            callback(audio, bytes, user_data);
            rac_free(audio);
        }
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_tts_stop(void* impl) {
    auto* c = as_session(impl);
    if (c != nullptr) {
        const uint64_t request_id = c->tts_requests.active_id.load(std::memory_order_acquire);
        c->tts_requests.cancel_active();
        RAC_LOG_INFO(LOG_CAT, "TTS stop routed to request %llu",
                     static_cast<unsigned long long>(request_id));
    }
    return RAC_SUCCESS;
}

rac_result_t qhexrt_tts_get_info(void* impl, rac_tts_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* c = as_session(impl);
    rac_bool_t is_ready = RAC_FALSE;
    if (c != nullptr) {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        is_ready = c->sess != nullptr ? RAC_TRUE : RAC_FALSE;
    }
    out_info->is_ready = is_ready;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = nullptr;
    out_info->num_voices = 0;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_tts_cleanup(void* impl) {
    auto* c = as_session(impl);
    if (c == nullptr) {
        return RAC_SUCCESS;
    }
    std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
    if (c->sess != nullptr) {
        qhx_session_reset(c->sess);
    }
    return RAC_SUCCESS;
}

void qhexrt_tts_destroy(void* impl) {
    session_close(as_session(impl));
}

}  // namespace

extern "C" const rac_tts_service_ops_t g_qhexrt_tts_ops = {
    /* .initialize        = */ qhexrt_tts_initialize,
    /* .synthesize        = */ qhexrt_tts_synthesize,
    /* .synthesize_stream = */ qhexrt_tts_synthesize_stream,
    /* .stop              = */ qhexrt_tts_stop,
    /* .get_info          = */ qhexrt_tts_get_info,
    /* .cleanup           = */ qhexrt_tts_cleanup,
    /* .destroy           = */ qhexrt_tts_destroy,
    /* .create            = */ qhexrt_tts_create,
    /* .get_languages     = */ nullptr,
};
