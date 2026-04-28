/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for L5 solutions runtime.
 * Wave 2 KOTLIN: Stub pending C++ rac_solution_* JNI wiring.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

actual class SolutionHandle internal constructor(
    @Suppress("UNUSED_PARAMETER") nativeHandle: Long,
) {
    actual suspend fun start() {
        throw SDKException.notImplemented("rac_solution_start is being wired up")
    }

    actual suspend fun stop() {
        throw SDKException.notImplemented("rac_solution_stop is being wired up")
    }

    actual suspend fun cancel() {
        throw SDKException.notImplemented("rac_solution_cancel is being wired up")
    }

    actual suspend fun feed(item: String) {
        throw SDKException.notImplemented("rac_solution_feed is being wired up")
    }

    actual suspend fun closeInput() {
        throw SDKException.notImplemented("rac_solution_close_input is being wired up")
    }

    actual suspend fun destroy() {
        throw SDKException.notImplemented("rac_solution_destroy is being wired up")
    }
}

actual suspend fun RunAnywhere.runSolution(configBytes: ByteArray): SolutionHandle {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    throw SDKException.notImplemented("rac_solution_create_from_proto is being wired up")
}

actual suspend fun RunAnywhere.runSolutionFromYaml(yaml: String): SolutionHandle {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    throw SDKException.notImplemented("rac_solution_create_from_yaml is being wired up")
}
