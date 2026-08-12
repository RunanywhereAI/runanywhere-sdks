/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for L5 solutions runtime (T4.7 / T4.8).
 *
 * A "solution" is a prepackaged pipeline config — either a serialized
 * `runanywhere.v1.SolutionConfig` proto or a YAML document — that the
 * C++ core compiles into a GraphScheduler DAG and executes through the
 * `rac_solution_*` C ABI. Mirrors Swift RunAnywhere+Solutions.swift.
 *
 * Bare `RunAnywhere.runSolution(...)` top-level methods were deleted; the
 * canonical surface is `RunAnywhere.solutions.run(...)`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.SolutionConfig
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

class SolutionHandle internal constructor(
    nativeHandle: Long,
) {
    private val handleRef = AtomicLong(nativeHandle)

    val isAlive: Boolean
        get() = handleRef.get() != 0L

    suspend fun start() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionStart(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_start failed with rc=$rc")
            }
        }
    }

    suspend fun stop() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionStop(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_stop failed with rc=$rc")
            }
        }
    }

    suspend fun cancel() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionCancel(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_cancel failed with rc=$rc")
            }
        }
    }

    suspend fun feed(input: String) {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionFeed(h, input)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_feed failed with rc=$rc")
            }
        }
    }

    suspend fun closeInput() {
        val h = requireHandle()
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racSolutionCloseInput(h)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_solution_close_input failed with rc=$rc")
            }
        }
    }

    suspend fun destroy() {
        val h = handleRef.getAndSet(0L)
        if (h != 0L) {
            withContext(Dispatchers.IO) {
                RunAnywhereBridge.racSolutionDestroy(h)
            }
        }
    }

    private fun requireHandle(): Long {
        val h = handleRef.get()
        if (h == 0L) throw SDKException.invalidState("SolutionHandle has already been destroyed")
        return h
    }
}

class Solutions internal constructor() {
    suspend fun run(yaml: String): SolutionHandle {
        ensureReady()
        return withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromYaml(yaml)
            if (handle == 0L) {
                throw SDKException.operation("rac_solution_create_from_yaml returned a null handle")
            }
            SolutionHandle(handle)
        }
    }

    suspend fun run(configBytes: ByteArray): SolutionHandle {
        ensureReady()
        return withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromProto(configBytes)
            if (handle == 0L) {
                throw SDKException.operation("rac_solution_create_from_proto returned a null handle")
            }
            SolutionHandle(handle)
        }
    }

    suspend fun run(config: SolutionConfig): SolutionHandle =
        run(config.encode())

    /**
     * Mirror Swift's `Solutions.ensureReady()` —
     * `RunAnywhere+Solutions.swift:223-228`. Block the cold-start caller until
     * Phase 2 (services + HTTP) has completed so a `run(yaml=...)` issued
     * immediately after `RunAnywhere.initialize(...)` does not race against a
     * half-initialised HTTP client / model registry. Throws notInitialized if
     * Phase 1 has not run.
     */
    private suspend fun ensureReady() {
        if (!RunAnywhere.isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }
        RunAnywhere.ensureServicesReady()
    }

    private fun ensureNativeReady() {
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) {
            throw SDKException.platform("Failed to load runanywhere_jni — solutions ABI unavailable")
        }
    }
}

private val SolutionsSingleton = Solutions()

val RunAnywhere.solutions: Solutions
    get() = SolutionsSingleton
