/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal event protocol for SDK events.
 * All event logic and definitions are in C++ (rac_analytics_events.h).
 * This Kotlin interface only provides the interface for bridged events.
 *
 * Mirrors Swift SDKEvent.swift exactly.
 */

package com.runanywhere.sdk.public.events

import com.runanywhere.sdk.public.extensions.RAG.RAGResult
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// MARK: - Event Destination

/**
 * Where an event should be routed (mirrors C++ rac_event_destination_t).
 * Mirrors Swift EventDestination exactly.
 */
enum class EventDestination {
    /** Only to public EventBus (app developers) */
    PUBLIC_ONLY,

    /** Only to analytics/telemetry (backend) */
    ANALYTICS_ONLY,

    /** Both destinations (default) */
    ALL,
}

// MARK: - Event Category

/**
 * Event categories for filtering/grouping (mirrors C++ categories).
 * Mirrors Swift EventCategory exactly.
 */
enum class EventCategory(
    val value: String,
) {
    SDK("sdk"),
    MODEL("model"),
    LLM("llm"),
    STT("stt"),
    TTS("tts"),
    VOICE("voice"),
    STORAGE("storage"),
    DEVICE("device"),
    NETWORK("network"),
    ERROR("error"),
    RAG("rag"),
}

// MARK: - SDK Event Interface

/**
 * Minimal interface for SDK events.
 *
 * Events originate from C++ and are bridged to Kotlin via EventBridge.
 * App developers can subscribe to events via EventBus.
 *
 * Mirrors Swift SDKEvent protocol exactly.
 */
interface SDKEvent {
    /** Unique identifier for this event instance */
    val id: String

    /** Event type string (from C++ event types) */
    val type: String

    /** Category for filtering/routing */
    val category: EventCategory

    /** When the event occurred (epoch milliseconds) */
    val timestamp: Long

    /** Optional session ID for grouping related events */
    val sessionId: String?

    /** Where to route this event */
    val destination: EventDestination

    /** Event properties as key-value pairs */
    val properties: Map<String, String>
}

// MARK: - Base Event Implementation

/**
 * Base implementation of SDKEvent with default values.
 */
@OptIn(ExperimentalUuidApi::class)
data class BaseSDKEvent(
    override val type: String,
    override val category: EventCategory,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
    override val properties: Map<String, String> = emptyMap(),
) : SDKEvent

// MARK: - Specific Event Types

/**
 * SDK lifecycle events.
 */
@OptIn(ExperimentalUuidApi::class)
data class SDKLifecycleEvent(
    val lifecycleType: LifecycleType,
    val version: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "sdk.${lifecycleType.value}"
    override val category: EventCategory get() = EventCategory.SDK
    override val properties: Map<String, String>
        get() =
            buildMap {
                version?.let { put("version", it) }
            }

    enum class LifecycleType(
        val value: String,
    ) {
        INITIALIZED("initialized"),
        SHUTDOWN("shutdown"),
        ERROR("error"),
    }
}

/**
 * Model-related events.
 */
@OptIn(ExperimentalUuidApi::class)
data class ModelEvent(
    val eventType: ModelEventType,
    val modelId: String,
    val progress: Float? = null,
    val error: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "model.${eventType.value}"
    override val category: EventCategory get() = EventCategory.MODEL
    override val properties: Map<String, String>
        get() =
            buildMap {
                put("model_id", modelId)
                progress?.let { put("progress", it.toString()) }
                error?.let { put("error", it) }
            }

    enum class ModelEventType(
        val value: String,
    ) {
        DOWNLOAD_STARTED("download_started"),
        DOWNLOAD_PROGRESS("download_progress"),
        DOWNLOAD_COMPLETED("download_completed"),
        DOWNLOAD_FAILED("download_failed"),
        LOADED("loaded"),
        UNLOADED("unloaded"),
        DELETED("deleted"),
    }
}

/**
 * LLM-related events.
 */
@OptIn(ExperimentalUuidApi::class)
data class LLMEvent(
    val eventType: LLMEventType,
    val modelId: String? = null,
    val tokensGenerated: Int? = null,
    val latencyMs: Double? = null,
    val error: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "llm.${eventType.value}"
    override val category: EventCategory get() = EventCategory.LLM
    override val properties: Map<String, String>
        get() =
            buildMap {
                modelId?.let { put("model_id", it) }
                tokensGenerated?.let { put("tokens_generated", it.toString()) }
                latencyMs?.let { put("latency_ms", it.toString()) }
                error?.let { put("error", it) }
            }

    enum class LLMEventType(
        val value: String,
    ) {
        GENERATION_STARTED("generation_started"),
        GENERATION_COMPLETED("generation_completed"),
        GENERATION_FAILED("generation_failed"),
        STREAM_TOKEN("stream_token"),
        STREAM_COMPLETED("stream_completed"),
    }
}

/**
 * STT-related events.
 */
