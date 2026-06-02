/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Simple pub/sub for SDK events.
 *
 * Mirrors Swift EventBus.swift exactly: subscribes to the canonical native
 * SDKEvent stream via rac_sdk_event_subscribe, decodes the proto bytes, and
 * fans them into a Kotlin MutableSharedFlow so consumers see lifecycle,
 * model, error, and other events emitted by C++ commons.
 */

package com.runanywhere.sdk.public.events

import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_ERROR
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_LLM
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_MODEL
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_RAG
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_SDK
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_STT
import ai.runanywhere.proto.v1.EventCategory.EVENT_CATEGORY_TTS
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.mapNotNull

/**
 * Central event bus for SDK-wide event distribution.
 *
 * Subscribe to events by category or to all events:
 *
 * ```kotlin
 * // Subscribe to all events
 * EventBus.events.collect { event ->
 *     println(event.type)
 * }
 *
 * // Subscribe to specific category
 * EventBus.events(EventCategory.LLM).collect { event ->
 *     println(event.type)
 * }
 * ```
 *
 * Mirrors Swift EventBus exactly. Native SDK events emitted by C++ commons
 * (model lifecycle, errors, init, device, etc.) flow into this bus through
 * the [start] / [stop] lifecycle hooks called by the platform bridge during
 * SDK init/shutdown.
 */
object EventBus {
    // MARK: - Publishers

    private val logger = SDKLogger.shared

    private val _events =
        MutableSharedFlow<SDKEvent>(
            replay = 0,
            extraBufferCapacity = 64,
        )

    /** All events flow */
    val events: Flow<SDKEvent> = _events.asSharedFlow()

    // MARK: - Native subscription lifecycle

    /**
     * Start the native SDK event subscription. Idempotent: calling twice
     * is a no-op. Invoked by the platform bridge after C++ commons is
     * initialized so native events are delivered into [events].
     */
    fun start() {
        startNativeSubscription()
    }

    /**
     * Stop the native SDK event subscription. Idempotent: calling twice
     * is a no-op. Invoked by the platform bridge during shutdown so the
     * native side releases the subscription slot.
     */
    fun stop() {
        stopNativeSubscription()
    }

    /**
     * Internal entry point used by the platform bridge to push a native
     * SDKEvent into the bus. Non-suspending; safe to call from any
     * thread (including the JNI callback thread).
     */
    internal fun emitFromNative(event: SDKEvent) {
        _events.tryEmit(event)
    }

    // MARK: - Publishing

    /**
     * Publish an event to all subscribers.
     *
     * Mirrors Swift: tries the native publish path first so the canonical
     * stream sees the event (and re-delivers it back through the
     * subscription); falls back to a direct local emit if native is not
     * available (e.g. native lib not loaded).
     */
    fun publish(event: SDKEvent) {
        logger.debug("Publishing event: ${event.id} (category: ${event.category})")
        if (!publishToNative(event)) {
            _events.tryEmit(event)
        }
    }

    // MARK: - Filtered Subscriptions

    /**
     * Get events for a specific category.
     */
    fun events(category: EventCategory): Flow<SDKEvent> {
        return events.filter { it.category == category }
    }

    /**
     * Extract a specific payload type from the proto envelope stream.
     *
     * Replaces the pre-proto `eventsOfType<T : SDKEvent>()` API. The
     * generated `SDKEvent` is the top-level Wire envelope with optional
     * `oneof` payload fields (model, generation, voice, etc.); payload
     * types like [ModelEvent] are sibling messages, not subclasses, so
     * the old `is T` filter could not work. Use the per-payload helpers
     * below for common cases, or call this directly:
     *
     * ```kotlin
     * RunAnywhere.events
     *     .eventsOfPayload { it.model }
     *     .collect { modelEvent: ModelEvent -> ... }
     * ```
     */
    fun <T : Any> eventsOfPayload(selector: (SDKEvent) -> T?): Flow<T> = events.mapNotNull(selector)

    /** Stream of [ModelEvent] payloads extracted from the SDKEvent envelope. */
    val modelEventPayloads: Flow<ModelEvent>
        get() = eventsOfPayload { it.model }

    /** Stream of [GenerationEvent] payloads (LLM token + streaming generation events). */
    val generationEventPayloads: Flow<GenerationEvent>
        get() = eventsOfPayload { it.generation }

    /** Stream of [VoiceEvent] payloads (voice-agent pipeline events). */
    val voiceEventPayloads: Flow<VoiceEvent>
        get() = eventsOfPayload { it.voice_pipeline }

    /** Stream of [DownloadEvent] payloads (model download progress / lifecycle). */
    val downloadEventPayloads: Flow<DownloadEvent>
        get() = eventsOfPayload { it.download }

    /** Stream of [ComponentLifecycleEvent] payloads. */
    val componentLifecycleEventPayloads: Flow<ComponentLifecycleEvent>
        get() = eventsOfPayload { it.component_lifecycle }

    /** Stream of [ModelRegistryEvent] payloads. */
    val modelRegistryEventPayloads: Flow<ModelRegistryEvent>
        get() = eventsOfPayload { it.model_registry }

    // MARK: - Convenience Methods

    /**
     * Get LLM events.
     */
    val llmEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_LLM)

    /**
     * Get STT events.
     */
    val sttEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_STT)

    /**
     * Get TTS events.
     */
    val ttsEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_TTS)

    /**
     * Get model events.
     */
    val modelEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_MODEL)

    /**
     * Get error events.
     */
    val errorEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_ERROR)

    /**
     * Get SDK lifecycle events.
     */
    val sdkEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_SDK)

    /**
     * Get RAG events.
     */
    val ragEvents: Flow<SDKEvent>
        get() = events(EVENT_CATEGORY_RAG)
}

// Platform-specific native bridge hooks (expect/actual pattern)
