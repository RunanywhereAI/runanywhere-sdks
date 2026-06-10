/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public voice-agent type aliases.
 *
 * The concrete public data contract lives in generated Wire types from
 * idl/voice_agent_service.proto and idl/voice_events.proto. Keep this file as
 * an import-stability shim only; do not add hand-written duplicate models here.
 */

package com.runanywhere.sdk.public.extensions.VoiceAgent

import ai.runanywhere.proto.v1.ComponentLifecycleState
import kotlin.math.roundToInt

// VoiceAgentComponentStates now uses the richer canonical
// `ComponentLifecycleState` (shared with SDKEvent). The former
// `ComponentLoadState.LOADED` case maps to
// `ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY`.
typealias ComponentLoadState = ai.runanywhere.proto.v1.ComponentLifecycleState
typealias VoiceAgentComponentStates = ai.runanywhere.proto.v1.VoiceAgentComponentStates
typealias VoiceAgentConfiguration = ai.runanywhere.proto.v1.VoiceAgentComposeConfig
typealias VoiceAgentResult = ai.runanywhere.proto.v1.VoiceAgentResult
typealias VoiceSessionConfig = ai.runanywhere.proto.v1.VoiceSessionConfig
typealias VoiceSessionError = ai.runanywhere.proto.v1.VoiceSessionError

val ComponentLoadState.isLoaded: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY

val ComponentLoadState.isLoading: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_LOADING

val VoiceSessionConfig.silenceDuration: Double
    get() = silence_duration_ms.toDouble() / MILLIS_PER_SECOND

fun VoiceSessionConfig.withSilenceDuration(seconds: Double): VoiceSessionConfig =
    copy(silence_duration_ms = (seconds.coerceAtLeast(0.0) * MILLIS_PER_SECOND).roundToInt())

val VoiceSessionConfig.autoPlayTTS: Boolean
    get() = auto_play_tts

fun VoiceSessionConfig.withAutoPlayTTS(enabled: Boolean): VoiceSessionConfig =
    copy(auto_play_tts = enabled)

val VoiceSessionError.errorDescription: String?
    get() = message.ifBlank { null }

val VoiceSessionError.localizedMessage: String?
    get() = errorDescription

private const val MILLIS_PER_SECOND = 1_000.0
