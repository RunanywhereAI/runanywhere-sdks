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

typealias ComponentLoadState = ai.runanywhere.proto.v1.ComponentLoadState
typealias VoiceAgentComponentStates = ai.runanywhere.proto.v1.VoiceAgentComponentStates
typealias VoiceAgentConfiguration = ai.runanywhere.proto.v1.VoiceAgentComposeConfig
typealias VoiceAgentResult = ai.runanywhere.proto.v1.VoiceAgentResult
typealias VoiceSessionConfig = ai.runanywhere.proto.v1.VoiceSessionConfig
typealias VoiceSessionError = ai.runanywhere.proto.v1.VoiceSessionError
typealias VoiceSessionErrorCode = ai.runanywhere.proto.v1.VoiceSessionErrorCode
