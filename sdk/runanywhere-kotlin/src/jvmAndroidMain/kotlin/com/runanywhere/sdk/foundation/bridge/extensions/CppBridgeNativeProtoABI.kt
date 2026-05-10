/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Documentation/contract for the non-modality (core/platform) proto C ABI
 * symbols the Kotlin SDK depends on. Sister object to
 * [CppBridgeModalityProtoABI].
 *
 * Mirrors iOS [CppBridge+NativeProtoABI.swift]
 * (../../../../../../../../../../../../sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+NativeProtoABI.swift),
 * which provides shared helpers for optional native proto-byte C ABI
 * bindings on Apple platforms by `dlsym`-ing each symbol from the
 * RACommons binary.
 *
 * On Kotlin/JNI, the equivalent surface is reached through `external fun`
 * declarations on [com.runanywhere.sdk.native.bridge.RunAnywhereBridge] and
 * resolved implicitly at link time. No runtime symbol resolution helpers
 * are required, so this file is documentation-heavy and contains a single
 * [assertAvailable] guard that callers can use before invoking any non-
 * modality proto operation.
 *
 * Categories enumerated below mirror the C header groupings in
 * `runanywhere-commons/include/`:
 *   - rac_core.h        — init / shutdown / lifecycle
 *   - rac_platform_adapter.h — platform IoC vtable registration
 *   - rac_logger.h      — logging configuration and emission
 *   - rac_http_transport.h — HTTP transport vtable plumbing
 *   - rac_model_paths.h — canonical model directory layout
 *   - rac_model_registry.h — registered model catalog
 *   - rac_model_lifecycle.h — load / unload / current model lookup
 *   - rac_download.h    — download orchestration
 *   - rac_storage.h     — storage info / availability / deletion
 *   - rac_sdk_event.h   — pub/sub for proto-encoded SDK events
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Catalog of non-modality `rac_*` C ABI symbols required by the Kotlin
 * bridge layer. Acts as a documentation companion to the modality counterpart
 * in [CppBridgeModalityProtoABI].
 *
 * Each `external fun` listed under "JNI counterpart" on [RunAnywhereBridge]
 * eventually calls into the matching `rac_*` symbol from `librac_commons.so`.
 * Missing symbols surface as `UnsatisfiedLinkError` on first invocation and
 * are normalized to [SDKException] by the consuming bridges.
 */
object CppBridgeNativeProtoABI {
    // ====================================================================
    // CORE LIFECYCLE (rac_core.h)
    //   - rac_init           → racInit
    //   - rac_shutdown       → racShutdown
    //   - rac_is_initialized → racIsInitialized
    //
    // These three symbols underpin the Phase 1 / Phase 2 init pattern.
    // They must be present in any build of librac_commons.so; CI fails the
    // smoke build otherwise.
    // ====================================================================

    // ====================================================================
    // PLATFORM ADAPTER (rac_platform_adapter.h)
    //   - rac_set_platform_adapter → racSetPlatformAdapter
    //   - rac_get_platform_adapter → racGetPlatformAdapter
    //
    // The platform adapter is a flat C struct of function pointers
    // populated by each SDK before calling rac_init(). On Kotlin the struct
    // is materialized inside librunanywhere_jni.so from JVM callback
    // listeners; see CppBridgePlatformAdapter for the producer side.
    // ====================================================================

    // ====================================================================
    // LOGGING (rac_logger.h)
    //   - rac_configure_logging → racConfigureLogging
    //   - rac_log               → racLog
    // ====================================================================

    // ====================================================================
    // HTTP TRANSPORT (rac_http_transport.h)
    //   - rac_http_set_transport_ops → racHttpSetTransportOps (registered via CppBridgeHTTP)
    //
    // The Kotlin SDK's CppBridgeHTTP adapter implements the three-slot
    // vtable (request_send, request_stream, request_resume) and registers
    // it through this symbol. Without this registration any `rac_http_*`
    // download / auth call inside commons returns RAC_ERROR_NOT_SUPPORTED.
    // ====================================================================

