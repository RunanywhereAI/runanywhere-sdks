/**
 * @file rac_device_live_state_internal.h
 * @brief Internal live device-state sampling for per-event telemetry.
 *
 * Not part of the public C ABI. The telemetry manager stamps every tracked
 * event with a live device snapshot (battery, RAM, CPU) via these helpers.
 */

#ifndef RAC_DEVICE_LIVE_STATE_INTERNAL_H
#define RAC_DEVICE_LIVE_STATE_INTERNAL_H

#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_device_live_state {
    double battery_level;   /* 0.0-1.0, negative if unavailable */
    char battery_state[16]; /* "charging"/"full"/"unplugged", "" if unavailable */
    rac_bool_t is_low_power_mode;
    rac_bool_t has_low_power_mode;
    int64_t total_memory;     /* bytes, 0 if unknown */
    int64_t available_memory; /* bytes, 0 if unknown */
} rac_device_live_state_t;

/**
 * Sample live device state via the registered device-manager callbacks.
 * Returns RAC_ERROR_NOT_INITIALIZED when no callbacks are set (e.g. CLI
 * before wiring, early init) — caller keeps unknown sentinels.
 */
rac_result_t rac_device_manager_sample_live_state(rac_device_live_state_t* out);

/**
 * System CPU usage percent (0-100) averaged since the previous call.
 * First call establishes the baseline and returns -1. Returns -1 when the
 * platform exposes no CPU accounting (e.g. WASM). Thread-safe.
 */
double rac_cpu_sample_usage_percent(void);

/** CPU cores currently online; 0 if unknown. */
int32_t rac_cpu_online_core_count(void);

/**
 * Server-driven registration heal. The authenticate response carries
 * device_registered=false when the backend just minted (or still holds) an
 * "Unknown"/"SDK Device" placeholder row for this device — the client's
 * persisted is_registered flag is stale in that case, and production mode
 * would otherwise skip registration forever. Calling this forces the next
 * rac_device_manager_register_if_needed() to register regardless of the
 * platform-persisted flag; a successful registration clears it.
 */
void rac_device_manager_notify_server_unregistered(void);

/**
 * Opt-in for live platform sampling (battery/RAM via platform callbacks) on
 * telemetry events. Only bridges whose callbacks are thread-safe from any
 * thread may enable this (JNI attaches threads; the desktop adapter is plain
 * C). Dart FFI callbacks are isolate-bound and MUST NOT be invoked from
 * inference/telemetry threads — Flutter stays disabled until its bridge
 * pushes state instead. In-process fields (CPU, core count, sdk_binding)
 * are always stamped regardless.
 */
void rac_telemetry_enable_live_platform_sampling(void);

/**
 * Push model for isolate-bound bridges (Dart FFI): the platform pushes fresh
 * battery/RAM values from its own thread; telemetry stamping reads only this
 * cache. battery_level negative = unknown; battery_state NULL/"" = unknown;
 * memory 0 = unknown. Exported with default visibility on Android/desktop so
 * Dart can bind it by name.
 */
void rac_telemetry_push_live_device_state(double battery_level, const char* battery_state,
                                          rac_bool_t is_low_power_mode, int64_t total_memory,
                                          int64_t available_memory);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DEVICE_LIVE_STATE_INTERNAL_H */
