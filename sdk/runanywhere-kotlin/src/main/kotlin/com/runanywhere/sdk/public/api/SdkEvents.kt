/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.events`, the lifecycle breadcrumb stream.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.InitializationStage
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.SDKComponent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull
import ai.runanywhere.proto.v1.SDKEvent as ProtoSdkEvent

internal fun Flow<ProtoSdkEvent>.toSdkEvents(): Flow<SdkEvent> = mapNotNull { it.toSdkEvent() }

private fun ProtoSdkEvent.toSdkEvent(): SdkEvent? {
    initialization?.let { init ->
        if (init.stage == InitializationStage.INITIALIZATION_STAGE_COMPLETED) return SdkEvent.Ready
        if (init.stage == InitializationStage.INITIALIZATION_STAGE_FAILED) {
            return SdkEvent.Error(init.error.ifBlank { "SDK initialization failed" }, recoverable = false)
        }
    }
    component_lifecycle?.let { lifecycle ->
        when (lifecycle.current_state) {
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ->
                if (lifecycle.model_id.isNotEmpty()) {
                    return SdkEvent.ModelLoaded(lifecycle.model_id, lifecycle.component.toCategory())
                }
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED ->
                if (lifecycle.model_id.isNotEmpty()) {
                    return SdkEvent.ModelUnloaded(lifecycle.model_id)
                }
            else -> Unit
        }
    }
    model?.let { event ->
        when (event.kind) {
            ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED ->
                return SdkEvent.ModelLoaded(event.model_id, ModelCategory.MODEL_CATEGORY_UNSPECIFIED)
            ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED ->
                return SdkEvent.ModelUnloaded(event.model_id)
            ModelEventKind.MODEL_EVENT_KIND_LOAD_FAILED,
            ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED,
            -> return SdkEvent.Error(event.error.ifBlank { "Model operation failed" }, recoverable = true)
            else -> Unit
        }
    }
    // `FailureEvent` (the oneof arm) is deleted outright (idl/sdk_events.proto):
    // every field moved onto the envelope itself -- `component`/`operation_id`
    // already live there, and `error` is now `SDKEvent.error` directly (an
    // optional SDKError), with `recoverable` renamed `SDKError.retryable`.
    // Mirrors Swift's `proto.category == .failure || .error` check.
    this.error?.let {
        return SdkEvent.Error(it.message.ifBlank { "SDK error" }, recoverable = it.retryable)
    }
    return null
}

private fun SDKComponent.toCategory(): ModelCategory =
    when (this) {
        SDKComponent.SDK_COMPONENT_LLM -> ModelCategory.MODEL_CATEGORY_LANGUAGE
        SDKComponent.SDK_COMPONENT_VLM -> ModelCategory.MODEL_CATEGORY_MULTIMODAL
        SDKComponent.SDK_COMPONENT_STT -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        SDKComponent.SDK_COMPONENT_TTS -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        SDKComponent.SDK_COMPONENT_VAD -> ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        SDKComponent.SDK_COMPONENT_EMBEDDINGS -> ModelCategory.MODEL_CATEGORY_EMBEDDING
        SDKComponent.SDK_COMPONENT_DIFFUSION -> ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION
        SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION -> ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION
        SDKComponent.SDK_COMPONENT_SEMANTIC_SEGMENTATION -> ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION
        else -> ModelCategory.MODEL_CATEGORY_UNSPECIFIED
    }
