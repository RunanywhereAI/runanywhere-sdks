/**
 * @file rac_hybrid_device_state_jni.cpp
 * @brief JNI bridge that registers a Kotlin DeviceStateProvider as the
 *        cross-SDK `rac_hybrid_device_state_ops_t` vtable in commons.
 *
 * The hybrid router (STT today) reads is_online / battery_percent /
 * thermal_throttled from this vtable to drive its NETWORK / Battery filters.
 * One adapter is stashed in g_device_state_adapter while a Kotlin provider
 * is registered; it owns the GlobalRef + cached jmethodIDs, freed on the next
 * set/unset call.
 */

#include <jni.h>

#include <atomic>
#include <new>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/router/hybrid/rac_hybrid_device_state.h"

namespace {

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
 * Android NDK and as `void**` on the Linux/macOS JDK. This wrapper takes the
 * platform-appropriate cast so the same translation unit compiles cleanly
 * under either header set.
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

}  // extern "C"
