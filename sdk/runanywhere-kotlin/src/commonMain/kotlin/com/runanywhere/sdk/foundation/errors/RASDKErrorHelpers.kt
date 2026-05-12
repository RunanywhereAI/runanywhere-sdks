/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RASDKErrorHelpers — ergonomic helpers attached to the canonical proto
 * error type (`ai.runanywhere.proto.v1.SDKError`, named `RASDKError` in the
 * Swift SDK). Mirrors `Foundation/Errors/RASDKError+Helpers.swift` (97 LOC).
 *
 * The proto SDKError is the on-the-wire canonical form. These extensions
 * restore Kotlin conveniences (category-specific construction, log
 * summary, throw-as-exception) without needing a hand-rolled wrapper.
 *
 * Notes:
 *   * The Wire-generated `SDKError` is an immutable Kotlin class; it cannot
 *     extend `Throwable`, so callers that need to throw should use
 *     `SDKException(proto:)` — `throwAsException()` does this internally.
 *   * `cAbiCode` is NOT populated by `make(...)`. The canonical
 *     `rac_result_t -> proto` translation lives in the commons C ABI
 *     (`rac_result_to_proto_error`). Use `RASDKError.from(rcResult)` when
 *     you have a raw `rac_result_t` integer — that helper delegates to the
 *     commons ABI via the JNI thunk
 *     [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racResultToProtoError].
 */

package com.runanywhere.sdk.foundation.errors

import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode
import ai.runanywhere.proto.v1.SDKError as ProtoSDKError

// ============================================================================
// RASDKError (proto SDKError) factories
// ============================================================================

/**
 * Construct a proto error directly.
 *
 * Mirrors Swift's `RASDKError.make(code:message:category:nestedMessage:)`.
 *
 * `cAbiCode` is NOT populated here. Callers that need to round-trip through
 * the C ABI should go through [ProtoSDKError.Companion.from] (rcResult), which
 * delegates to the canonical commons ABI `rac_result_to_proto_error` so the
 * `rac_result_t -> proto` mapping lives in a single place across every SDK.
 *
 * @param code     The proto error code (positive magnitude of C ABI code).
 * @param message  Human-readable, non-localized error message.
 * @param category Coarse routing bucket. Defaults to
 *                 [ProtoErrorCategory.ERROR_CATEGORY_COMPONENT].
 * @param nestedMessage Optional underlying-error message captured at wrap time.
 */
fun ProtoSDKError.Companion.make(
    code: ProtoErrorCode,
    message: String,
    category: ProtoErrorCategory = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
    nestedMessage: String? = null,
): ProtoSDKError =
    ProtoSDKError(
        code = code,
        category = category,
        message = message,
        nested_message = nestedMessage,
    )

// ============================================================================
// RASDKError (proto SDKError) instance helpers
// ============================================================================

/**
 * Format a one-line summary suitable for logs / debug output.
 *
 * Mirrors Swift's `RASDKError.summary` computed property:
 *   `[\(category)] \(code): \(message)`
 */
val ProtoSDKError.summary: String
    get() = "[${this.category}] ${this.code}: ${this.message}"

/**
 * Throw this proto error wrapped as an [SDKException]. Returns [Nothing].
 *
 * Mirrors Swift's `RASDKError.throwAsException() throws -> Never`.
 */
fun ProtoSDKError.throwAsException(): Nothing = throw SDKException(error = this)

// ============================================================================
// C ABI → proto bridge
// ============================================================================

/**
 * Map a `rac_result_t` integer to a proto-backed [ProtoSDKError]. Returns
 * `null` for `RAC_SUCCESS` (i.e. any non-negative result code).
 *
 * Mirrors Swift's `RASDKError.from(rcResult:)` in
 * `Sources/RunAnywhere/Foundation/Errors/RASDKError+Helpers.swift`.
 *
 * The Swift helper delegates to the canonical commons ABI
 * `rac_result_to_proto_error` so the translation table lives in one place.
 * The Kotlin SDK currently reuses [SDKException.fromCAbiCode] which performs
 * the equivalent mapping in the JVM layer (positive-magnitude proto code +
 * inferred category). A JNI thunk
 * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racResultToProtoError]
 * is declared for a future swap to the commons path once the matching
 * `Java_*` export is added to `runanywhere_commons_jni.cpp`.
 */
fun ProtoSDKError.Companion.from(rcResult: Int): ProtoSDKError? {
    if (rcResult >= 0) return null
    return SDKException.fromCAbiCode(rcResult).error
}
