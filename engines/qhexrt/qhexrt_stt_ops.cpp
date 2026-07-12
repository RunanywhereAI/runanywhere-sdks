/**
 * @file qhexrt_stt_ops.cpp
 * @brief STT (RAC_PRIMITIVE_TRANSCRIBE) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in routable builds. Maps `rac_stt_service_ops_t` onto
 * `qhx_generate` with an audio input (QHexRT Whisper family). The QHexRT runtime
 * consumes mono float32 PCM in [-1,1], but the RAC STT contract delivers mono
 * int16 PCM (RAC_AUDIO_FORMAT_PCM == int16, per stt_module.cpp); this adapter
 * converts int16 -> float32 before calling qhx_generate. Only RAC_AUDIO_FORMAT_PCM
 * input is accepted (compressed formats need decoding QHexRT does not perform and
 * return RAC_ERROR_NOT_SUPPORTED).
 */

#include "qhexrt_session.h"

#include <cstdint>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) {
    return static_cast<Session*>(impl);
}

// Converts the raw STT audio buffer (mono int16 PCM, the RAC contract) into the
// mono float32 [-1,1] buffer the QHexRT runtime expects. The converted samples
// are stored in `scratch`, which must outlive the qhx_generate() call. Returns
// false (caller -> NOT_SUPPORTED) for formats QHexRT cannot consume directly.
bool fill_audio(qhx_inputs* in, std::vector<float>& scratch, const void* audio_data,
                size_t audio_size, const rac_stt_options_t* o) {
    *in = qhx_inputs{};
    if (audio_data == nullptr || audio_size < sizeof(int16_t)) {
        return false;
    }
    if (o != nullptr && o->audio_format != RAC_AUDIO_FORMAT_PCM) {
        return false;  // mp3/wav/opus/... need decoding QHexRT does not do
    }
    const auto* pcm = static_cast<const int16_t*>(audio_data);
    const size_t n = audio_size / sizeof(int16_t);
    scratch.resize(n);
    constexpr float kInvScale = 1.0f / 32768.0f;
    for (size_t i = 0; i < n; ++i) {
        scratch[i] = static_cast<float>(pcm[i]) * kInvScale;
    }
    in->audio = scratch.data();
    in->n_audio = static_cast<int>(n);
    in->audio_sr = (o != nullptr && o->sample_rate > 0) ? o->sample_rate : 16000;
    return true;
}

struct StreamCtx {
    rac_stt_stream_callback_t cb;
    void* user;
    Session* session;
    bool cancelled = false;
    std::string acc;  // cumulative transcript forwarded as partial text
};

int stream_trampoline(void* user, const char* utf8, int len, int /*token_id*/, int is_final) {
    auto* c = static_cast<StreamCtx*>(user);
    if (c == nullptr) {
        return 1;
    }
    if (c->session != nullptr && c->session->cancel.load(std::memory_order_relaxed)) {
        c->cancelled = true;
        return 0;
    }
    if (is_final != 0 || utf8 == nullptr) {
        if (c->cb != nullptr) {
            c->cb(c->acc.c_str(), RAC_TRUE, c->user);
        }
        return 1;
    }
    if (len > 0) {
        c->acc.append(utf8, static_cast<size_t>(len));
    }
    if (c->cb != nullptr) {
        c->cb(c->acc.c_str(), RAC_FALSE, c->user);
    }
    return 1;
}

struct StopCtx {
    Session* session;
    bool cancelled = false;
};

int stop_trampoline(void* user, const char* /*utf8*/, int /*len*/, int /*token_id*/,
                    int /*is_final*/) {
    auto* c = static_cast<StopCtx*>(user);
    if (c != nullptr && c->session != nullptr &&
        c->session->cancel.load(std::memory_order_relaxed)) {
        c->cancelled = true;
        return 0;
    }
    return 1;
}

void fill_result(rac_stt_result_t* out, const qhx_output& o) {
    out->text = rac_strdup(o.text != nullptr ? o.text : "");
    out->detected_language = nullptr;
    out->words = nullptr;
    out->num_words = 0;
    out->confidence = 0.0f;
    out->processing_time_ms = static_cast<int64_t>(o.prefill_ms + o.decode_ms);
}

// ───────────────────────────────── vtable ops ───────────────────────────────

rac_result_t qhexrt_stt_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_stt_create: manifest=%s", model_id);
    Session* s = session_open(model_id);
    if (s == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    *out_impl = s;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_stt_initialize(void* /*impl*/, const char* /*model_path*/) {
    return RAC_SUCCESS;
}

rac_result_t qhexrt_stt_transcribe(void* impl, const void* audio_data, size_t audio_size,
                                   const rac_stt_options_t* options, rac_stt_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        qhx_session_reset(c->sess);  // public SDK transcribe calls are independent requests
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        std::vector<float> audio_f32;
        if (!fill_audio(&in, audio_f32, audio_data, audio_size, options)) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        qhx_gen_cfg cfg;
        qhx_gen_cfg_default(&cfg);
        StopCtx stop_ctx{c};
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, stop_trampoline, &stop_ctx, &out);
        if (stop_ctx.cancelled || c->cancel.load(std::memory_order_relaxed)) {
            return RAC_ERROR_CANCELLED;
        }
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate(stt) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        fill_result(out_result, out);
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_stt_transcribe_stream(void* impl, const void* audio_data, size_t audio_size,
                                          const rac_stt_options_t* options,
                                          rac_stt_stream_callback_t callback, void* user_data) {
    auto* c = as_session(impl);
    if (c == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        std::lock_guard<std::mutex> operation_lock(c->operation_mutex);
        if (c->sess == nullptr) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        qhx_session_reset(c->sess);  // public SDK stream calls are independent requests
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        std::vector<float> audio_f32;
        if (!fill_audio(&in, audio_f32, audio_data, audio_size, options)) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        qhx_gen_cfg cfg;
        qhx_gen_cfg_default(&cfg);
        StreamCtx ctx{callback, user_data, c, false, std::string()};
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, stream_trampoline, &ctx, &out);
        if (ctx.cancelled || c->cancel.load(std::memory_order_relaxed)) {
            return RAC_ERROR_CANCELLED;
        }
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate(stt stream) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_stt_get_info(void* impl, rac_stt_info_t* out_info) {
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
    out_info->current_model = nullptr;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_stt_cleanup(void* impl) {
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

void qhexrt_stt_destroy(void* impl) {
    session_close(as_session(impl));
}

}  // namespace

// STT optional ops (language list/detect, real-time stream handle) are NULL:
// QHexRT exposes single-shot transcription; the registry maps NULL to
// RAC_ERROR_NOT_SUPPORTED.
extern "C" const rac_stt_service_ops_t g_qhexrt_stt_ops = {
    /* .initialize             = */ qhexrt_stt_initialize,
    /* .transcribe             = */ qhexrt_stt_transcribe,
    /* .transcribe_stream      = */ qhexrt_stt_transcribe_stream,
    /* .get_info               = */ qhexrt_stt_get_info,
    /* .cleanup                = */ qhexrt_stt_cleanup,
    /* .destroy                = */ qhexrt_stt_destroy,
    /* .create                 = */ qhexrt_stt_create,
    /* .get_languages          = */ nullptr,
    /* .detect_language        = */ nullptr,
    /* .stream_create          = */ nullptr,
    /* .stream_feed_audio_chunk= */ nullptr,
    /* .stream_destroy         = */ nullptr,
};
