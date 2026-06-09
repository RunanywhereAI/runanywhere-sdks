/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Typed model-lifecycle stream over the raw SDK event bus.
 *
 * Native commons signals "model loaded/unloaded" on THREE different proto
 * channels depending on the path that performed the work:
 *   1. component-lifecycle events (EVENT_CATEGORY_COMPONENT,
 *      `component_lifecycle.current_state`) — the `loadModel` path,
 *   2. model events (`model.kind` load/unload completed),
 *   3. LLM generation events (`generation.kind` modelLoaded/Unloaded).
 *
 * Which channel fires when is an SDK-internal detail. Consumers should not
 * need to know it — before this helper every app ViewModel hand-decoded all
 * three with an identical switch. `EventBus.modelLifecycle` folds them into
 * one typed stream; `modelLoaded` / `modelUnloaded` are pre-filtered views.
 *
 * Mirrors Swift `EventBus+ModelLifecycle.swift` exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ComponentLifecycleState
import ai.runanywhere.proto.v1.EventCategory
import ai.runanywhere.proto.v1.GenerationEventKind
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.SDKComponent
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.SDKEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.mapNotNull

// MARK: - Typed change

/** One model load/unload transition, decoded from the raw event bus. */
data class RAModelLifecycleChange(
    /** Whether the model finished loading or was unloaded. */
    val kind: Kind,
    /**
     * Registry id of the affected model. May be empty when the native
     * channel did not carry one (rare; treat as "current model").
     */
    val modelId: String,
    /** SDK component slot the change applies to (LLM, STT, TTS, ...). */
    val component: SDKComponent,
    /**
     * The underlying raw event, for consumers that need extra payload
     * fields (progress, framework, error, ...).
     */
    val event: SDKEvent,
) {
    enum class Kind {
        LOADED,
        UNLOADED,
    }
}

// MARK: - EventBus typed flows

/**
 * Unified model load/unload stream across all native signal channels.
 *
 * ```kotlin
 * RunAnywhere.events.modelLifecycle
 *     .filter { it.component == SDKComponent.SDK_COMPONENT_LLM }
 *     .collect { change -> ... }
 * ```
 */
val EventBus.modelLifecycle: Flow<RAModelLifecycleChange>
    get() = events.mapNotNull { modelLifecycleChange(it) }

/** [modelLifecycle] filtered to load completions. */
val EventBus.modelLoaded: Flow<RAModelLifecycleChange>
    get() = modelLifecycle.filter { it.kind == RAModelLifecycleChange.Kind.LOADED }

/** [modelLifecycle] filtered to unloads. */
val EventBus.modelUnloaded: Flow<RAModelLifecycleChange>
    get() = modelLifecycle.filter { it.kind == RAModelLifecycleChange.Kind.UNLOADED }

/**
 * Decode a raw SDK event into a lifecycle change, or null when the event
 * is not a load/unload transition. Exposed so non-Flow consumers can
 * reuse the exact same channel mapping.
 */
fun EventBus.modelLifecycleChange(event: SDKEvent): RAModelLifecycleChange? {
    // Channel 1: component-lifecycle (the canonical loadModel path).
    if (event.category == EventCategory.EVENT_CATEGORY_COMPONENT) {
        val lifecycle = event.component_lifecycle ?: return null
        return when (lifecycle.current_state) {
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY ->
                RAModelLifecycleChange(
                    kind = RAModelLifecycleChange.Kind.LOADED,
                    modelId = lifecycle.model_id,
                    component = lifecycle.component,
                    event = event,
                )
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_UNLOADING,
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_SHUTDOWN,
            ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_DELETING,
            ->
                RAModelLifecycleChange(
                    kind = RAModelLifecycleChange.Kind.UNLOADED,
                    modelId = lifecycle.model_id,
                    component = lifecycle.component,
                    event = event,
                )
            else -> null
        }
    }

    // Channels 2 + 3: model events and LLM generation events.
    val modelKind = event.model?.kind
    val generationKind = event.generation?.kind
    val modelId = event.model?.model_id?.takeIf { it.isNotEmpty() }
        ?: event.generation?.model_id.orEmpty()

    return when {
        modelKind == ModelEventKind.MODEL_EVENT_KIND_LOAD_COMPLETED ||
            generationKind == GenerationEventKind.GENERATION_EVENT_KIND_MODEL_LOADED ->
            RAModelLifecycleChange(
                kind = RAModelLifecycleChange.Kind.LOADED,
                modelId = modelId,
                component = event.component,
                event = event,
            )
        modelKind == ModelEventKind.MODEL_EVENT_KIND_UNLOAD_COMPLETED ||
            generationKind == GenerationEventKind.GENERATION_EVENT_KIND_MODEL_UNLOADED ->
            RAModelLifecycleChange(
                kind = RAModelLifecycleChange.Kind.UNLOADED,
                modelId = modelId,
                component = event.component,
                event = event,
            )
        else -> null
    }
}
