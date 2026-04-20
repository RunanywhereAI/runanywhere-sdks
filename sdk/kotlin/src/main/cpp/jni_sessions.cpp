// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// JNI bridge for primitive sessions (LLM/STT/TTS/VAD/Embed) and
// SDK state. Complements jni_bridge.cpp which handles ra_pipeline.

#include <jni.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "../../../../../core/abi/ra_primitives.h"
#include "../../../../../core/abi/ra_state.h"
#include "../../../../../core/abi/ra_core_init.h"
#include "../../../../../core/abi/ra_platform_adapter.h"

namespace {

struct JvmCallbackRef {
    JavaVM*   vm = nullptr;
    jobject   global_emitter = nullptr;
    jmethodID mid_chunk = nullptr;    // STT: void onChunk(String,bool,float,long,long)
    jmethodID mid_vad   = nullptr;    // VAD: void onEvent(int,long,float)
    jmethodID mid_token = nullptr;    // LLM: void onToken(String,int,bool)
    jmethodID mid_error = nullptr;    // LLM: void onError(int,String)
};

// JvmCallbackRef lives inside a session's Kotlin-owned wrapper; we keep the
// JvmCallbackRef pointer as a raw pointer attached via Kotlin Long field
// so we can delete it when the session is destroyed.

const char* jstr(JNIEnv* env, jstring s, std::vector<std::string>& hold) {
    if (!s) return "";
    const char* c = env->GetStringUTFChars(s, nullptr);
    hold.emplace_back(c ? c : "");
    env->ReleaseStringUTFChars(s, c);
    return hold.back().c_str();
}

ra_model_spec_t make_spec(const char* id, const char* path,
                           ra_model_format_t fmt) {
    ra_model_spec_t s{};
    s.model_id = id;
    s.model_path = path;
    s.format = fmt;
    s.preferred_runtime = RA_RUNTIME_SELF_CONTAINED;
    return s;
}

ra_session_config_t default_cfg() {
    ra_session_config_t c{};
    c.n_gpu_layers = -1;
    c.n_threads = 0;
    c.context_size = 0;
    c.use_mmap = 1;
    c.use_mlock = 0;
    return c;
}

JNIEnv* attach(JvmCallbackRef* ref) {
    JNIEnv* env = nullptr;
    if (ref->vm->AttachCurrentThread(
#ifdef __ANDROID__
            &env,
#else
            reinterpret_cast<void**>(&env),
#endif
            nullptr) != JNI_OK) {
        return nullptr;
    }
    return env;
}

}  // namespace

extern "C" {

// ===========================================================================
// LLM
// ===========================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeCreate(
    JNIEnv* env, jobject, jobject emitter,
    jstring model_id, jstring model_path, jint format_int) {

    std::vector<std::string> hold;
    const char* id   = jstr(env, model_id, hold);
    const char* path = jstr(env, model_path, hold);
    auto spec = make_spec(id, path, static_cast<ra_model_format_t>(format_int));
    auto cfg  = default_cfg();

    ra_llm_session_t* session = nullptr;
    const auto status = ra_llm_create(&spec, &cfg, &session);
    if (status != RA_OK || !session) return 0;

    auto* ref = new JvmCallbackRef{};
    env->GetJavaVM(&ref->vm);
    ref->global_emitter = env->NewGlobalRef(emitter);
    jclass cls = env->GetObjectClass(emitter);
    ref->mid_token = env->GetMethodID(cls, "onToken",
                                       "(Ljava/lang/String;IZ)V");
    ref->mid_error = env->GetMethodID(cls, "onError",
                                       "(ILjava/lang/String;)V");

    // Store both pointers — we need session + ref
    auto* pair = new std::pair<ra_llm_session_t*, JvmCallbackRef*>(session, ref);
    return reinterpret_cast<jlong>(pair);
}

