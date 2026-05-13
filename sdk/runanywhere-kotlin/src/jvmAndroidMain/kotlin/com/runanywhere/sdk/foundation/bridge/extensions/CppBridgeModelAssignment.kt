/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Bridge for the C++ model assignment manager.
 *
 * Mirrors the Swift surface in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelAssignment.swift`,
 * which exposes:
 *   - register(autoFetch: Bool)              -> rac_model_assignment_set_callbacks
 *   - fetch(forceRefresh: Bool)              -> rac_model_assignment_fetch
 *   - getByFramework(framework)              -> rac_model_assignment_get_by_framework
 *   - getByCategory(category)                -> rac_model_assignment_get_by_category
 *
 * The corresponding `racModelAssignment*` JNI thunks were added in B1
 * (see `RunAnywhereBridge.kt` lines 1779-1789). On the commons side the
 * legacy struct/JSON callback path was retired after KOT-CPPBRIDGE-MOVE
 * in favour of the canonical `rac_http_transport_register` transport;
 * the HTTP GET requests issued by `rac_model_assignment_fetch` flow
 * through the OkHttp vtable installed by [OkHttpHttpTransport].
 *
 * The `register(autoFetch:)` thunk on the C side is a no-op success
 * (the auto-fetch flag is currently consumed inside `rac_init`); this
 * Kotlin wrapper keeps the API symmetric with Swift so that callers can
 * write the same code on both SDKs.
 *
 * Decoding strategy mirrors `CppBridgeModelRegistry`: the JNI bytes
 * payload is fed through `ProtoModelInfoList.ADAPTER.decode` and the
 * result list is returned.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAInferenceFramework
import com.runanywhere.sdk.public.types.RAModelCategory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import ai.runanywhere.proto.v1.ModelInfo as ProtoModelInfo
import ai.runanywhere.proto.v1.ModelInfoList as ProtoModelInfoList

/**
 * Model assignment bridge — fetches device-assigned models from the backend.
 *
 * Mirrors Swift's `CppBridge.ModelAssignment` enum namespace. All business
 * logic (caching, JSON parsing, registry saving) lives in C++; Kotlin
 * only registers callbacks and decodes proto results.
 */
object CppBridgeModelAssignment {
    private const val TAG = "CppBridge/ModelAssignment"

    private val logger = SDKLogger(TAG)

    @Volatile
    private var isRegistered: Boolean = false

    // ========================================================================
    // REGISTRATION
    // ========================================================================

    /**
     * Register callbacks with the C++ model assignment manager. Called during
     * SDK initialization.
     *
     * Mirrors Swift `CppBridge.ModelAssignment.register(autoFetch:)`. The
     * underlying `racModelAssignmentSetCallbacks` thunk is currently a
     * no-op success on the commons side — the actual HTTP GET callback is
     * served by the canonical platform HTTP transport registered via
     * [OkHttpHttpTransport] / `rac_http_transport_register`. The
     * `autoFetch` flag is forwarded to commons for parity with Swift
     * even though commons does not yet consume it through this entry
     * point.
     *
     * @param autoFetch Whether to auto-fetch model assignments after
     *                  registration. Should be `false` for development
     *                  mode, `true` for staging/production.
     */
    @Synchronized
    fun register(autoFetch: Boolean = false) {
        if (isRegistered) return

        // The cb parameter is reserved for future callback-struct wiring;
        // commons currently ignores its contents and the thunk returns
        // RAC_SUCCESS unconditionally. We pass a placeholder object so
        // the JNI signature is satisfied.
        val placeholderCallbacks = Any()
        val result = RunAnywhereBridge.racModelAssignmentSetCallbacks(placeholderCallbacks)

        if (result == RunAnywhereBridge.RAC_SUCCESS) {
            isRegistered = true
            logger.debug("Model assignment callbacks registered (autoFetch=$autoFetch)")
        } else {
            logger.error("Failed to register model assignment callbacks: $result")
        }
    }

    // ========================================================================
    // PUBLIC API
    // ========================================================================

    /**
     * Fetch model assignments from the backend.
     *
     * Mirrors Swift `CppBridge.ModelAssignment.fetch(forceRefresh:)` —
     * `async throws -> [RAModelInfo]`. Commons performs an HTTP GET via the
     * registered transport (OkHttp on Android/JVM), parses the response,
     * caches assignments, and returns the resulting [ProtoModelInfo] list.
     * The JNI thunk blocks the calling thread for the duration of the HTTP
     * request, so the body is wrapped in [withContext] on [Dispatchers.IO]
     * to keep callers off the main thread.
     *
     * After commons completes the fetch the cached list is read back via
     * the unfiltered framework query — the fetch thunk itself returns only
     * the success/failure status code.
     *
     * @param forceRefresh Force refresh even if cached.
     * @return The serialized [ProtoModelInfo] records returned by the
     *         backend. May be empty if no assignments are configured.
     * @throws SDKException if the fetch transport returns a non-success
     *         status code.
     */
    suspend fun fetch(forceRefresh: Boolean = false): List<ProtoModelInfo> =
        withContext(Dispatchers.IO) {
            val result = RunAnywhereBridge.racModelAssignmentFetch(forceRefresh)

            if (result != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.networkError("Failed to fetch model assignments: $result")
            }

            // Commons does not return the fetched payload through the Fetch
            // thunk — it caches the assignments internally. Read them back via
            // the unfiltered framework query (UNSPECIFIED == 0) which the C
            // side treats as "no framework filter" in commons' assignment
            // accessor. If commons later tightens that semantic, callers
            // should switch to the per-framework / per-category accessors.
            val models =
                decodeList(
                    kind = "fetch",
                    bytes =
                        RunAnywhereBridge.racModelAssignmentGetByFramework(
                            RAInferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED.value,
                        ),
                )
            logger.info("Fetched ${models.size} model assignments")
            models
        }

    /**
     * Get cached models for a specific framework.
     *
     * Mirrors Swift `CppBridge.ModelAssignment.getByFramework(_:)`.
     *
     * @param framework The proto-canonical [RAInferenceFramework] (alias
     *                  of [ai.runanywhere.proto.v1.InferenceFramework]).
     *                  Its wire [RAInferenceFramework.value] is forwarded
     *                  to the JNI thunk (`RAC_FRAMEWORK_*` matches the
     *                  proto value 1-to-1).
     * @return Cached models registered to the given framework. Empty list
     *         on decode failure or when commons returns null.
     */
    fun getByFramework(framework: RAInferenceFramework): List<ProtoModelInfo> =
        decodeList(
            kind = "getByFramework",
            bytes = RunAnywhereBridge.racModelAssignmentGetByFramework(framework.value),
        )

    /**
     * Get cached models for a specific category.
     *
     * Mirrors Swift `CppBridge.ModelAssignment.getByCategory(_:)`.
     *
     * @param category The proto-canonical [RAModelCategory] (alias of
     *                 [ai.runanywhere.proto.v1.ModelCategory]). Its wire
     *                 [RAModelCategory.value] is forwarded to the JNI
     *                 thunk (`RAC_MODEL_CATEGORY_*` matches the proto
     *                 value 1-to-1).
     * @return Cached models classified under the given category. Empty
     *         list on decode failure or when commons returns null.
     */
    fun getByCategory(category: RAModelCategory): List<ProtoModelInfo> =
        decodeList(
            kind = "getByCategory",
            bytes = RunAnywhereBridge.racModelAssignmentGetByCategory(category.value),
        )

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    /**
     * Decode the serialized [ProtoModelInfoList] payload returned by the
     * native bridge. Returns an empty list when commons returned null or
     * when the bytes cannot be decoded — this matches Swift's "warning
     * + empty list" recovery semantics on the get-by-* paths.
     */
    private fun decodeList(kind: String, bytes: ByteArray?): List<ProtoModelInfo> {
        if (bytes == null) return emptyList()
        if (bytes.isEmpty()) return emptyList()
        return try {
            ProtoModelInfoList.ADAPTER.decode(bytes).models
        } catch (e: Exception) {
            logger.warning("Failed to decode ModelInfoList from $kind: ${e.message}")
            emptyList()
        }
    }
}
