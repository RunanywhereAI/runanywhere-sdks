/**
 * @file rac_sdk_init.h
 * @brief Canonical two-phase SDK initialization C ABI.
 *
 * Collapses the duplicated Phase 1 / Phase 2 / retryHTTPSetup step list that
 * lives in every platform SDK (RunAnywhere.swift:198-555, the Kotlin
 * RunAnywhere object, RunAnywhereSDK.dart, RN RunAnywhere.ts, Web
 * RunAnywhere.ts) into a single C ABI surface owned by commons.
 *
 * Step responsibilities split:
 *   - C++ (this file)              — validate inputs, persist API key /
 *                                     base URL via the auth manager's
 *                                     rac_secure_storage_t vtable, init
 *                                     rac_sdk_state, authenticate via
 *                                     rac_auth_*, register device via
 *                                     rac_device_manager_register_if_needed,
 *                                     flush telemetry, fetch model
 *                                     assignments, ask the model registry to
 *                                     publish its discovery proto.
 *   - Platform SDK retains          — Task.detached / coroutine spawning,
 *                                     MainActor-style platform-plugin
 *                                     registration that requires UI-thread
 *                                     isolation, and the concurrency primitive
 *                                     that serializes Phase 2 (Swift's
 *                                     _servicesInitLock, Kotlin's Mutex,
 *                                     Dart's Future, RN's Promise).
 *
 * Wire format: requests and results are serialized
 * runanywhere.v1.SdkInit*Request / SdkInitResult bytes. Parameters follow the
 * canonical proto-buffer ABI: a borrowed input pair plus an owned-output
 * rac_proto_buffer_t.
 *
 * NOTE: callers MUST register their rac_platform_adapter_t,
 * rac_secure_storage_t (via rac_auth_init), rac_device_callbacks_t (via
 * rac_device_manager_set_callbacks), and rac_assignment_callbacks_t (via
 * rac_model_assignment_set_callbacks) BEFORE invoking these entry points.
 * Phase 1 / Phase 2 only orchestrate; they do not register adapters
 * themselves.
 */

#ifndef RAC_SDK_INIT_H
#define RAC_SDK_INIT_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Drive Phase 1 (synchronous core init) from serialized
 *        runanywhere.v1.SdkInitPhase1Request bytes.
 *
 * Steps owned by C++:
 *   1. Validate the request envelope (non-NULL bytes, parseable proto,
 *      api_key/base_url required for staging/production).
 *   2. Persist api_key + base_url through the secure storage vtable
 *      registered with rac_auth_init() (no-op when storage is NULL).
 *   3. Call rac_state_initialize() with environment + api_key + base_url +
 *      device_id from the request.
 *
 * The request envelope intentionally does NOT include adapter callbacks —
 * platform SDKs must already have registered rac_platform_adapter_t,
 * rac_secure_storage_t, and per-feature callback structs before invoking this
 * function. Those registrations are the inversion-of-control surface; this
 * entry point is the deterministic step list that runs ON TOP of them.
 *
 * On success: out_RASdkInitResult carries a serialized SdkInitResult with
 * phase=ONE and success=true. On failure (validation, parse, or state init):
 * success=false and the SDKError sub-message is populated.
 */
RAC_API rac_result_t rac_sdk_init_phase1_proto(const uint8_t* in_request_bytes, size_t in_size,
                                               rac_proto_buffer_t* out_RASdkInitResult);

/**
 * @brief Drive Phase 2 (async services init) from serialized
 *        runanywhere.v1.SdkInitPhase2Request bytes.
 *
 * Steps owned by C++:
 *   1. Confirm Phase 1 has run (rac_state_is_initialized()).
 *   2. Authenticate via rac_auth_*  (no-op when API key/base URL absent or
 *      environment == DEVELOPMENT and no usable Supabase config — same
 *      offline-tolerant policy as RunAnywhere.swift::setupHTTP).
 *   3. Register device via rac_device_manager_register_if_needed() when the
 *      callbacks are wired and the environment requires it.
 *   4. Fetch model assignments via rac_model_assignment_fetch() when callbacks
 *      are wired (failure is non-fatal; SDK continues with cached/local
 *      models, mirroring Swift's offline-mode behavior).
 *   5. Flush queued telemetry through rac_telemetry_manager_flush() so
 *      analytics emitted during Phase 1 reach the backend.
 *   6. Trigger filesystem-backed model discovery by handing a default
 *      ModelDiscoveryRequest to rac_model_registry_discover_proto().
 *      Returns linked / orphan counts in the result envelope.
 *
 * Failures in steps 2-5 are non-fatal — the result reports success=true with
 * http_configured / device_registered / linked_models_count flags so the SDK
 * can decide which UI affordances to enable. Failures in step 6 are also
 * non-fatal because no models is a valid steady state.
 *
 * The request envelope is reserved for future hints (force_refresh,
 * skip_device_registration). Today an empty proto is the canonical input.
 */
RAC_API rac_result_t rac_sdk_init_phase2_proto(const uint8_t* in_request_bytes, size_t in_size,
                                               rac_proto_buffer_t* out_RASdkInitResult);

/**
 * @brief Re-attempt the HTTP setup steps from Phase 2 that failed during
 *        offline initialization (typically auth + device registration).
 *
 * Mirrors RunAnywhere.swift::retryHTTPSetup:
 *   - When authentication callbacks already report rac_auth_is_authenticated()
 *     == true, the call returns success=true with http_configured=true and no
 *     side effects (idempotent fast path).
 *   - Otherwise re-runs the auth handshake using the cached api_key/base_url
 *     from rac_state, then flushes telemetry queued during the offline
 *     window.
 *
 * The result envelope carries phase=RETRY_HTTP and the same fields as Phase
 * 2; warning is populated when the retry was a no-op (e.g. "no usable
 * external config") so the SDK can downgrade to a debug-level log.
 */
RAC_API rac_result_t rac_sdk_retry_http_proto(rac_proto_buffer_t* out_RASdkInitResult);

#ifdef __cplusplus
}
#endif

#endif /* RAC_SDK_INIT_H */
