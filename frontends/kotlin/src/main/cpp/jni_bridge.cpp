// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// JNI bridge that exposes core/abi/ra_pipeline.h to the Kotlin adapter.
// Compiled as part of the racommons_core shared library on Linux / Android
// / macOS so `System.loadLibrary("racommons_core")` reaches both the C
// ABI symbols and these Java_... glue functions in one dlopen.

#include <jni.h>

#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "../../../../../core/abi/ra_pipeline.h"

namespace {

struct JvmRef {
    JavaVM* vm            = nullptr;
    jobject global_emitter = nullptr;  // VoiceSessionEmitter
    jmethodID on_event_mid  = nullptr;  // void onEvent(int kind, String text,
                                        //              boolean isFinal, ...)
    jmethodID on_error_mid  = nullptr;  // void onError(int code, String msg)
    jmethodID on_done_mid   = nullptr;  // void onDone()
};

void event_callback(const ra_voice_event_t* ev, void* ud) {
    if (!ev || !ud) return;
    auto* ref = static_cast<JvmRef*>(ud);
    JNIEnv* env = nullptr;
    if (ref->vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) != JNI_OK) {
        return;
    }
    jstring jtext = env->NewStringUTF(ev->text ? ev->text : "");
    env->CallVoidMethod(ref->global_emitter, ref->on_event_mid,
                        static_cast<jint>(ev->kind),
                        jtext,
                        static_cast<jboolean>(ev->is_final),
                        static_cast<jint>(ev->token_kind),
                        static_cast<jint>(ev->vad_type),
                        static_cast<jint>(ev->sample_rate_hz));
    env->DeleteLocalRef(jtext);
    ref->vm->DetachCurrentThread();
}

void completion_callback(ra_status_t status, const char* message, void* ud) {
    if (!ud) return;
    auto* ref = static_cast<JvmRef*>(ud);
    JNIEnv* env = nullptr;
    if (ref->vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) != JNI_OK) {
        return;
    }
    if (status == RA_OK) {
        env->CallVoidMethod(ref->global_emitter, ref->on_done_mid);
    } else {
        jstring jmsg = env->NewStringUTF(message ? message : "");
        env->CallVoidMethod(ref->global_emitter, ref->on_error_mid,
                            static_cast<jint>(status), jmsg);
        env->DeleteLocalRef(jmsg);
    }
    ref->vm->DetachCurrentThread();
}

struct Handle {
    ra_pipeline_t* pipeline = nullptr;
    std::unique_ptr<JvmRef> ref;
    std::vector<std::string> held_strings;  // keep configs alive during call
};

const char* safe(JNIEnv* env, jstring s, std::vector<std::string>& hold) {
    if (!s) return "";
    const char* c = env->GetStringUTFChars(s, nullptr);
    hold.emplace_back(c ? c : "");
    env->ReleaseStringUTFChars(s, c);
    return hold.back().c_str();
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeCreate(
    JNIEnv* env, jobject /*self*/,
    jobject emitter,
    jstring llm, jstring stt, jstring tts, jstring vad,
    jint    sample_rate, jint chunk_ms,
    jboolean enable_barge_in,
    jstring  system_prompt,
    jint     max_context_tokens,
    jfloat   temperature,
    jboolean emit_partials,
    jboolean emit_thoughts) {

    auto handle = std::make_unique<Handle>();
    ra_voice_agent_config_t cfg{};
    cfg.llm_model_id       = safe(env, llm, handle->held_strings);
    cfg.stt_model_id       = safe(env, stt, handle->held_strings);
    cfg.tts_model_id       = safe(env, tts, handle->held_strings);
    cfg.vad_model_id       = safe(env, vad, handle->held_strings);
    cfg.sample_rate_hz     = sample_rate;
    cfg.chunk_ms           = chunk_ms;
    cfg.audio_source       = RA_AUDIO_SOURCE_MICROPHONE;
    cfg.enable_barge_in    = enable_barge_in ? 1 : 0;
    cfg.barge_in_threshold_ms = 200;
    cfg.system_prompt      = safe(env, system_prompt, handle->held_strings);
    cfg.max_context_tokens = max_context_tokens;
    cfg.temperature        = temperature;
    cfg.emit_partials      = emit_partials ? 1 : 0;
    cfg.emit_thoughts      = emit_thoughts ? 1 : 0;

    ra_pipeline_t* p = nullptr;
    const auto status = ra_pipeline_create_voice_agent(&cfg, &p);
    if (status != RA_OK) return 0;
    handle->pipeline = p;

    handle->ref = std::make_unique<JvmRef>();
    env->GetJavaVM(&handle->ref->vm);
    handle->ref->global_emitter = env->NewGlobalRef(emitter);
    jclass cls = env->GetObjectClass(emitter);
    handle->ref->on_event_mid = env->GetMethodID(cls, "onEvent",
        "(ILjava/lang/String;ZIII)V");
    handle->ref->on_error_mid = env->GetMethodID(cls, "onError",
        "(ILjava/lang/String;)V");
    handle->ref->on_done_mid  = env->GetMethodID(cls, "onDone", "()V");

    ra_pipeline_set_event_callback(p, event_callback, handle->ref.get());
    ra_pipeline_set_completion_callback(p, completion_callback, handle->ref.get());

    return reinterpret_cast<jlong>(handle.release());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeRun(JNIEnv*, jobject, jlong ptr) {
    auto* h = reinterpret_cast<Handle*>(ptr);
    if (!h || !h->pipeline) return RA_ERR_INVALID_ARGUMENT;
    return ra_pipeline_run(h->pipeline);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeCancel(JNIEnv*, jobject, jlong ptr) {
    auto* h = reinterpret_cast<Handle*>(ptr);
    if (!h || !h->pipeline) return RA_ERR_INVALID_ARGUMENT;
    return ra_pipeline_cancel(h->pipeline);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeDestroy(JNIEnv* env, jobject, jlong ptr) {
    auto* h = reinterpret_cast<Handle*>(ptr);
    if (!h) return;
    if (h->ref && h->ref->global_emitter) {
        env->DeleteGlobalRef(h->ref->global_emitter);
    }
    if (h->pipeline) ra_pipeline_destroy(h->pipeline);
    delete h;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeFeedAudio(
    JNIEnv* env, jobject, jlong ptr,
    jfloatArray samples, jint sample_rate_hz) {
    auto* h = reinterpret_cast<Handle*>(ptr);
    if (!h || !h->pipeline || !samples) return RA_ERR_INVALID_ARGUMENT;
    jsize n = env->GetArrayLength(samples);
    jfloat* data = env->GetFloatArrayElements(samples, nullptr);
    const auto status = ra_pipeline_feed_audio(h->pipeline, data, n, sample_rate_hz);
    env->ReleaseFloatArrayElements(samples, data, JNI_ABORT);
    return status;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_adapter_VoiceSession_nativeBargeIn(JNIEnv*, jobject, jlong ptr) {
    auto* h = reinterpret_cast<Handle*>(ptr);
    if (!h || !h->pipeline) return RA_ERR_INVALID_ARGUMENT;
    return ra_pipeline_inject_barge_in(h->pipeline);
}

}  // extern "C"
