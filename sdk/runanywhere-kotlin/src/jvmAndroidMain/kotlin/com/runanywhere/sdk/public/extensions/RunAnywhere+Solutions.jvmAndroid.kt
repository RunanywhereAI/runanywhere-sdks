/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for L5 solutions runtime.
 *
 * Round 1 KOTLIN (G-A1, G-A4): wired to real `racSolution*` JNI thunks
 * declared at RunAnywhereBridge.kt:1273-1294 (no `notImplemented` stubs).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.SolutionConfig
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

private val solutionsLogger = SDKLogger("Solutions")

actual class SolutionHandle internal constructor(
    nativeHandle: Long,
) {
    private val handleRef = AtomicLong(nativeHandle)

    actual val isAlive: Boolean
        get() = handleRef.get() != 0L

    actual suspend fun start() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionStart(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_start failed with rc=$rc")
            }
        }
    }

    actual suspend fun stop() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionStop(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_stop failed with rc=$rc")
            }
        }
    }

    actual suspend fun cancel() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionCancel(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_cancel failed with rc=$rc")
            }
        }
    }

    actual suspend fun feed(input: ByteArray) {
        val h = requireHandle()
        // The C ABI's feed accepts a UTF-8 string — encode the bytes accordingly.
        val item = input.toString(Charsets.UTF_8)
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionFeed(h, item)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_feed failed with rc=$rc")
            }
        }
    }

    actual suspend fun closeInput() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionCloseInput(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_close_input failed with rc=$rc")
            }
        }
    }

    actual suspend fun destroy() {
        val h = handleRef.getAndSet(0L)
        if (h != 0L) {
            withContext(Dispatchers.IO) {
                RunAnywhereBridge.racSolutionDestroy(h)
            }
        }
    }

    @Suppress("DEPRECATION", "removal", "ProtectedInFinal")
    protected fun finalize() {
        val h = handleRef.getAndSet(0L)
        if (h != 0L) {
            solutionsLogger.warn("SolutionHandle finalized without explicit destroy — leaking C handle for $h")
            RunAnywhereBridge.racSolutionDestroy(h)
        }
    }

    private fun requireHandle(): Long {
        val h = handleRef.get()
        if (h == 0L) throw SDKException.invalidState("SolutionHandle has already been destroyed")
        return h
    }
}

actual class Solutions internal actual constructor() {
    actual suspend fun run(yaml: String): SolutionHandle =
        withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromYaml(yaml)
            if (handle == 0L) {
                throw SDKException.operation(buildCreateFailureMessage("yaml"))
            }
            SolutionHandle(handle)
        }

    actual suspend fun run(configBytes: ByteArray): SolutionHandle =
        withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromProto(configBytes)
            if (handle == 0L) {
                throw SDKException.operation(buildCreateFailureMessage("proto"))
            }
            SolutionHandle(handle)
        }

    /// The C ABI set a thread-local details string before returning the
    /// failure code that the JNI thunk swallowed into a 0L handle. Pull
    /// it back out so users see the real reason (e.g. the stub's
    /// "Solutions runtime unavailable: rac_commons was built without
    /// Protobuf support" diagnostic) instead of an opaque "null handle"
    /// message.
    private fun buildCreateFailureMessage(kind: String): String {
        val details = runCatching { RunAnywhereBridge.racErrorGetLastDetails() }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
        val base = "rac_solution_create_from_$kind returned a null handle"
        return if (details != null) "$base: $details" else base
    }

    actual suspend fun run(config: SolutionConfig): SolutionHandle =
        run(config.encode())

    private fun ensureNativeReady() {
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) {
            throw SDKException.platform("Failed to load runanywhere_jni — solutions ABI unavailable")
        }
    }
}

private val SolutionsSingleton = Solutions()

actual val RunAnywhere.solutions: Solutions
    get() = SolutionsSingleton
