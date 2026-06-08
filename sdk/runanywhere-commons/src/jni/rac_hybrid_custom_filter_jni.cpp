/**
 * @file rac_hybrid_custom_filter_jni.cpp
 * @brief JNI bridge that registers a Kotlin custom-filter predicate as a
 *        NAMED entry in the cross-SDK rac_hybrid_custom_filter table in
 *        commons.
 *
 * The hybrid router (STT today) resolves a HybridFilter.Custom by NAME and
 * invokes the registered predicate during candidate filtering — so the
 * custom-filter decision lives in commons instead of leaking back into the
 * Kotlin layer (which used to toggle router slots around the call). Each
 * registered name owns one adapter holding a JavaVM + GlobalRef to the Kotlin
 * predicate object plus its cached jmethodID; the adapter is freed when the
 * name is re-registered or unregistered.
 *
 * Mirrors rac_hybrid_device_state_jni.cpp's EnvScope + adapter lifecycle; the
 * only structural difference is that this keeps a name→adapter map (a policy
 * may install several distinct custom filters) instead of a single slot.
 */

#include <jni.h>

#include <map>
#include <mutex>
#include <new>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/router/hybrid/rac_hybrid_custom_filter.h"
#include "rac/router/hybrid/rac_hybrid_types.h"

namespace {

struct CustomFilterAdapter {
    JavaVM*   vm = nullptr;
    jobject   predicate = nullptr;  // GlobalRef to CustomFilterPredicate
    jmethodID mid_evaluate = nullptr;
};

// name → adapter. Guarded by g_mutex; the commons-side named table
// (rac_hybrid_custom_filter.cpp) owns the predicate-pointer publication, this
// map only owns the JNI GlobalRef lifetime per name.
std::mutex                                       g_mutex;
std::map<std::string, CustomFilterAdapter*>      g_adapters;

/**
 * AttachCurrentThread's first parameter is `JNIEnv**` on the Android NDK and
 * `void**` on the Linux/macOS JDK. Cast per-platform so this TU compiles under
 * either header set (identical to the device-state bridge).
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

// Commons-facing predicate: marshal candidate_model_id → Kotlin and return its
// verdict. Fails OPEN (eligible) on any JNI error so a transient attach/lookup
// failure never silently drops a candidate.
rac_bool_t custom_filter_predicate(const rac_hybrid_routing_context_t* ctx, void* user_data) {
    auto* a = static_cast<CustomFilterAdapter*>(user_data);
    if (a == nullptr || ctx == nullptr) {
        return RAC_TRUE;
    }
    EnvScope scope(a->vm);
    if (scope.env == nullptr) {
        return RAC_TRUE;
    }
    jstring model_id = scope.env->NewStringUTF(ctx->candidate_model_id);
    if (model_id == nullptr) {
        return RAC_TRUE;
    }
    const jboolean keep =
        scope.env->CallBooleanMethod(a->predicate, a->mid_evaluate, model_id);
    scope.env->DeleteLocalRef(model_id);
    return keep != JNI_FALSE ? RAC_TRUE : RAC_FALSE;
}

// Delete a name's adapter GlobalRef + struct. Caller holds g_mutex.
void destroy_adapter_locked(CustomFilterAdapter* a) {
    if (a == nullptr) {
        return;
    }
    EnvScope scope(a->vm);
    if (scope.env != nullptr && a->predicate != nullptr) {
        scope.env->DeleteGlobalRef(a->predicate);
    }
    delete a;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHybridRegisterCustomFilter(
    JNIEnv* env, jclass /*clazz*/, jstring name, jobject predicate) {
    if (name == nullptr || predicate == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const char* name_utf = env->GetStringUTFChars(name, nullptr);
    if (name_utf == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const std::string name_str(name_utf);
    env->ReleaseStringUTFChars(name, name_utf);

    jclass clazz = env->FindClass("com/runanywhere/sdk/public/hybrid/CustomFilterPredicate");
    if (clazz == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }
    const jmethodID mid_evaluate =
        env->GetMethodID(clazz, "evaluate", "(Ljava/lang/String;)Z");
    env->DeleteLocalRef(clazz);
    if (mid_evaluate == nullptr) {
        return static_cast<jint>(RAC_ERROR_INVALID_PARAMETER);
    }

    auto* adapter = new (std::nothrow) CustomFilterAdapter();
    if (adapter == nullptr) {
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }
    if (env->GetJavaVM(&adapter->vm) != JNI_OK) {
        delete adapter;
        return static_cast<jint>(RAC_ERROR_INTERNAL);
    }
    adapter->predicate = env->NewGlobalRef(predicate);
    if (adapter->predicate == nullptr) {
        delete adapter;
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);
    }
    adapter->mid_evaluate = mid_evaluate;

    const rac_result_t rc =
        rac_hybrid_register_custom_filter(name_str.c_str(), custom_filter_predicate, adapter);
    if (rc != RAC_SUCCESS) {
        env->DeleteGlobalRef(adapter->predicate);
        delete adapter;
        return static_cast<jint>(rc);
    }

    // Commons now points at `adapter`; retire any previous adapter under the
    // same name. The one-generation reprieve inside the commons table means a
    // request thread may still hold the prior predicate pointer, so the prior
    // adapter's user_data must outlive that window — register the new entry
    // FIRST (above), then free the old GlobalRef here.
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
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHybridUnregisterCustomFilter(
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

    const rac_result_t rc = rac_hybrid_unregister_custom_filter(name_str.c_str());

    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_adapters.find(name_str);
    if (it != g_adapters.end()) {
        destroy_adapter_locked(it->second);
        g_adapters.erase(it);
    }
    return static_cast<jint>(rc);
}

}  // extern "C"
