/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Human-readable display name for the proto-generated SDKComponent enum.
 * Mirrors iOS: Sources/RunAnywhere/Foundation/Core/RASDKComponent+DisplayName.swift
 */

package com.runanywhere.sdk.foundation.core

import ai.runanywhere.proto.v1.SDKComponent

val SDKComponent.displayName: String
    get() =
        when (this) {
            SDKComponent.SDK_COMPONENT_LLM -> "Language Model"
            SDKComponent.SDK_COMPONENT_VLM -> "Vision Language Model"
            SDKComponent.SDK_COMPONENT_STT -> "Speech to Text"
            SDKComponent.SDK_COMPONENT_TTS -> "Text to Speech"
            SDKComponent.SDK_COMPONENT_VAD -> "Voice Activity Detection"
            SDKComponent.SDK_COMPONENT_VOICE_AGENT -> "Voice Agent"
            SDKComponent.SDK_COMPONENT_EMBEDDINGS -> "Embedding"
            SDKComponent.SDK_COMPONENT_DIFFUSION -> "Image Generation"
            SDKComponent.SDK_COMPONENT_RAG -> "Retrieval-Augmented Generation"
            SDKComponent.SDK_COMPONENT_WAKEWORD -> "Wake Word"
            SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION -> "Speaker Diarization"
            SDKComponent.SDK_COMPONENT_UNSPECIFIED -> "Unknown"
        }
