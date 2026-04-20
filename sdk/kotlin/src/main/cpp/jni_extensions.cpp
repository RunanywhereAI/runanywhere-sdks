// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// JNI entry points for v2 ABI extensions: auth, telemetry, model,
// RAG. Complements jni_bridge.cpp + jni_sessions.cpp.

#include <jni.h>

#include <cstring>
#include <string>
#include <vector>

#include "ra_auth.h"
#include "ra_model.h"
#include "ra_rag.h"
#include "ra_telemetry.h"
#include "ra_primitives.h"

namespace {

jstring cstr_to_jstring(JNIEnv* env, const char* s) {
    return env->NewStringUTF(s ? s : "");
}

std::string jstring_to_str(JNIEnv* env, jstring s) {
    if (!s) return {};
    const char* ptr = env->GetStringUTFChars(s, nullptr);
    std::string out = ptr ? ptr : "";
    env->ReleaseStringUTFChars(s, ptr);
    return out;
}

}  // namespace

extern "C" {

// -----------------------------------------------------------------------
// Auth
// -----------------------------------------------------------------------

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_isAuthenticated(JNIEnv*, jobject) {
    return ra_auth_is_authenticated() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_needsRefresh(JNIEnv*, jobject, jint horizon_seconds) {
    return ra_auth_needs_refresh(horizon_seconds) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_getAccessToken(JNIEnv* env, jobject) {
    return cstr_to_jstring(env, ra_auth_get_access_token());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_getRefreshToken(JNIEnv* env, jobject) {
    return cstr_to_jstring(env, ra_auth_get_refresh_token());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_getDeviceId(JNIEnv* env, jobject) {
    return cstr_to_jstring(env, ra_auth_get_device_id());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_buildAuthenticateRequest(
    JNIEnv* env, jobject, jstring apiKey, jstring deviceId) {
    const auto ak = jstring_to_str(env, apiKey);
    const auto di = jstring_to_str(env, deviceId);
    char* out = nullptr;
    auto rc = ra_auth_build_authenticate_request(ak.c_str(), di.c_str(), &out);
    if (rc != RA_OK || !out) return env->NewStringUTF("");
    jstring jout = env->NewStringUTF(out);
    ra_auth_string_free(out);
    return jout;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_handleAuthenticateResponse(
    JNIEnv* env, jobject, jstring body) {
    const auto b = jstring_to_str(env, body);
    return static_cast<jint>(ra_auth_handle_authenticate_response(b.c_str()));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_jni_AuthNative_clear(JNIEnv*, jobject) {
    ra_auth_clear();
}

// -----------------------------------------------------------------------
// Telemetry
// -----------------------------------------------------------------------

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_TelemetryNative_track(
    JNIEnv* env, jobject, jstring name, jstring propertiesJson) {
    const auto n = jstring_to_str(env, name);
    const auto p = jstring_to_str(env, propertiesJson);
    return static_cast<jint>(ra_telemetry_track(n.c_str(), p.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_TelemetryNative_flush(JNIEnv*, jobject) {
    return static_cast<jint>(ra_telemetry_flush());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_jni_TelemetryNative_defaultPayloadJson(
    JNIEnv* env, jobject) {
    char* out = nullptr;
    auto rc = ra_telemetry_payload_default(&out);
    if (rc != RA_OK || !out) return env->NewStringUTF("");
    jstring j = env->NewStringUTF(out);
    ra_telemetry_string_free(out);
    return j;
}

// -----------------------------------------------------------------------
// Model helpers
// -----------------------------------------------------------------------

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_jni_ModelNative_frameworkSupports(
    JNIEnv* env, jobject, jstring fw, jstring cat) {
    const auto f = jstring_to_str(env, fw);
    const auto c = jstring_to_str(env, cat);
    return ra_framework_supports(f.c_str(), c.c_str()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_ModelNative_detectFormat(
    JNIEnv* env, jobject, jstring url) {
    const auto s = jstring_to_str(env, url);
    return static_cast<jint>(ra_model_detect_format(s.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_ModelNative_inferCategory(
    JNIEnv* env, jobject, jstring modelId) {
    const auto s = jstring_to_str(env, modelId);
    return static_cast<jint>(ra_model_infer_category(s.c_str()));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_jni_ModelNative_isArchive(
    JNIEnv* env, jobject, jstring url) {
    const auto s = jstring_to_str(env, url);
    return ra_artifact_is_archive(s.c_str()) ? JNI_TRUE : JNI_FALSE;
}

// -----------------------------------------------------------------------
// RAG
// -----------------------------------------------------------------------

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_jni_RagNative_storeCreate(JNIEnv*, jobject, jint dim) {
    ra_rag_vector_store_t* s = nullptr;
    if (ra_rag_store_create(dim, &s) != RA_OK) return 0;
    return reinterpret_cast<jlong>(s);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_jni_RagNative_storeDestroy(JNIEnv*, jobject, jlong handle) {
    ra_rag_store_destroy(reinterpret_cast<ra_rag_vector_store_t*>(handle));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_RagNative_storeAdd(
    JNIEnv* env, jobject,
    jlong handle, jstring rowId, jstring metaJson,
    jfloatArray embedding) {
    auto* store = reinterpret_cast<ra_rag_vector_store_t*>(handle);
    const auto id = jstring_to_str(env, rowId);
    const auto meta = jstring_to_str(env, metaJson);
    const jsize n = env->GetArrayLength(embedding);
    std::vector<float> buf(n);
    env->GetFloatArrayRegion(embedding, 0, n, buf.data());
    return static_cast<jint>(ra_rag_store_add(store, id.c_str(),
                                                  meta.c_str(),
                                                  buf.data(),
                                                  static_cast<int32_t>(n)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_jni_RagNative_storeSize(JNIEnv*, jobject, jlong handle) {
    return ra_rag_store_size(reinterpret_cast<ra_rag_vector_store_t*>(handle));
}

JNIEXPORT jobjectArray JNICALL
Java_com_runanywhere_sdk_jni_RagNative_storeSearch(
    JNIEnv* env, jobject, jlong handle, jfloatArray query, jint topK) {
    auto* store = reinterpret_cast<ra_rag_vector_store_t*>(handle);
    const jsize dim = env->GetArrayLength(query);
    std::vector<float> buf(dim);
    env->GetFloatArrayRegion(query, 0, dim, buf.data());
    char** ids = nullptr; char** metas = nullptr; float* scores = nullptr;
    int32_t count = 0;
    auto rc = ra_rag_store_search(store, buf.data(), dim, topK,
                                    &ids, &metas, &scores, &count);
    if (rc != RA_OK || count == 0) {
        return env->NewObjectArray(0, env->FindClass("java/lang/String"), nullptr);
    }
    jclass strCls = env->FindClass("java/lang/String");
    // Return flat [id0, meta0, score0, id1, meta1, score1, …]
    jobjectArray out = env->NewObjectArray(count * 3, strCls, nullptr);
    for (int32_t i = 0; i < count; ++i) {
        env->SetObjectArrayElement(out, i*3 + 0,
            env->NewStringUTF(ids[i]));
        env->SetObjectArrayElement(out, i*3 + 1,
            env->NewStringUTF(metas[i]));
        char score_buf[32];
        std::snprintf(score_buf, sizeof(score_buf), "%g", scores[i]);
        env->SetObjectArrayElement(out, i*3 + 2,
            env->NewStringUTF(score_buf));
    }
    ra_rag_strings_free(ids, count);
    ra_rag_strings_free(metas, count);
    ra_rag_floats_free(scores);
    return out;
}

}  // extern "C"
