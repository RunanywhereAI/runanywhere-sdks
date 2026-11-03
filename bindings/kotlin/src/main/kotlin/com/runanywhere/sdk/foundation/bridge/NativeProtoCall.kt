/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeProtoException

/** Map shared JNI proto failures before callers decode the response. */
internal inline fun <T> withNativeProtoFailure(block: () -> T): T =
    try {
        block()
    } catch (error: NativeProtoException) {
        val mapped = SDKException.fromRACResult(error.resultCode) ?: throw error
        throw SDKException(
            error = mapped.error.copy(message = error.message ?: mapped.error.message),
            cause = error,
        )
    }
