/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.native.bridge

/** A failed native proto call with its lossless `rac_result_t` status. */
internal class NativeProtoException(
    val resultCode: Int,
    message: String,
) : IllegalStateException(message)
