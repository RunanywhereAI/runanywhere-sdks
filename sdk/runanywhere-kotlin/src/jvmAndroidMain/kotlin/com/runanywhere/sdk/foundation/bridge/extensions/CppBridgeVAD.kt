/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.VADConfiguration
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VADStatistics
import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.squareup.wire.Message
import com.squareup.wire.ProtoAdapter

/**
 * Mirrors Swift CppBridge+VAD.swift. Wraps `rac_vad_*_proto` C ABI.
 */
object CppBridgeVAD {
    @Volatile
    private var handle: Long = 0L

    private val lock = Any()

    /**
     * Whether the underlying native component has been created.
     * Replaces the legacy isReady/isLoaded — readiness should be queried
     * through `CppBridgeModelLifecycle.snapshot(SDK_COMPONENT_VAD)`.
     */
    val isReady: Boolean
        get() = handle != 0L

    @Throws(SDKException::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) create()
            if (handle == 0L) {
                throw SDKException.notInitialized("VAD component not created")
            }
            return handle
        }
    }

    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) return 0
            if (!CppBridge.isNativeLibraryLoaded) {
                throw SDKException.notInitialized(
                    "Native library not available. Please ensure the native libraries are bundled in your APK.",
                )
            }
            val result =
                try {
                    RunAnywhereBridge.racVadComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    throw SDKException.notInitialized(
                        "VAD native library not available: ${e.message}",
                    )
                }
            if (result == 0L) return -1
            handle = result
            return 0
        }
    }

    /**
     * Cancel the current detection. Native ABI is the source of truth;
     * the previous Kotlin-side `isCancelled` flag was deleted.
     */
    fun cancel() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentCancel(handle)
        }
    }

    /**
     * Reset the VAD state for a new audio stream.
     */
    fun reset() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentReset(handle)
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racVadComponentDestroy(handle)
            handle = 0L
        }
    }

    fun configure(configuration: VADConfiguration) {
        create()
        val rc =
            RunAnywhereBridge.racVadComponentConfigureProto(
                getHandle(),
                VADConfiguration.ADAPTER.encode(configuration),
            )
        checkRc(rc, "racVadComponentConfigureProto")
    }

    fun process(samples: FloatArray, options: VADOptions = VADOptions()): VADResult {
        create()
        return decodeOrThrow(
            VADResult.ADAPTER,
            RunAnywhereBridge.racVadComponentProcessProto(
                getHandle(),
                samples,
                VADOptions.ADAPTER.encode(options),
            ),
            "racVadComponentProcessProto",
        )
    }

    fun statistics(): VADStatistics {
        create()
        return decodeOrThrow(
            VADStatistics.ADAPTER,
            RunAnywhereBridge.racVadComponentGetStatisticsProto(getHandle()),
            "racVadComponentGetStatisticsProto",
        )
    }

    private fun <M : Message<M, *>> decodeOrThrow(
        adapter: ProtoAdapter<M>,
        bytes: ByteArray?,
        operation: String,
    ): M {
        val payload = bytes ?: throw SDKException.operation("$operation returned null")
        return try {
            adapter.decode(payload)
        } catch (e: Exception) {
            throw SDKException.operation("Failed to decode $operation result: ${e.message}")
        }
    }

    private fun checkRc(rc: Int, operation: String) {
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            throw SDKException.operation("$operation failed with rc=$rc")
        }
    }
}
