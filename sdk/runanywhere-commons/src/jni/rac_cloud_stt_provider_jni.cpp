/**
 * @file rac_cloud_stt_provider_jni.cpp
 * @brief JNI bridge that registers a Kotlin cloud STT provider as a NAMED entry
 *        in the cross-SDK rac_cloud_stt_provider table in commons.
 *
 * The `cloud` STT engine resolves a developer-defined provider by NAME and
 * invokes the registered callback to perform the whole request host-side — so
 * any cloud vendor works without a native adapter. Each registered name owns
 * one adapter holding a JavaVM + GlobalRef to the Kotlin
 * NativeCloudSttProvider object plus its cached jmethodID; the adapter is freed
 * when the name is re-registered or unregistered.
 *
 * Mirrors rac_hybrid_custom_filter_jni.cpp's EnvScope + adapter lifecycle. The
 * only structural difference is the callback payload: a config-JSON string +
 * audio byte[] + format int in, a result-JSON string out (instead of a single
 * boolean), so the marshalling is heavier but the registration/lifetime rules
 * are identical.
 */

#include <jni.h>

#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <new>
#include <string>

#include "rac/cloud/rac_cloud_stt_provider.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace {

struct CloudProviderAdapter {
    JavaVM*   vm = nullptr;
    jobject   provider = nullptr;  // GlobalRef to NativeCloudSttProvider
    jmethodID mid_invoke = nullptr;
};

// name → adapter. Guarded by g_mutex; the commons-side named table
// (rac_cloud_stt_provider.cpp) owns the callback-pointer publication, this map
// only owns the JNI GlobalRef lifetime per name.
std::mutex                                  g_mutex;
std::map<std::string, CloudProviderAdapter*> g_adapters;

inline jint attach_current_thread(JavaVM* vm, JNIEnv** out_env) {
#if defined(__ANDROID__)
    return vm->AttachCurrentThread(out_env, nullptr);
#else
    return vm->AttachCurrentThread(reinterpret_cast<void**>(out_env), nullptr);
#endif
}

struct EnvScope {
    JavaVM* vm;
    JNIEnv* env = nullptr;
    bool    attached = false;

    explicit EnvScope(JavaVM* v) : vm(v) {
        if (vm == nullptr) {
            return;
        }
        const jint rc = vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
        if (rc == JNI_EDETACHED) {
            if (attach_current_thread(vm, &env) == JNI_OK) {
                attached = true;
            } else {
                env = nullptr;
            }
        } else if (rc != JNI_OK) {
            env = nullptr;
        }
    }
    ~EnvScope() {
        if (attached && vm != nullptr) {
            vm->DetachCurrentThread();
        }
    }
};

// malloc-copy a JNI UTF string into a NUL-terminated C string owned by the
// caller (freed via rac_cloud_stt_result_free in the engine).
char* dup_cstr(const char* s, size_t len) {
    char* out = static_cast<char*>(std::malloc(len + 1));
    if (out == nullptr) {
        return nullptr;
    }
    std::memcpy(out, s, len);
    out[len] = '\0';
    return out;
}

