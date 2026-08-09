// voice_bridge.cpp — the composed voice agent over the commons proto ABI.
//
// Unlike the rest of the migrated surface these entry points take a
// rac_voice_agent_handle_t, so the handle crosses into JS as a number and comes
// back on every call, the same shape rerank uses. The agent is a session rather
// than a one-shot: it owns the VAD framing, the endpointing, and the
// STT -> LLM -> TTS pipeline for as long as the SDK keeps feeding it audio.
//
// The VoiceEvent stream is the one place this file cannot reuse
// `RunProtoStream`. `rac_voice_agent_set_proto_callback` registers a slot that
// outlives any single call rather than being driven by a blocking start
// function, so the ThreadSafeFunction is created when the stream is opened and
// released when the agent is destroyed. `rac_voice_agent_destroy` performs the
// unregister-then-quiesce sequence `rac_voice_event_abi.h` documents, and it
// runs on a worker, so the spin never lands on the event loop.

#include "voice_bridge.h"

#include "proto_bridge.h"

#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"

namespace rac_electron {
namespace {

constexpr size_t kVoiceEventQueueCapacity = 512;

struct VoiceEventStream {
    Napi::ThreadSafeFunction emit;
    Napi::Promise::Deferred deferred;

    explicit VoiceEventStream(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

std::mutex& StreamMutex() {
    static std::mutex mutex;
    return mutex;
}

std::unordered_map<rac_voice_agent_handle_t, VoiceEventStream*>& Streams() {
    static std::unordered_map<rac_voice_agent_handle_t, VoiceEventStream*> streams;
    return streams;
}

void ForwardVoiceEvent(const uint8_t* bytes, size_t size, void* user_data) {
    auto* stream = static_cast<VoiceEventStream*>(user_data);
    if (stream == nullptr || bytes == nullptr || size == 0)
        return;
    auto* payload = new std::vector<uint8_t>(bytes, bytes + size);
    const napi_status status = stream->emit.BlockingCall(
        payload, [](Napi::Env env, Napi::Function callback, std::vector<uint8_t>* held) {
            std::unique_ptr<std::vector<uint8_t>> owned(held);
            callback.Call({Napi::Buffer<uint8_t>::Copy(env, owned->data(), owned->size())});
        });
    if (status != napi_ok)
        delete payload;
}

rac_voice_agent_handle_t RequireHandle(const Napi::CallbackInfo& info, const char* signature) {
    if (info.Length() < 1 || !info[0].IsNumber()) {
        throw Napi::TypeError::New(info.Env(),
                                   std::string(signature) + " expects a voice-agent handle");
    }
    return reinterpret_cast<rac_voice_agent_handle_t>(
        static_cast<intptr_t>(info[0].As<Napi::Number>().Int64Value()));
}

Napi::Value VoiceCreate(const Napi::CallbackInfo& info) {
    auto config = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 0, "voiceCreateProto(configBytes)"));
    auto created = std::make_shared<rac_voice_agent_handle_t>(nullptr);
    return RunNativeCall(
        info.Env(), "voice_agent_create",
        [config, created]() {
            return rac_voice_agent_component_create_proto(
                config->empty() ? nullptr : config->data(), config->size(), created.get());
        },
        [created](Napi::Env env) {
            return Napi::Number::New(env,
                                     static_cast<double>(reinterpret_cast<intptr_t>(*created)));
        });
}

Napi::Value VoiceDestroy(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle = RequireHandle(info, "voiceDestroyProto(handle)");
    return RunNativeCall(
        info.Env(), "voice_agent_destroy",
        [handle]() { return rac_voice_agent_component_destroy_proto(handle); },
        [handle](Napi::Env env) {
            VoiceEventStream* stream = nullptr;
            {
                std::lock_guard<std::mutex> lock(StreamMutex());
                auto it = Streams().find(handle);
                if (it != Streams().end()) {
                    stream = it->second;
                    Streams().erase(it);
                }
            }
            // The destroy above already cleared the callback slot and quiesced,
            // so nothing can reach the queue between here and the release.
            if (stream != nullptr)
                stream->emit.Release();
            return env.Undefined();
        });
}

Napi::Value VoiceEvents(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle = RequireHandle(info, "voiceEventsProto(handle, onEvent)");
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(info.Env(),
                                   "voiceEventsProto(handle, onEvent) expects a callback");
    }
    {
        std::lock_guard<std::mutex> lock(StreamMutex());
        if (Streams().count(handle) != 0) {
            return RejectWithProtoError(info.Env(), RAC_ERROR_INVALID_STATE,
                                        "voice_agent_events (a stream is already open)");
        }
    }

    auto* stream = new VoiceEventStream(info.Env());
    Napi::Promise promise = stream->deferred.Promise();
    stream->emit = Napi::ThreadSafeFunction::New(
        info.Env(), info[1].As<Napi::Function>(), "runanywhere_voice_events",
        kVoiceEventQueueCapacity, 1, [stream](Napi::Env finalizer_env) {
            Napi::HandleScope scope(finalizer_env);
            stream->deferred.Resolve(finalizer_env.Undefined());
            delete stream;
        });

