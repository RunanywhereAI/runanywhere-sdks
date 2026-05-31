/**
 * @file rac_hybrid_router_jni.cpp
 * @brief JNI thunks for the LLM hybrid router.
 *
 * Stays byte-only at the .so boundary. All proto parsing / building
 * lives inside rac_commons (rac_llm_hybrid_router_proto.cpp); these
 * thunks just marshal jbyteArray → (const uint8_t*, size_t) and back.
 *
 * Service handles (offline / online) cross the JNI as raw `jlong`
 * (reinterpret_cast'd `rac_llm_service_t*`). Kotlin obtains them from
 * either rac_llm_create() (for in-tree LLM backends like llama.cpp) or
 * from an engine-specific factory (e.g. rac_llm_openrouter_create()).
 *
 * Also hosts the DeviceStateProvider JNI bridge: registers a Kotlin
 * DeviceStateProvider object as the cross-SDK
 * `rac_hybrid_device_state_ops_t` vtable in commons.
 */

#include <jni.h>

#include <atomic>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/routing/rac_hybrid_device_state.h"
#include "rac/routing/rac_llm_hybrid_router.h"
#include "rac/routing/rac_llm_hybrid_router_proto.h"

namespace {

std::string jstring_to_std(JNIEnv* env, jstring s) {
    if (s == nullptr) {
        return {};
    }
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out(c == nullptr ? "" : c);
    if (c != nullptr) {
        env->ReleaseStringUTFChars(s, c);
    }
    return out;
}

/** Copy bytes out of a Java jbyteArray. Empty vector on null/empty. */
std::vector<uint8_t> jbyte_array_to_vec(JNIEnv* env, jbyteArray arr) {
    if (arr == nullptr) {
        return {};
    }
    const jsize len = env->GetArrayLength(arr);
    if (len <= 0) {
        return {};
    }
    std::vector<uint8_t> out(static_cast<size_t>(len));
    env->GetByteArrayRegion(arr, 0, len, reinterpret_cast<jbyte*>(out.data()));
    return out;
}

/** Wrap a heap-allocated byte buffer in a new jbyteArray and free the source. */
jbyteArray bytes_to_jbyte_array(JNIEnv* env, uint8_t* src, size_t size) {
    if (src == nullptr) {
        return env->NewByteArray(0);
    }
    jbyteArray arr = env->NewByteArray(static_cast<jsize>(size));
    if (arr != nullptr && size > 0) {
        env->SetByteArrayRegion(arr, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(src));
    }
    rac_llm_hybrid_router_proto_buffer_free(src);
    return arr;
}

// ---------------------------------------------------------------------------
// DeviceStateProvider JNI bridge
//
// One adapter is stashed in g_device_state_adapter while a Kotlin provider
// is registered. The adapter struct owns the GlobalRef to the Kotlin object
// + cached jmethodIDs; freed on next set/unset call (after the C vtable
// has retired the previous slot so in-flight callbacks complete).
// ---------------------------------------------------------------------------
struct DeviceStateAdapter {
    JavaVM*   vm = nullptr;
    jobject   provider = nullptr;  // GlobalRef
    jmethodID mid_is_online = nullptr;
    jmethodID mid_battery_percent = nullptr;
    jmethodID mid_is_thermal_throttled = nullptr;
};

std::atomic<DeviceStateAdapter*> g_device_state_adapter{nullptr};

/**
 * AttachCurrentThread's first parameter is declared as `JNIEnv**` on the
 * Android NDK and as `void**` on the Linux/macOS JDK. This wrapper takes
 * the platform-appropriate cast so the same translation unit compiles
 * cleanly under either headers set.
 */
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

bool device_state_is_online(void* user_data) {
    auto* a = static_cast<DeviceStateAdapter*>(user_data);
    if (a == nullptr) {
        return true;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return true;
    }
    return scope.env->CallBooleanMethod(a->provider, a->mid_is_online) != JNI_FALSE;
}

int32_t device_state_battery_percent(void* user_data) {
    auto* a = static_cast<DeviceStateAdapter*>(user_data);
    if (a == nullptr) {
        return 100;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return 100;
    }
    return static_cast<int32_t>(
        scope.env->CallIntMethod(a->provider, a->mid_battery_percent));
}

bool device_state_is_thermal_throttled(void* user_data) {
    auto* a = static_cast<DeviceStateAdapter*>(user_data);
    if (a == nullptr) {
        return false;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return false;
    }
    return scope.env->CallBooleanMethod(a->provider, a->mid_is_thermal_throttled) != JNI_FALSE;
}

/** Detach commons from the current adapter and free its GlobalRef. */
void clear_device_state_adapter() {
    rac_hybrid_set_device_state(nullptr);
    auto* prev = g_device_state_adapter.exchange(nullptr, std::memory_order_acq_rel);
    if (prev != nullptr) {
        EnvScope scope(prev->vm);
        if (scope.env != nullptr && prev->provider != nullptr) {
            scope.env->DeleteGlobalRef(prev->provider);
        }
        delete prev;
    }
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmServiceCreate(
    JNIEnv* env, jclass /*clazz*/, jstring model_id) {
    const std::string id = jstring_to_std(env, model_id);
    if (id.empty()) {
        return 0;
    }
    rac_handle_t handle = RAC_INVALID_HANDLE;
    if (rac_llm_create(id.c_str(), &handle) != RAC_SUCCESS || handle == RAC_INVALID_HANDLE) {
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmServiceDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle != 0) {
        rac_llm_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHybridSetDeviceState(
    JNIEnv* env, jclass /*clazz*/, jobject provider) {
    if (provider == nullptr) {
        clear_device_state_adapter();
        return static_cast<jint>(RAC_SUCCESS);
    }

    jclass clazz = env->FindClass("com/runanywhere/sdk/public/hybrid/DeviceStateProvider");
    if (clazz == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const jmethodID mid_is_online =
        env->GetMethodID(clazz, "isOnline", "()Z");
    const jmethodID mid_battery_percent =
        env->GetMethodID(clazz, "batteryPercent", "()I");
    const jmethodID mid_is_thermal_throttled =
        env->GetMethodID(clazz, "isThermalThrottled", "()Z");
    env->DeleteLocalRef(clazz);
    if (mid_is_online == nullptr || mid_battery_percent == nullptr ||
        mid_is_thermal_throttled == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }

    auto* adapter = new (std::nothrow) DeviceStateAdapter();
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
    adapter->mid_is_online = mid_is_online;
    adapter->mid_battery_percent = mid_battery_percent;
    adapter->mid_is_thermal_throttled = mid_is_thermal_throttled;

    rac_hybrid_device_state_ops_t ops{
        device_state_is_online,
        device_state_battery_percent,
        device_state_is_thermal_throttled,
        adapter,
    };
    const rac_result_t rc = rac_hybrid_set_device_state(&ops);
    if (rc != RAC_SUCCESS) {
        env->DeleteGlobalRef(adapter->provider);
        delete adapter;
        return static_cast<jint>(rc);
    }

    auto* prev = g_device_state_adapter.exchange(adapter, std::memory_order_acq_rel);
    if (prev != nullptr) {
        EnvScope scope(prev->vm);
        if (scope.env != nullptr && prev->provider != nullptr) {
            scope.env->DeleteGlobalRef(prev->provider);
        }
        delete prev;
    }
    return static_cast<jint>(RAC_SUCCESS);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterCreate(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    if (rac_llm_hybrid_router_create(&handle) != RAC_SUCCESS) {
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterDestroy(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong handle) {
    if (handle != 0) {
        rac_llm_hybrid_router_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterSetOfflineService(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jlong service_handle,
    jbyteArray descriptor_proto) {
    const auto bytes = jbyte_array_to_vec(env, descriptor_proto);
    return static_cast<jint>(rac_llm_hybrid_router_set_offline_service_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        reinterpret_cast<rac_llm_service_t*>(service_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterSetOnlineService(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jlong service_handle,
    jbyteArray descriptor_proto) {
    const auto bytes = jbyte_array_to_vec(env, descriptor_proto);
    return static_cast<jint>(rac_llm_hybrid_router_set_online_service_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        reinterpret_cast<rac_llm_service_t*>(service_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterSetPolicy(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray policy_proto) {
    const auto bytes = jbyte_array_to_vec(env, policy_proto);
    return static_cast<jint>(rac_llm_hybrid_router_set_policy_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        bytes.data(), bytes.size()));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterGenerate(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray request_proto) {
    const auto bytes = jbyte_array_to_vec(env, request_proto);
    uint8_t* response_bytes = nullptr;
    size_t   response_size = 0;
    const rac_result_t rc = rac_llm_hybrid_router_generate_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        bytes.data(), bytes.size(),
        &response_bytes, &response_size);
    if (rc != RAC_SUCCESS) {
        rac_llm_hybrid_router_proto_buffer_free(response_bytes);
        return nullptr;
    }
    return bytes_to_jbyte_array(env, response_bytes, response_size);
}

}  // extern "C"

// ---------------------------------------------------------------------------
// Stream + cancel JNI bridge
//
// Kotlin owns a HybridStreamCallback instance; we hold a JavaVM + GlobalRef
// + cached jmethodIDs for the call's duration and forward each token and the
// final done event back to it. The native call is synchronous from the
// caller's POV, so the GlobalRef + adapter live on the stack and are
// released right after rac_llm_hybrid_router_generate_stream_proto returns.
// ---------------------------------------------------------------------------

namespace {

struct StreamAdapter {
    JavaVM*   vm           = nullptr;
    jobject   callback     = nullptr;  // GlobalRef of HybridStreamCallback
    jmethodID mid_on_token = nullptr;
    jmethodID mid_on_done  = nullptr;
};

rac_bool_t stream_token_jni(const char* token, void* user_data) {
    auto* a = static_cast<StreamAdapter*>(user_data);
    if (a == nullptr || a->callback == nullptr || a->vm == nullptr) {
        return RAC_FALSE;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return RAC_FALSE;
    }
    jstring jToken = scope.env->NewStringUTF(token != nullptr ? token : "");
    const jboolean keep =
        scope.env->CallBooleanMethod(a->callback, a->mid_on_token, jToken);
    if (jToken != nullptr) {
        scope.env->DeleteLocalRef(jToken);
    }
    if (scope.env->ExceptionCheck()) {
        scope.env->ExceptionDescribe();
        scope.env->ExceptionClear();
        return RAC_FALSE;
    }
    return keep != JNI_FALSE ? RAC_TRUE : RAC_FALSE;
}

void stream_done_jni(rac_result_t rc, const uint8_t* bytes, size_t size, void* user_data) {
    auto* a = static_cast<StreamAdapter*>(user_data);
    if (a == nullptr || a->callback == nullptr || a->vm == nullptr) {
        return;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return;
    }
    jbyteArray jBytes = scope.env->NewByteArray(static_cast<jsize>(size));
    if (jBytes != nullptr && bytes != nullptr && size > 0) {
        scope.env->SetByteArrayRegion(jBytes, 0, static_cast<jsize>(size),
                                      reinterpret_cast<const jbyte*>(bytes));
    }
    scope.env->CallVoidMethod(a->callback, a->mid_on_done,
                              static_cast<jint>(rc), jBytes);
    if (jBytes != nullptr) {
        scope.env->DeleteLocalRef(jBytes);
    }
    if (scope.env->ExceptionCheck()) {
        scope.env->ExceptionDescribe();
        scope.env->ExceptionClear();
    }
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterGenerateStream(
    JNIEnv* env, jclass /*clazz*/, jlong router_handle, jbyteArray request_proto,
    jobject callback) {
    if (callback == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }

    jclass clazz =
        env->FindClass("com/runanywhere/sdk/public/hybrid/HybridStreamCallback");
    if (clazz == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const jmethodID mid_on_token =
        env->GetMethodID(clazz, "onToken", "(Ljava/lang/String;)Z");
    const jmethodID mid_on_done = env->GetMethodID(clazz, "onDone", "(I[B)V");
    env->DeleteLocalRef(clazz);
    if (mid_on_token == nullptr || mid_on_done == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }

    StreamAdapter adapter;
    if (env->GetJavaVM(&adapter.vm) != JNI_OK) {
        return static_cast<jint>(RAC_ERROR_INTERNAL);
    }
    adapter.callback = env->NewGlobalRef(callback);
    if (adapter.callback == nullptr) {
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }
    adapter.mid_on_token = mid_on_token;
    adapter.mid_on_done  = mid_on_done;

    const auto bytes = jbyte_array_to_vec(env, request_proto);
    const rac_result_t rc = rac_llm_hybrid_router_generate_stream_proto(
        reinterpret_cast<rac_handle_t>(router_handle),
        bytes.data(), bytes.size(),
        stream_token_jni, stream_done_jni, &adapter);

    env->DeleteGlobalRef(adapter.callback);
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmHybridRouterCancel(
    JNIEnv* /*env*/, jclass /*clazz*/, jlong router_handle) {
    if (router_handle == 0) {
        return static_cast<jint>(RAC_SUCCESS);
    }
    return static_cast<jint>(
        rac_llm_hybrid_router_cancel(reinterpret_cast<rac_handle_t>(router_handle)));
}

}  // extern "C"