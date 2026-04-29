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
 * Round 1 KOTLIN (G-A1): Migrated from bare `RunAnywhere.runSolution(...)`
 * top-level methods to the canonical `RunAnywhere.solutions.run(...)`
 * namespace. Bare names DELETED — no aliases, no @Deprecated.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.SolutionConfig
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Opaque, ARC-safe wrapper around a `rac_solution_handle_t`.
 *
 * Owns the underlying C handle and guarantees `rac_solution_destroy`
 * runs at most once. Lifecycle verbs are forwarded one-to-one to the C ABI.
 *
 * Per canonical §11: every method `start, stop, cancel, feed, closeInput,
 * destroy` exists, plus `isAlive` query.
 */
expect class SolutionHandle {
    /** Whether the handle still owns a live C-side solution. */
    val isAlive: Boolean

    /** Start the underlying scheduler. Non-blocking. */
    suspend fun start()

    /** Request a graceful shutdown. Non-blocking. */
    suspend fun stop()

    /** Force-cancel the graph. Returns once worker threads observe cancellation. */
    suspend fun cancel()

    /** Feed a single byte payload into the root input edge. */
    suspend fun feed(input: ByteArray)

    /** Signal end-of-stream on the root input edge. */
    suspend fun closeInput()

    /** Cancel, join, and destroy the solution. Idempotent. */
    suspend fun destroy()
}

/**
 * Capability namespace for solution-runtime operations.
 *
 * Stateless from the public perspective — every handle returned by
 * `run` owns its own native solution and is released via
 * [SolutionHandle.destroy].
 */
expect class Solutions internal constructor() {
    /**
     * Construct and return a started solution from a YAML document.
     */
    suspend fun run(yaml: String): SolutionHandle

    /**
     * Construct and return a started solution from a serialised
     * `runanywhere.v1.SolutionConfig` proto.
     */
    suspend fun run(configBytes: ByteArray): SolutionHandle

    /**
     * Construct and return a started solution from a typed
     * `SolutionConfig` proto. Encoded internally and forwarded to the
     * `configBytes` overload.
     */
    suspend fun run(config: SolutionConfig): SolutionHandle
}

/**
 * Public capability accessor — `RunAnywhere.solutions.run(yaml)`.
 *
 * Backed by a singleton so callers can hold a stable reference and the
 * JVM does not allocate per-call.
 */
expect val RunAnywhere.solutions: Solutions
