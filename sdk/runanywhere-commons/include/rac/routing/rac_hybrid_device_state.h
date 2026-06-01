/**
 * @file rac_hybrid_device_state.h
 * @brief Cross-SDK host device-state vtable for the hybrid router.
 *
 * Each platform binding (Kotlin, Swift, Flutter, RN, Web) populates this
 * vtable once at SDK init with native callbacks that report whether the
 * host has internet, current battery %, and whether the device is
 * thermally throttled.
 *
 * The native hybrid router consults this vtable (via
 * rac_hybrid_get_device_state_snapshot) on every generate() call to
 * evaluate the NETWORK / Battery filters. Bindings do NOT pass these
 * fields in the per-request routing context — the proto context message
 * is currently empty and reserved for future per-call hints.
 *
 * Thread-safety: rac_hybrid_set_device_state can be called from any
 * thread; the active vtable is swapped atomically. Callbacks themselves
 * may be invoked concurrently from request threads, so implementations
 * must be reentrant.
 *
 * Lifecycle: callbacks are invoked while the binding's user_data is
 * alive. Bindings must call rac_hybrid_set_device_state(NULL) to detach
 * before freeing their user_data — see the @warning note on the setter.
 */

#ifndef RAC_HYBRID_DEVICE_STATE_H
#define RAC_HYBRID_DEVICE_STATE_H

#include <stdbool.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Function-pointer vtable populated by each SDK binding.
 *
 * `user_data` is an opaque pointer the binding allocates and passes back
 * to each callback. Typical Kotlin shape: a small struct holding a
 * `JavaVM*` + a `jobject` GlobalRef to the Kotlin DeviceStateProvider,
 * plus cached jmethodIDs for the three accessor methods.
 *
 * All three function pointers must be non-NULL when registering via
 * rac_hybrid_set_device_state. Passing the whole struct as NULL is
 * the documented "unset" path; partial population is rejected.
 */
typedef struct rac_hybrid_device_state_ops {
    /** Returns true iff the host has a usable internet connection now. */
    bool (*is_online)(void* user_data);

    /** Returns the host battery level as a percentage in [0, 100]. */
    int32_t (*battery_percent)(void* user_data);

    /** Returns true when the device is currently thermally throttled. */
    bool (*is_thermal_throttled)(void* user_data);

    /** Opaque binding-owned pointer passed back to each callback. */
    void* user_data;
} rac_hybrid_device_state_ops_t;

/**
 * @brief Snapshot of the device-state values captured at one instant by
 *        invoking each vtable callback in sequence.
 *
 * Returned by rac_hybrid_get_device_state_snapshot. Callers consume the
 * fields directly and do not invoke any callbacks themselves — the
 * snapshot is decoupled from the vtable's lifetime.
 */
typedef struct rac_hybrid_device_state_snapshot {
    bool    is_online;
    int32_t battery_percent;
    bool    thermal_throttled;
} rac_hybrid_device_state_snapshot_t;

/**
 * @brief Install the device-state vtable that the hybrid router will
 *        consult on every generate() call.
 *
 * The provided ops struct is copied into commons-owned storage; callers
 * may free their copy on return.
 *
 * Passing @p ops == NULL restores the optimistic default vtable
 * (always-online, 100% battery, not-throttled). Useful for tests and
 * for graceful SDK teardown.
 *
 * @warning When replacing or unsetting a vtable that holds binding-owned
 *          resources (e.g. a JavaVM + GlobalRef pair on Android), the
 *          binding MUST call rac_hybrid_set_device_state(NULL) first to
 *          guarantee no request thread is mid-callback, then release its
 *          user_data. There is no native-side reference counting on
 *          user_data; freeing it while a callback is in flight is
 *          undefined behavior.
 *
 * @param ops Vtable to install, or NULL to unset.
 * @return RAC_SUCCESS on success;
 *         RAC_ERROR_INVALID_PARAMETER if @p ops is non-NULL but any of
 *         its three function pointers are NULL.
 */
RAC_API rac_result_t rac_hybrid_set_device_state(const rac_hybrid_device_state_ops_t* ops);

/**
 * @brief Capture the current device state by invoking each callback on
 *        the active vtable in sequence.
 *
 * Cheap; safe to call on the request hot path. The default vtable
 * cannot fail, so this function always populates @p out and returns
 * RAC_SUCCESS unless @p out itself is NULL.
 *
 * @param out Destination snapshot struct. Must be non-NULL.
 * @return RAC_SUCCESS on success;
 *         RAC_ERROR_INVALID_PARAMETER if @p out is NULL.
 */
RAC_API rac_result_t rac_hybrid_get_device_state_snapshot(
    rac_hybrid_device_state_snapshot_t* out);

#ifdef __cplusplus
}
#endif

#endif  // RAC_HYBRID_DEVICE_STATE_H