@OptIn(ExperimentalUuidApi::class)
data class STTEvent(
    val eventType: STTEventType,
    val modelId: String? = null,
    val transcript: String? = null,
    val confidence: Float? = null,
    val error: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "stt.${eventType.value}"
    override val category: EventCategory get() = EventCategory.STT
    override val properties: Map<String, String>
        get() =
            buildMap {
                modelId?.let { put("model_id", it) }
                transcript?.let { put("transcript", it) }
                confidence?.let { put("confidence", it.toString()) }
                error?.let { put("error", it) }
            }

    enum class STTEventType(
        val value: String,
    ) {
        TRANSCRIPTION_STARTED("transcription_started"),
        TRANSCRIPTION_COMPLETED("transcription_completed"),
        TRANSCRIPTION_FAILED("transcription_failed"),
        PARTIAL_RESULT("partial_result"),
    }
}

/**
 * TTS-related events.
 */
@OptIn(ExperimentalUuidApi::class)
data class TTSEvent(
    val eventType: TTSEventType,
    val voice: String? = null,
    val durationMs: Double? = null,
    val error: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "tts.${eventType.value}"
    override val category: EventCategory get() = EventCategory.TTS
    override val properties: Map<String, String>
        get() =
            buildMap {
                voice?.let { put("voice", it) }
                durationMs?.let { put("duration_ms", it.toString()) }
                error?.let { put("error", it) }
            }

    enum class TTSEventType(
        val value: String,
    ) {
        SYNTHESIS_STARTED("synthesis_started"),
        SYNTHESIS_COMPLETED("synthesis_completed"),
        SYNTHESIS_FAILED("synthesis_failed"),
        PLAYBACK_STARTED("playback_started"),
        PLAYBACK_COMPLETED("playback_completed"),
    }
}

/**
 * Error events.
 */
@OptIn(ExperimentalUuidApi::class)
data class ErrorEvent(
    val errorCode: String,
    val errorMessage: String,
    val errorCategory: String? = null,
    val component: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = "error.occurred"
    override val category: EventCategory get() = EventCategory.ERROR
    override val properties: Map<String, String>
        get() =
            buildMap {
                put("error_code", errorCode)
                put("error_message", errorMessage)
                errorCategory?.let { put("error_category", it) }
                component?.let { put("component", it) }
            }
}

/**
 * RAG-related events.
 * Mirrors Swift RAGEvent exactly.
 */
@OptIn(ExperimentalUuidApi::class)
data class RAGEvent(
    val eventType: RAGEventType,
    val documentLength: Int? = null,
    val chunkCount: Int? = null,
    val durationMs: Double? = null,
    val questionLength: Int? = null,
    val answerLength: Int? = null,
    val chunksRetrieved: Int? = null,
    val retrievalTimeMs: Double? = null,
    val generationTimeMs: Double? = null,
    val totalTimeMs: Double? = null,
    val errorMessage: String? = null,
    override val id: String = Uuid.random().toString(),
    override val timestamp: Long = System.currentTimeMillis(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.PUBLIC_ONLY,
) : SDKEvent {
    override val type: String get() = "rag.${eventType.value}"
    override val category: EventCategory get() = EventCategory.RAG
    override val properties: Map<String, String>
        get() = buildMap {
            documentLength?.let { put("documentLength", it.toString()) }
            chunkCount?.let { put("chunkCount", it.toString()) }
            durationMs?.let { put("durationMs", "%.1f".format(it)) }
            questionLength?.let { put("questionLength", it.toString()) }
            answerLength?.let { put("answerLength", it.toString()) }
            chunksRetrieved?.let { put("chunksRetrieved", it.toString()) }
            retrievalTimeMs?.let { put("retrievalTimeMs", "%.1f".format(it)) }
            generationTimeMs?.let { put("generationTimeMs", "%.1f".format(it)) }
            totalTimeMs?.let { put("totalTimeMs", "%.1f".format(it)) }
            errorMessage?.let { put("message", it) }
        }

    enum class RAGEventType(val value: String) {
        INGESTION_STARTED("ingestion.started"),
        INGESTION_COMPLETE("ingestion.complete"),
        QUERY_STARTED("query.started"),
        QUERY_COMPLETE("query.complete"),
        PIPELINE_CREATED("pipeline.created"),
        PIPELINE_DESTROYED("pipeline.destroyed"),
        ERROR("error"),
    }

    companion object {
        fun ingestionStarted(documentLength: Int) = RAGEvent(
            eventType = RAGEventType.INGESTION_STARTED,
            documentLength = documentLength,
        )

        fun ingestionComplete(chunkCount: Int, durationMs: Double) = RAGEvent(
            eventType = RAGEventType.INGESTION_COMPLETE,
            chunkCount = chunkCount,
            durationMs = durationMs,
        )

        fun queryStarted(question: String) = RAGEvent(
            eventType = RAGEventType.QUERY_STARTED,
            questionLength = question.length,
        )

        fun queryComplete(result: RAGResult) = RAGEvent(
            eventType = RAGEventType.QUERY_COMPLETE,
            answerLength = result.answer.length,
            chunksRetrieved = result.retrievedChunks.size,
            retrievalTimeMs = result.retrievalTimeMs,
            generationTimeMs = result.generationTimeMs,
            totalTimeMs = result.totalTimeMs,
        )

        fun pipelineCreated() = RAGEvent(eventType = RAGEventType.PIPELINE_CREATED)

        fun pipelineDestroyed() = RAGEvent(eventType = RAGEventType.PIPELINE_DESTROYED)

        fun error(message: String) = RAGEvent(
            eventType = RAGEventType.ERROR,
            errorMessage = message,
            destination = EventDestination.ALL,
        )
    }
}
