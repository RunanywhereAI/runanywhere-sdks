/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.hybrid

/**
 * JNI sink for the streaming hybrid router. Internal — bridges native
 * `rac_hybrid_stream_token_fn` + `rac_hybrid_stream_done_fn` callbacks
 * back to the Kotlin Flow built by [RACRouter.LlmRouter.generateStream].
 *
 * @see com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racLlmHybridRouterGenerateStream
 */
interface HybridStreamCallback {
    /**
     * Fired once per generated token. The native side calls back on the
     * binding's invoking thread; return `true` to keep streaming, `false`
     * to signal a cooperative stop. (Hard cancellation should go through
     * [com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racLlmHybridRouterCancel]
     * because not every engine respects the cooperative return.)
     */
    fun onToken(token: String): Boolean

    /**
     * Fired exactly once after the stream terminates (success, cancel, or
     * failed fallback).
     *
     * @param rc            Native rc from the streaming call.
     * @param responseProto Serialized `runanywhere.v1.HybridLlmGenerateResponse`;
     *                      `text` is empty (tokens arrived via [onToken]) and
     *                      `routing` carries the final [RoutedMetadata].
     *                      May be empty when the encoder failed.
     */
    fun onDone(rc: Int, responseProto: ByteArray)
}