    // ====================================================================
    // MODEL PATHS (rac_model_paths.h)
    //   - rac_model_paths_set_base_dir       → racModelPathsSetBaseDir
    //   - rac_model_paths_get_model_folder   → racModelPathsGetModelFolder
    // ====================================================================

    // ====================================================================
    // MODEL REGISTRY (rac_model_registry.h) — proto-only surface
    //   - rac_model_registry_register_proto         → racModelRegistryRegisterProto
    //   - rac_model_registry_update_proto           → racModelRegistryUpdateProto
    //   - rac_model_registry_get_proto              → racModelRegistryGetProto
    //   - rac_model_registry_list_proto             → racModelRegistryListProto
    //   - rac_model_registry_query_proto            → racModelRegistryQueryProto
    //   - rac_model_registry_list_downloaded_proto  → racModelRegistryListDownloadedProto
    //   - rac_model_registry_remove_proto           → racModelRegistryRemoveProto
    //   - rac_model_registry_refresh_proto          → racModelRegistryRefreshProto
    //
    // Legacy non-proto rac_model_registry_{save,get,...} symbols were
    // removed in KOT-JNI-ORPHAN. Do not re-introduce them.
    // ====================================================================

    // ====================================================================
    // MODEL LIFECYCLE (rac_model_lifecycle.h)
    //   - rac_model_lifecycle_load_proto           → racModelLifecycleLoadProto
    //   - rac_model_lifecycle_unload_proto         → racModelLifecycleUnloadProto
    //   - rac_model_lifecycle_current_model_proto  → racModelLifecycleCurrentModelProto
    //   - rac_component_lifecycle_snapshot_proto   → racComponentLifecycleSnapshotProto
    // ====================================================================

    // ====================================================================
    // DOWNLOAD (rac_download.h) — proto-only surface
    //   - rac_download_set_progress_proto_callback → racDownloadSetProgressProtoCallback
    //   - rac_download_plan_proto                  → racDownloadPlanProto
    //   - rac_download_start_proto                 → racDownloadStartProto
    //   - rac_download_cancel_proto                → racDownloadCancelProto
    //   - rac_download_resume_proto                → racDownloadResumeProto
    //   - rac_download_progress_poll_proto         → racDownloadProgressPollProto
    // ====================================================================

    // ====================================================================
    // STORAGE (rac_storage.h)
    //   - rac_storage_info_proto         → racStorageInfoProto
    //   - rac_storage_availability_proto → racStorageAvailabilityProto
    //   - rac_storage_delete_plan_proto  → racStorageDeletePlanProto
    //   - rac_storage_delete_proto       → racStorageDeleteProto
    // ====================================================================

    // ====================================================================
    // SDK EVENTS (rac_sdk_event.h)
    //   - rac_sdk_event_subscribe         → racSdkEventSubscribe
    //   - rac_sdk_event_unsubscribe       → racSdkEventUnsubscribe
    //   - rac_sdk_event_publish_proto     → racSdkEventPublishProto
    //   - rac_sdk_event_poll              → racSdkEventPoll
    //   - rac_sdk_event_publish_failure   → racSdkEventPublishFailure
    // ====================================================================

    /**
     * Verifies the runanywhere_jni native library is loaded so that the
     * `external fun` declarations enumerated above can be safely invoked.
     *
     * Unlike the Swift counterpart in `NativeProtoABI.canReceiveProtoBuffer`
     * (which probes for `rac_proto_buffer_free` via `dlsym`), the JVM does
     * not provide a portable way to test for individual JNI symbols without
     * actually invoking them. This guard therefore only checks the cached
     * `nativeLibraryLoaded` flag flipped by
     * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.ensureNativeLibraryLoaded].
     * Per-symbol availability is enforced lazily by the JVM as
     * `UnsatisfiedLinkError` on first invocation; the consuming bridges
     * normalize that into [SDKException].
     *
     * @throws SDKException with category `not supported` if the native
     *   library has not been loaded.
     */
    fun assertAvailable() {
        if (!RunAnywhereBridge.isNativeLibraryLoaded()) {
            throw SDKException.operation(
                "Native proto ABI not available: librunanywhere_jni.so is not loaded",
            )
        }
    }
}
