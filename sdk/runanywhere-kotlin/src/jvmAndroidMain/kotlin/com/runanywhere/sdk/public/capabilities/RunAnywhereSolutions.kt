/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for L5 solutions runtime (T4.7 / T4.8). A "solution" is a
 * prepackaged pipeline config — either a typed `SolutionConfig` proto or
 * YAML sugar — that the C++ core compiles into a GraphScheduler DAG and
 * runs through the `rac_solution_*` C ABI.
 *
 * Capability shape mirrors the other 4 SDKs:
 *
 *     val handle = RunAnywhere.solutions.run(config)        // typed proto
 *     val handle = RunAnywhere.solutions.run(configBytes)   // raw bytes
 *     val handle = RunAnywhere.solutions.runYaml(yamlText)  // YAML sugar
 *     handle.start(); handle.feed("..."); handle.close()
 */

package com.runanywhere.sdk.public.capabilities

import ai.runanywhere.proto.v1.SolutionConfig
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicLong

private val solutionsLogger = SDKLogger("Solutions")

/**
 * Lifecycle handle for a started solution.
 *
 * Owns the underlying `rac_solution_handle_t` and forwards each verb to
 * the matching JNI thunk. `close()` (or `destroy()`) is idempotent and
 * always safe; the handle is also released by the finalizer if the caller
 * forgets — but explicit close is the contract.
 */
public class SolutionHandle internal constructor(
    handle: Long,
) : AutoCloseable {
    private val handleRef = AtomicLong(handle)

    /** Start the underlying scheduler (non-blocking). */
    public fun start() {
        val h = requireHandle()
        val rc = RunAnywhereBridge.racSolutionStart(h)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "rac_solution_start failed with rc=$rc"
        }
    }

    /** Request a graceful shutdown (non-blocking). */
    public fun stop() {
        val h = requireHandle()
        val rc = RunAnywhereBridge.racSolutionStop(h)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "rac_solution_stop failed with rc=$rc"
        }
    }

    /** Force-cancel the graph; returns once worker threads observe cancellation. */
    public fun cancel() {
        val h = requireHandle()
        val rc = RunAnywhereBridge.racSolutionCancel(h)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "rac_solution_cancel failed with rc=$rc"
        }
    }

    /** Feed one UTF-8 item into the root input edge. */
    public fun feed(item: String) {
        val h = requireHandle()
        val rc = RunAnywhereBridge.racSolutionFeed(h, item)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "rac_solution_feed failed with rc=$rc"
        }
    }

    /** Signal end-of-stream on the root input edge. */
    public fun closeInput() {
        val h = requireHandle()
        val rc = RunAnywhereBridge.racSolutionCloseInput(h)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "rac_solution_close_input failed with rc=$rc"
        }
    }

    /** Cancel, join, and release native resources. Idempotent. */
    public fun destroy() {
        val h = handleRef.getAndSet(0L)
        if (h != 0L) {
            RunAnywhereBridge.racSolutionDestroy(h)
        }
    }

    /** AutoCloseable contract — delegates to [destroy]. */
    override fun close() {
        destroy()
    }

    @Suppress("DEPRECATION", "removal", "ProtectedInFinal")
    protected fun finalize() {
        val h = handleRef.getAndSet(0L)
        if (h != 0L) {
            solutionsLogger.warn("SolutionHandle finalized without explicit close — leaking C handle for $h")
            RunAnywhereBridge.racSolutionDestroy(h)
        }
    }

    private fun requireHandle(): Long {
        val h = handleRef.get()
        check(h != 0L) { "SolutionHandle has already been destroyed" }
        return h
    }
}

/**
 * Capability accessor for solution-runtime operations.
 *
 * Stateless — every handle returned by `run` / `runYaml` owns its own
 * native solution and is released via [SolutionHandle.close].
 */
public object RunAnywhereSolutions {
    /**
     * Construct a solution from a serialized `runanywhere.v1.SolutionConfig`
     * (or `PipelineSpec`) protobuf. The handle is returned in the **created**
     * state — call [SolutionHandle.start] to launch worker threads.
     *
     * @throws IllegalStateException if `rac_solution_create_from_proto` rejects
     *         the bytes (e.g. malformed proto, missing oneof, build without
     *         protobuf support).
     */
    public suspend fun run(configBytes: ByteArray): SolutionHandle =
        withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromProto(configBytes)
            check(handle != 0L) { "rac_solution_create_from_proto returned a null handle" }
            SolutionHandle(handle)
        }

    /**
     * Convenience overload — encode the typed proto and forward to
     * [run]. The bytes path is the canonical entrypoint downstream.
     */
    public suspend fun run(config: SolutionConfig): SolutionHandle =
        run(config.encode())

    /**
     * YAML sugar — accept a `SolutionConfig`-shape or `PipelineSpec`-shape
     * YAML document. Loader auto-disambiguates on the presence of `operators:`.
     */
    public suspend fun runYaml(yamlText: String): SolutionHandle =
        withContext(Dispatchers.IO) {
            ensureNativeReady()
            val handle = RunAnywhereBridge.racSolutionCreateFromYaml(yamlText)
            check(handle != 0L) { "rac_solution_create_from_yaml returned a null handle" }
            SolutionHandle(handle)
        }

    private fun ensureNativeReady() {
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) {
            error("Failed to load runanywhere_jni — solutions ABI unavailable")
        }
    }
}

/**
 * Public capability accessor — `RunAnywhere.solutions.run(config)`.
 *
 * Backed by a singleton object so callers can hold a stable reference
 * and the JVM doesn't allocate per-call.
 */
public val RunAnywhere.solutions: RunAnywhereSolutions
    get() = RunAnywhereSolutions
