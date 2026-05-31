/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.hybrid

/**
 * Events emitted by [RACRouter.LlmRouter.generateStream]. The stream emits
 * zero or more [Token] events followed by exactly one terminal [Done]
 * carrying the same [RoutedMetadata] returned by the non-streaming
 * [RACRouter.LlmRouter.generate] call.
 */
sealed class StreamEvent {
    data class Token(val text: String) : StreamEvent()
    data class Done(val routing: RoutedMetadata) : StreamEvent()
}