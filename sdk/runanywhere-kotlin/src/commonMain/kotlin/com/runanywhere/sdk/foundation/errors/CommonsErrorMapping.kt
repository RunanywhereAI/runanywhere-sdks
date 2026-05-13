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
}