static void llm_token_cb(const ra_token_output_t* t, void* ud) {
    auto* ref = static_cast<JvmCallbackRef*>(ud);
    if (!t || !ref) return;
    JNIEnv* env = attach(ref);
    if (!env) return;
    jstring jtext = env->NewStringUTF(t->text ? t->text : "");
    env->CallVoidMethod(ref->global_emitter, ref->mid_token,
                         jtext,
                         static_cast<jint>(t->token_kind),
                         static_cast<jboolean>(t->is_final));
    env->DeleteLocalRef(jtext);
    ref->vm->DetachCurrentThread();
}

static void llm_error_cb(ra_status_t code, const char* msg, void* ud) {
    auto* ref = static_cast<JvmCallbackRef*>(ud);
    if (!ref) return;
    JNIEnv* env = attach(ref);
    if (!env) return;
    jstring jmsg = env->NewStringUTF(msg ? msg : "");
    env->CallVoidMethod(ref->global_emitter, ref->mid_error,
                         static_cast<jint>(code), jmsg);
    env->DeleteLocalRef(jmsg);
    ref->vm->DetachCurrentThread();
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeGenerate(
    JNIEnv* env, jobject, jlong ptr, jstring jprompt, jint conv_id) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first) return RA_ERR_INVALID_ARGUMENT;
    std::vector<std::string> hold;
    ra_prompt_t p{};
    p.text = jstr(env, jprompt, hold);
    p.conversation_id = conv_id;
    return ra_llm_generate(pair->first, &p, llm_token_cb, llm_error_cb, pair->second);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeCancel(JNIEnv*, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    return (pair && pair->first) ? ra_llm_cancel(pair->first) : RA_ERR_INVALID_ARGUMENT;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeReset(JNIEnv*, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    return (pair && pair->first) ? ra_llm_reset(pair->first) : RA_ERR_INVALID_ARGUMENT;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeInjectSystemPrompt(
    JNIEnv* env, jobject, jlong ptr, jstring jprompt) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first) return RA_ERR_INVALID_ARGUMENT;
    std::vector<std::string> hold;
    return ra_llm_inject_system_prompt(pair->first, jstr(env, jprompt, hold));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeAppendContext(
    JNIEnv* env, jobject, jlong ptr, jstring jtext) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first) return RA_ERR_INVALID_ARGUMENT;
    std::vector<std::string> hold;
    return ra_llm_append_context(pair->first, jstr(env, jtext, hold));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeGenerateFromContext(
    JNIEnv* env, jobject, jlong ptr, jstring jquery) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first) return RA_ERR_INVALID_ARGUMENT;
    std::vector<std::string> hold;
    return ra_llm_generate_from_context(pair->first, jstr(env, jquery, hold),
                                          llm_token_cb, llm_error_cb, pair->second);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeClearContext(JNIEnv*, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    return (pair && pair->first) ? ra_llm_clear_context(pair->first) : RA_ERR_INVALID_ARGUMENT;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_LLMSession_nativeDestroy(JNIEnv* env, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_llm_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair) return;
    if (pair->first) ra_llm_destroy(pair->first);
    if (pair->second) {
        if (pair->second->global_emitter) env->DeleteGlobalRef(pair->second->global_emitter);
        delete pair->second;
    }
    delete pair;
}

// ===========================================================================
// STT
// ===========================================================================

