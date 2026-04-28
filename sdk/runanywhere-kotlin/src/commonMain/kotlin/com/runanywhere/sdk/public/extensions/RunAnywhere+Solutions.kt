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
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

/**
 * Opaque, ARC-safe wrapper around a `rac_solution_handle_t`.
 *
 * Owns the underlying C handle and guarantees `rac_solution_destroy`
 * runs at most once. Lifecycle verbs are forwarded one-to-one to the C ABI.
 */
expect class SolutionHandle {
    /** Start the underlying scheduler. Non-blocking. */
    suspend fun start()

    /** Request a graceful shutdown. Non-blocking. */
    suspend fun stop()

    /** Force-cancel the graph. Returns once worker threads observe cancellation. */
    suspend fun cancel()

    /** Feed a single UTF-8 item into the root input edge. */
    suspend fun feed(item: String)

    /** Signal end-of-stream on the root input edge. */
    suspend fun closeInput()

    /** Cancel, join, and destroy the solution. Idempotent. */
    suspend fun destroy()
}

/**
 * Construct and return a started solution from a serialised
 * `runanywhere.v1.SolutionConfig` proto.
 *
 * @param configBytes Serialized SolutionConfig proto bytes.
 */
expect suspend fun RunAnywhere.runSolution(configBytes: ByteArray): SolutionHandle

/**
 * YAML sugar — construct a solution from a YAML document.
 *
 * @param yaml YAML document body.
 */
expect suspend fun RunAnywhere.runSolutionFromYaml(yaml: String): SolutionHandle