// Commons-facing callback: marshal the request to Kotlin and copy back the
// result JSON. Fails with an error code on any JNI fault; the engine then
// surfaces a transcribe failure (it never silently fabricates a transcript).
rac_result_t cloud_stt_transcribe_adapter(const char*    config_json,
                                          const uint8_t* audio,
                                          size_t         audio_len,
                                          int32_t        audio_format,
                                          char**         out_result_json,
                                          void*          user_data) {
    auto* a = static_cast<CloudProviderAdapter*>(user_data);
    if (a == nullptr || out_result_json == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_result_json = nullptr;
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return RAC_ERROR_INTERNAL;
    }

    jstring jconfig = scope.env->NewStringUTF(config_json != nullptr ? config_json : "{}");
    jbyteArray jaudio = scope.env->NewByteArray(static_cast<jsize>(audio_len));
    if (jconfig == nullptr || jaudio == nullptr) {
        if (jconfig != nullptr) {
            scope.env->DeleteLocalRef(jconfig);
        }
        if (jaudio != nullptr) {
            scope.env->DeleteLocalRef(jaudio);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (audio_len > 0 && audio != nullptr) {
        scope.env->SetByteArrayRegion(jaudio, 0, static_cast<jsize>(audio_len),
                                      reinterpret_cast<const jbyte*>(audio));
    }

    auto jresult = static_cast<jstring>(scope.env->CallObjectMethod(
        a->provider, a->mid_invoke, jconfig, jaudio, static_cast<jint>(audio_format)));
    scope.env->DeleteLocalRef(jconfig);
    scope.env->DeleteLocalRef(jaudio);

    if (scope.env->ExceptionCheck()) {
        scope.env->ExceptionClear();
        if (jresult != nullptr) {
            scope.env->DeleteLocalRef(jresult);
        }
        return RAC_ERROR_INTERNAL;
    }
    if (jresult == nullptr) {
        return RAC_ERROR_INTERNAL;
    }

    const char* utf = scope.env->GetStringUTFChars(jresult, nullptr);
    if (utf == nullptr) {
        scope.env->DeleteLocalRef(jresult);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    char* copy = dup_cstr(utf, std::strlen(utf));
    scope.env->ReleaseStringUTFChars(jresult, utf);
    scope.env->DeleteLocalRef(jresult);
    if (copy == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_result_json = copy;
    return RAC_SUCCESS;
}

// Delete a name's adapter GlobalRef + struct. Caller holds g_mutex.
void destroy_adapter_locked(CloudProviderAdapter* a) {
    if (a == nullptr) {
        return;
    }
    EnvScope scope(a->vm);
    if (scope.env != nullptr && a->provider != nullptr) {
        scope.env->DeleteGlobalRef(a->provider);
    }
    delete a;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racCloudRegisterSttProvider(
    JNIEnv* env, jclass /*clazz*/, jstring name, jobject provider) {
    if (name == nullptr || provider == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const char* name_utf = env->GetStringUTFChars(name, nullptr);
    if (name_utf == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const std::string name_str(name_utf);
    env->ReleaseStringUTFChars(name, name_utf);

    jclass clazz =
        env->FindClass("com/runanywhere/sdk/public/hybrid/NativeCloudSttProvider");
    if (clazz == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const jmethodID mid_invoke =
        env->GetMethodID(clazz, "invoke", "(Ljava/lang/String;[BI)Ljava/lang/String;");
    env->DeleteLocalRef(clazz);
    if (mid_invoke == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }

    auto* adapter = new (std::nothrow) CloudProviderAdapter();
    if (adapter == nullptr) {
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }
    if (env->GetJavaVM(&adapter->vm) != JNI_OK) {
        delete adapter;
        return static_cast<jint>(RAC_ERROR_INTERNAL);
    }
    adapter->provider = env->NewGlobalRef(provider);
    if (adapter->provider == nullptr) {
        delete adapter;
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }
    adapter->mid_invoke = mid_invoke;

    const rac_result_t rc =
        rac_cloud_register_stt_provider(name_str.c_str(), cloud_stt_transcribe_adapter, adapter);
    if (rc != RAC_SUCCESS) {
        env->DeleteGlobalRef(adapter->provider);
        delete adapter;
        return static_cast<jint>(rc);
    }

    // Commons now points at `adapter`; retire any previous adapter under the
    // same name. Register the new entry FIRST (above), then free the old
    // GlobalRef here so an in-flight call holding the prior callback pointer
    // still has live user_data through the one-generation reprieve.
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_adapters.find(name_str);
    if (it != g_adapters.end()) {
        destroy_adapter_locked(it->second);
        it->second = adapter;
    } else {
        g_adapters.emplace(name_str, adapter);
    }
    return static_cast<jint>(RAC_SUCCESS);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racCloudUnregisterSttProvider(
    JNIEnv* env, jclass /*clazz*/, jstring name) {
    if (name == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const char* name_utf = env->GetStringUTFChars(name, nullptr);
    if (name_utf == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const std::string name_str(name_utf);
    env->ReleaseStringUTFChars(name, name_utf);

    const rac_result_t rc = rac_cloud_unregister_stt_provider(name_str.c_str());

    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_adapters.find(name_str);
    if (it != g_adapters.end()) {
        destroy_adapter_locked(it->second);
        g_adapters.erase(it);
    }
    return static_cast<jint>(rc);
}

}  // extern "C"
