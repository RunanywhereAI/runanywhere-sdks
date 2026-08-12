// speech_bridge.cpp — STT, TTS, and VAD over the lifecycle proto ABI.
//
// One file for the three because they are the same shape: handle-free entry
// points that read whatever rac_model_lifecycle_load_proto made resident for
// their component, a request message in, a result or an event stream out.

#include "speech_bridge.h"

#include "proto_bridge.h"

#include <memory>
#include <vector>

#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_stream.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_stream.h"
#include "rac/features/vad/rac_vad_service.h"

namespace rac_electron {
namespace {

// ---- stt ----

Napi::Value SttTranscribe(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "stt_transcribe", rac_stt_transcribe_lifecycle_proto,
                         RequireProtoBytes(info, 0, "sttTranscribeProto(requestBytes)"));
}

Napi::Value SttTranscribeStream(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "sttTranscribeStreamProto(requestBytes, onEvent)"));
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(
            info.Env(), "sttTranscribeStreamProto(requestBytes, onEvent) expects a callback");
    }
    return RunProtoStream(
        info.Env(), "stt_transcribe_stream",
        [request](rac_proto_bytes_callback_fn callback, void* user_data) {
            const rac_result_t rc = rac_stt_transcribe_stream_lifecycle_proto(
                request->data(), request->size(), callback, user_data);
            // The dispatcher may still be inside a callback when this returns.
            rac_stt_proto_quiesce();
            return rc;
        },
        info[1].As<Napi::Function>(), nullptr);
}

Napi::Value SttState(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "stt_state",
                        [](rac_proto_buffer_t* out) { return rac_stt_state_lifecycle_proto(out); });
}

// ---- tts ----

Napi::Value TtsSynthesize(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "tts_synthesize", rac_tts_synthesize_lifecycle_proto,
                         RequireProtoBytes(info, 0, "ttsSynthesizeProto(requestBytes)"));
}

Napi::Value TtsSynthesizeStream(const Napi::CallbackInfo& info) {
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "ttsSynthesizeStreamProto(requestBytes, onEvent)"));
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(
            info.Env(), "ttsSynthesizeStreamProto(requestBytes, onEvent) expects a callback");
    }
    return RunProtoStream(
        info.Env(), "tts_synthesize_stream",
        [request](rac_proto_bytes_callback_fn callback, void* user_data) {
            const rac_result_t rc = rac_tts_synthesize_stream_lifecycle_proto(
                request->data(), request->size(), callback, user_data);
            rac_tts_proto_quiesce();
            return rc;
        },
        info[1].As<Napi::Function>(), nullptr);
}

Napi::Value TtsStop(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "tts_stop",
                        [](rac_proto_buffer_t* out) { return rac_tts_stop_lifecycle_proto(out); });
}

Napi::Value TtsListVoices(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "tts_list_voices", [](rac_proto_buffer_t* out) {
        return rac_tts_list_voices_lifecycle_proto(out);
    });
}

Napi::Value TtsState(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "tts_state",
                        [](rac_proto_buffer_t* out) { return rac_tts_state_lifecycle_proto(out); });
}

// ---- vad ----

Napi::Value VadProcess(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "vad_process", rac_vad_process_lifecycle_proto,
                         RequireProtoBytes(info, 0, "vadProcessProto(requestBytes)"));
}

Napi::Value VadConfigure(const Napi::CallbackInfo& info) {
    return RunProtoUnary(info.Env(), "vad_configure", rac_vad_configure_lifecycle_proto,
                         RequireProtoBytes(info, 0, "vadConfigureProto(requestBytes)"));
}

Napi::Value VadStart(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "vad_start",
                        [](rac_proto_buffer_t* out) { return rac_vad_start_lifecycle_proto(out); });
}

Napi::Value VadStop(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "vad_stop",
                        [](rac_proto_buffer_t* out) { return rac_vad_stop_lifecycle_proto(out); });
}

Napi::Value VadReset(const Napi::CallbackInfo& info) {
    return RunProtoCall(info.Env(), "vad_reset",
                        [](rac_proto_buffer_t* out) { return rac_vad_reset_lifecycle_proto(out); });
}

}  // namespace

void RegisterSpeechBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("sttTranscribeProto", Napi::Function::New(env, SttTranscribe));
    exports.Set("sttTranscribeStreamProto", Napi::Function::New(env, SttTranscribeStream));
    exports.Set("sttStateProto", Napi::Function::New(env, SttState));
    exports.Set("ttsSynthesizeProto", Napi::Function::New(env, TtsSynthesize));
    exports.Set("ttsSynthesizeStreamProto", Napi::Function::New(env, TtsSynthesizeStream));
    exports.Set("ttsStopProto", Napi::Function::New(env, TtsStop));
    exports.Set("ttsListVoicesProto", Napi::Function::New(env, TtsListVoices));
    exports.Set("ttsStateProto", Napi::Function::New(env, TtsState));
    exports.Set("vadProcessProto", Napi::Function::New(env, VadProcess));
    exports.Set("vadConfigureProto", Napi::Function::New(env, VadConfigure));
    exports.Set("vadStartProto", Napi::Function::New(env, VadStart));
    exports.Set("vadStopProto", Napi::Function::New(env, VadStop));
    exports.Set("vadResetProto", Napi::Function::New(env, VadReset));
}

}  // namespace rac_electron
