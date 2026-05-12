/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal C-ABI success constant for runanywhere-commons. All richer error
 * conversion lives on [SDKException] directly via the typed factories on
 * its companion (e.g. `SDKException.make(...)`, `SDKException.modelNotFound(...)`).
 */

package com.runanywhere.sdk.foundation.errors

/**
 * Minimal convenience constants for runanywhere-commons return codes.
 *
 * For new code, prefer the typed factories on [SDKException.Companion]
 * (e.g. `SDKException.make(...)`, `SDKException.modelNotFound(...)`) when
 * mapping a `rac_result_t` integer to a typed error.
 */
object CommonsErrorCode {
    /** Operation completed successfully. */
    const val RAC_SUCCESS = 0

    /**
     * Check if an error code indicates success.
     *
     * @param code The C++ error code
     * @return true if the code indicates success (>= 0)
     */
    fun isSuccess(code: Int): Boolean = code >= 0

    /**
     * Check if an error code indicates failure.
     *
     * @param code The C++ error code
     * @return true if the code indicates failure (< 0)
     */
    fun isError(code: Int): Boolean = code < 0
}
