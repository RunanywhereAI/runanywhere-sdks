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

// VoiceAgentComponentStates now uses the richer canonical
// `ComponentLifecycleState` (shared with SDKEvent). The former
// `ComponentLoadState.LOADED` case maps to
// `ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY`.
typealias ComponentLoadState = ai.runanywhere.proto.v1.ComponentLifecycleState
typealias VoiceAgentComponentStates = ai.runanywhere.proto.v1.VoiceAgentComponentStates
typealias VoiceAgentConfiguration = ai.runanywhere.proto.v1.VoiceAgentComposeConfig
typealias VoiceAgentResult = ai.runanywhere.proto.v1.VoiceAgentResult
typealias VoiceSessionError = ai.runanywhere.proto.v1.VoiceSessionError

// VoiceSessionConfig is deleted: runanywhere.v1.VoiceSessionConfig no
// longer exists. Silence-duration configuration now lives on
// `TurnDetection.silence_duration_ms` (idl/voice_agent_service.proto);
// `auto_play_tts` has no surviving wire field anywhere in the proto tree
// and had zero live callers in this module, so the helpers built on it
// (`silenceDuration`/`withSilenceDuration`/`autoPlayTTS`/`withAutoPlayTTS`)
// are dropped rather than rehomed onto a type that cannot express them.

val ComponentLoadState.isLoaded: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY

val ComponentLoadState.isLoading: Boolean
    get() = this == ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_LOADING

val VoiceSessionError.errorDescription: String?
    get() = message.ifBlank { null }

val VoiceSessionError.localizedMessage: String?
    get() = errorDescription
