/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Simple pub/sub for SDK events.
 *
 * Mirrors Swift EventBus.swift exactly.
 */

package com.runanywhere.sdk.public.events

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.filter

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
 * Mirrors Swift EventBus exactly.
 */
object EventBus {

    // MARK: - Publishers

    private val _events = MutableSharedFlow<SDKEvent>(
        replay = 0,
        extraBufferCapacity = 64
    )

    /** All events flow */
    val events: Flow<SDKEvent> = _events.asSharedFlow()

    // MARK: - Publishing

    /**
     * Publish an event to all subscribers.
     */
    fun publish(event: SDKEvent) {
        _events.tryEmit(event)
    }

    // MARK: - Filtered Subscriptions

    /**
     * Get events for a specific category.
     */
    fun events(category: EventCategory): Flow<SDKEvent> {
        return events.filter { it.category == category }
    }

    /**
     * Get events of a specific type.
     */
    inline fun <reified T : SDKEvent> eventsOfType(): Flow<T> {
        return events.filter { it is T } as Flow<T>
    }

    // MARK: - Convenience Methods

    /**
     * Get LLM events.
     */
    val llmEvents: Flow<SDKEvent>
        get() = events(EventCategory.LLM)

    /**
     * Get STT events.
     */
    val sttEvents: Flow<SDKEvent>
        get() = events(EventCategory.STT)

    /**
     * Get TTS events.
     */
    val ttsEvents: Flow<SDKEvent>
        get() = events(EventCategory.TTS)

    /**
     * Get model events.
     */
    val modelEvents: Flow<SDKEvent>
        get() = events(EventCategory.MODEL)

    /**
     * Get error events.
     */
    val errorEvents: Flow<SDKEvent>
        get() = events(EventCategory.ERROR)

    /**
     * Get SDK lifecycle events.
     */
    val sdkEvents: Flow<SDKEvent>
        get() = events(EventCategory.SDK)
}