static void stt_chunk_cb(const ra_transcript_chunk_t* c, void* ud) {
    auto* ref = static_cast<JvmCallbackRef*>(ud);
    if (!c || !ref) return;
    JNIEnv* env = attach(ref);
    if (!env) return;
    jstring jtext = env->NewStringUTF(c->text ? c->text : "");
    env->CallVoidMethod(ref->global_emitter, ref->mid_chunk,
                         jtext,
                         static_cast<jboolean>(c->is_partial),
                         static_cast<jfloat>(c->confidence),
                         static_cast<jlong>(c->audio_start_us),
                         static_cast<jlong>(c->audio_end_us));
    env->DeleteLocalRef(jtext);
    ref->vm->DetachCurrentThread();
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_STTSession_nativeCreate(
    JNIEnv* env, jobject, jobject emitter,
    jstring model_id, jstring model_path, jint format_int) {
    std::vector<std::string> hold;
    auto spec = make_spec(jstr(env, model_id, hold), jstr(env, model_path, hold),
                           static_cast<ra_model_format_t>(format_int));
    auto cfg = default_cfg();
    ra_stt_session_t* session = nullptr;
    if (ra_stt_create(&spec, &cfg, &session) != RA_OK) return 0;

    auto* ref = new JvmCallbackRef{};
    env->GetJavaVM(&ref->vm);
    ref->global_emitter = env->NewGlobalRef(emitter);
    jclass cls = env->GetObjectClass(emitter);
    ref->mid_chunk = env->GetMethodID(cls, "onChunk",
        "(Ljava/lang/String;ZFJJ)V");
    ra_stt_set_callback(session, stt_chunk_cb, ref);

    auto* pair = new std::pair<ra_stt_session_t*, JvmCallbackRef*>(session, ref);
    return reinterpret_cast<jlong>(pair);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_STTSession_nativeFeedAudio(
    JNIEnv* env, jobject, jlong ptr, jfloatArray samples, jint sr) {
    auto* pair = reinterpret_cast<std::pair<ra_stt_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first || !samples) return RA_ERR_INVALID_ARGUMENT;
    jsize n = env->GetArrayLength(samples);
    jfloat* data = env->GetFloatArrayElements(samples, nullptr);
    auto status = ra_stt_feed_audio(pair->first, data, n, sr);
    env->ReleaseFloatArrayElements(samples, data, JNI_ABORT);
    return status;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_STTSession_nativeFlush(JNIEnv*, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_stt_session_t*, JvmCallbackRef*>*>(ptr);
    return (pair && pair->first) ? ra_stt_flush(pair->first) : RA_ERR_INVALID_ARGUMENT;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_STTSession_nativeDestroy(JNIEnv* env, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_stt_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair) return;
    if (pair->first) ra_stt_destroy(pair->first);
    if (pair->second) {
        if (pair->second->global_emitter) env->DeleteGlobalRef(pair->second->global_emitter);
        delete pair->second;
    }
    delete pair;
}

// ===========================================================================
// TTS
// ===========================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_TTSSession_nativeCreate(
    JNIEnv* env, jobject,
    jstring model_id, jstring model_path, jint format_int) {
    std::vector<std::string> hold;
    auto spec = make_spec(jstr(env, model_id, hold), jstr(env, model_path, hold),
                           static_cast<ra_model_format_t>(format_int));
    auto cfg = default_cfg();
    ra_tts_session_t* session = nullptr;
    if (ra_tts_create(&spec, &cfg, &session) != RA_OK) return 0;
    return reinterpret_cast<jlong>(session);
}

JNIEXPORT jfloatArray JNICALL
Java_com_runanywhere_sdk_public_TTSSession_nativeSynthesize(
    JNIEnv* env, jobject, jlong ptr, jstring jtext, jintArray outSr) {
    auto* session = reinterpret_cast<ra_tts_session_t*>(ptr);
    if (!session) return nullptr;
    std::vector<std::string> hold;
    const char* text = jstr(env, jtext, hold);

    int32_t capacity = 240000;
    while (capacity <= 4000000) {
        std::vector<float> buffer(capacity);
        int32_t written = 0, sr = 0;
        auto status = ra_tts_synthesize(session, text, buffer.data(), capacity,
                                         &written, &sr);
        if (status == RA_OK) {
            jfloatArray out = env->NewFloatArray(written);
            env->SetFloatArrayRegion(out, 0, written, buffer.data());
            if (outSr && env->GetArrayLength(outSr) > 0) {
                env->SetIntArrayRegion(outSr, 0, 1, &sr);
            }
            return out;
        }
        if (status != RA_ERR_OUT_OF_MEMORY) return nullptr;
        capacity *= 2;
    }
    return nullptr;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_TTSSession_nativeCancel(JNIEnv*, jobject, jlong ptr) {
    auto* s = reinterpret_cast<ra_tts_session_t*>(ptr);
    return s ? ra_tts_cancel(s) : RA_ERR_INVALID_ARGUMENT;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_TTSSession_nativeDestroy(JNIEnv*, jobject, jlong ptr) {
    auto* s = reinterpret_cast<ra_tts_session_t*>(ptr);
    if (s) ra_tts_destroy(s);
}

// ===========================================================================
// VAD
// ===========================================================================

static void vad_event_cb(const ra_vad_event_t* e, void* ud) {
    auto* ref = static_cast<JvmCallbackRef*>(ud);
    if (!e || !ref) return;
    JNIEnv* env = attach(ref);
    if (!env) return;
    env->CallVoidMethod(ref->global_emitter, ref->mid_vad,
                         static_cast<jint>(e->type),
                         static_cast<jlong>(e->frame_offset_us),
                         static_cast<jfloat>(e->energy));
    ref->vm->DetachCurrentThread();
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_VADSession_nativeCreate(
    JNIEnv* env, jobject, jobject emitter,
    jstring model_id, jstring model_path, jint format_int) {
    std::vector<std::string> hold;
    auto spec = make_spec(jstr(env, model_id, hold), jstr(env, model_path, hold),
                           static_cast<ra_model_format_t>(format_int));
    auto cfg = default_cfg();
    ra_vad_session_t* session = nullptr;
    if (ra_vad_create(&spec, &cfg, &session) != RA_OK) return 0;

    auto* ref = new JvmCallbackRef{};
    env->GetJavaVM(&ref->vm);
    ref->global_emitter = env->NewGlobalRef(emitter);
    jclass cls = env->GetObjectClass(emitter);
    ref->mid_vad = env->GetMethodID(cls, "onEvent", "(IJF)V");
    ra_vad_set_callback(session, vad_event_cb, ref);

    auto* pair = new std::pair<ra_vad_session_t*, JvmCallbackRef*>(session, ref);
    return reinterpret_cast<jlong>(pair);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_VADSession_nativeFeedAudio(
    JNIEnv* env, jobject, jlong ptr, jfloatArray samples, jint sr) {
    auto* pair = reinterpret_cast<std::pair<ra_vad_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair || !pair->first || !samples) return RA_ERR_INVALID_ARGUMENT;
    jsize n = env->GetArrayLength(samples);
    jfloat* data = env->GetFloatArrayElements(samples, nullptr);
    auto status = ra_vad_feed_audio(pair->first, data, n, sr);
    env->ReleaseFloatArrayElements(samples, data, JNI_ABORT);
    return status;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_VADSession_nativeDestroy(JNIEnv* env, jobject, jlong ptr) {
    auto* pair = reinterpret_cast<std::pair<ra_vad_session_t*, JvmCallbackRef*>*>(ptr);
    if (!pair) return;
    if (pair->first) ra_vad_destroy(pair->first);
    if (pair->second) {
        if (pair->second->global_emitter) env->DeleteGlobalRef(pair->second->global_emitter);
        delete pair->second;
    }
    delete pair;
}

// ===========================================================================
// Embed
// ===========================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_EmbedSession_nativeCreate(
    JNIEnv* env, jobject,
    jstring model_id, jstring model_path, jint format_int) {
    std::vector<std::string> hold;
    auto spec = make_spec(jstr(env, model_id, hold), jstr(env, model_path, hold),
                           static_cast<ra_model_format_t>(format_int));
    auto cfg = default_cfg();
    ra_embed_session_t* session = nullptr;
    if (ra_embed_create(&spec, &cfg, &session) != RA_OK) return 0;
    return reinterpret_cast<jlong>(session);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_EmbedSession_nativeDims(JNIEnv*, jobject, jlong ptr) {
    auto* s = reinterpret_cast<ra_embed_session_t*>(ptr);
    return s ? ra_embed_dims(s) : 0;
}

JNIEXPORT jfloatArray JNICALL
Java_com_runanywhere_sdk_public_EmbedSession_nativeEmbed(
    JNIEnv* env, jobject, jlong ptr, jstring jtext) {
    auto* s = reinterpret_cast<ra_embed_session_t*>(ptr);
    if (!s) return nullptr;
    int32_t dims = ra_embed_dims(s);
    if (dims <= 0) return nullptr;
    std::vector<std::string> hold;
    std::vector<float> vec(dims);
    if (ra_embed_text(s, jstr(env, jtext, hold), vec.data(), dims) != RA_OK) {
        return nullptr;
    }
    jfloatArray out = env->NewFloatArray(dims);
    env->SetFloatArrayRegion(out, 0, dims, vec.data());
    return out;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_EmbedSession_nativeDestroy(JNIEnv*, jobject, jlong ptr) {
    auto* s = reinterpret_cast<ra_embed_session_t*>(ptr);
    if (s) ra_embed_destroy(s);
}

// ===========================================================================
// SDK state
// ===========================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeInitialize(
    JNIEnv* env, jobject, jint env_int, jstring api_key,
    jstring base_url, jstring device_id) {
    std::vector<std::string> hold;
    return ra_state_initialize(static_cast<ra_environment_t>(env_int),
                                 jstr(env, api_key, hold),
                                 jstr(env, base_url, hold),
                                 jstr(env, device_id, hold));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeIsInitialized(JNIEnv*, jobject) {
    return ra_state_is_initialized() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeReset(JNIEnv*, jobject) {
    ra_state_reset();
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetEnvironment(JNIEnv*, jobject) {
    return ra_state_get_environment();
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetBaseUrl(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_base_url());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetApiKey(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_api_key());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetDeviceId(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_device_id());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeSetAuth(
    JNIEnv* env, jobject, jstring access, jstring refresh, jlong expires,
    jstring user_id, jstring org_id, jstring device_id) {
    std::vector<std::string> hold;
    ra_auth_data_t data{};
    data.access_token = jstr(env, access, hold);
    data.refresh_token = jstr(env, refresh, hold);
    data.expires_at_unix = expires;
    data.user_id = jstr(env, user_id, hold);
    data.organization_id = jstr(env, org_id, hold);
    data.device_id = jstr(env, device_id, hold);
    return ra_state_set_auth(&data);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetAccessToken(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_access_token());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetRefreshToken(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_refresh_token());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetUserId(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_user_id());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetOrganizationId(JNIEnv* env, jobject) {
    return env->NewStringUTF(ra_state_get_organization_id());
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeIsAuthenticated(JNIEnv*, jobject) {
    return ra_state_is_authenticated() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeTokenNeedsRefresh(JNIEnv*, jobject, jint h) {
    return ra_state_token_needs_refresh(h) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeGetTokenExpiresAt(JNIEnv*, jobject) {
    return ra_state_get_token_expires_at();
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeClearAuth(JNIEnv*, jobject) {
    ra_state_clear_auth();
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeIsDeviceRegistered(JNIEnv*, jobject) {
    return ra_state_is_device_registered() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeSetDeviceRegistered(JNIEnv*, jobject, jboolean r) {
    ra_state_set_device_registered(r == JNI_TRUE);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeValidateApiKey(JNIEnv* env, jobject, jstring key) {
    std::vector<std::string> hold;
    return ra_validate_api_key(jstr(env, key, hold)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeValidateBaseUrl(JNIEnv* env, jobject, jstring url) {
    std::vector<std::string> hold;
    return ra_validate_base_url(jstr(env, url, hold)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_public_SDKState_nativeSetLogLevel(JNIEnv*, jobject, jint level) {
    ra_logger_set_min_level(static_cast<ra_log_level_t>(level));
}

}  // extern "C"