    {
        std::lock_guard<std::mutex> lock(StreamMutex());
        Streams()[handle] = stream;
    }
    const rac_result_t status = rac_voice_agent_set_proto_callback(handle, ForwardVoiceEvent,
                                                                   stream);
    if (status != RAC_SUCCESS) {
        {
            std::lock_guard<std::mutex> lock(StreamMutex());
            Streams().erase(handle);
        }
        stream->emit.Release();
        return RejectWithProtoError(info.Env(), status, "voice_agent_set_event_callback");
    }
    return promise;
}

Napi::Value VoiceInitialize(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle =
        RequireHandle(info, "voiceInitializeProto(handle, configBytes)");
    auto config = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 1, "voiceInitializeProto(handle, configBytes)"));
    return RunProtoCall(info.Env(), "voice_agent_initialize",
                        [handle, config](rac_proto_buffer_t* out) {
                            return rac_voice_agent_initialize_proto(
                                handle, config->empty() ? nullptr : config->data(), config->size(),
                                out);
                        });
}

Napi::Value VoiceComponentStates(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle = RequireHandle(info, "voiceStatesProto(handle)");
    return RunProtoCall(info.Env(), "voice_agent_component_states",
                        [handle](rac_proto_buffer_t* out) {
                            return rac_voice_agent_component_states_proto(handle, out);
                        });
}

Napi::Value VoiceFeedAudio(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle =
        RequireHandle(info, "voiceFeedAudioProto(handle, frameBytes)");
    auto frame = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 1, "voiceFeedAudioProto(handle, frameBytes)"));
    return RunProtoCall(info.Env(), "voice_agent_feed_audio",
                        [handle, frame](rac_proto_buffer_t* out) {
                            return rac_voice_agent_feed_audio_proto(
                                handle, frame->empty() ? nullptr : frame->data(), frame->size(),
                                out);
                        });
}

Napi::Value VoiceProcessVoiceTurn(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle =
        RequireHandle(info, "voiceProcessVoiceTurnProto(handle, pcm16)");
    auto audio = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 1, "voiceProcessVoiceTurnProto(handle, pcm16)"));
    return RunProtoCall(info.Env(), "voice_agent_process_voice_turn",
                        [handle, audio](rac_proto_buffer_t* out) {
                            return rac_voice_agent_process_voice_turn_proto(
                                handle, audio->empty() ? nullptr : audio->data(), audio->size(),
                                out);
                        });
}

Napi::Value VoiceProcessTurn(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle =
        RequireHandle(info, "voiceProcessTurnProto(handle, requestBytes, onEvent)");
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 1, "voiceProcessTurnProto(handle, requestBytes, onEvent)"));
    if (info.Length() < 3 || !info[2].IsFunction()) {
        throw Napi::TypeError::New(
            info.Env(), "voiceProcessTurnProto(handle, requestBytes, onEvent) expects a callback");
    }
    return RunProtoStream(
        info.Env(), "voice_agent_process_turn",
        [handle, request](rac_proto_bytes_callback_fn callback, void* user_data) {
            const rac_result_t status = rac_voice_agent_process_turn_proto(
                handle, request->empty() ? nullptr : request->data(), request->size(), callback,
                user_data);
            // The per-turn callback can still be running when this returns.
            rac_voice_agent_proto_quiesce();
            return status;
        },
        info[2].As<Napi::Function>(), nullptr);
}

Napi::Value VoiceCancelTurn(const Napi::CallbackInfo& info) {
    const rac_voice_agent_handle_t handle =
        RequireHandle(info, "voiceCancelTurnProto(handle, requestBytes)");
    auto request = std::make_shared<std::vector<uint8_t>>(
        RequireProtoBytes(info, 1, "voiceCancelTurnProto(handle, requestBytes)"));
    return RunNativeCall(info.Env(), "voice_agent_cancel_turn", [handle, request]() {
        return rac_voice_agent_cancel_turn_proto(
            handle, request->empty() ? nullptr : request->data(), request->size());
    });
}

}  // namespace

void RegisterVoiceBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("voiceCreateProto", Napi::Function::New(env, VoiceCreate));
    exports.Set("voiceDestroyProto", Napi::Function::New(env, VoiceDestroy));
    exports.Set("voiceEventsProto", Napi::Function::New(env, VoiceEvents));
    exports.Set("voiceInitializeProto", Napi::Function::New(env, VoiceInitialize));
    exports.Set("voiceStatesProto", Napi::Function::New(env, VoiceComponentStates));
    exports.Set("voiceFeedAudioProto", Napi::Function::New(env, VoiceFeedAudio));
    exports.Set("voiceProcessVoiceTurnProto", Napi::Function::New(env, VoiceProcessVoiceTurn));
    exports.Set("voiceProcessTurnProto", Napi::Function::New(env, VoiceProcessTurn));
    exports.Set("voiceCancelTurnProto", Napi::Function::New(env, VoiceCancelTurn));
}

}  // namespace rac_electron
