//
//  RAGEvents.swift
//  RunAnywhere SDK
//
//  RAG lifecycle events published to EventBus.
//  Consumers can subscribe via EventBus.shared.events(for: .rag).
//

import Foundation

// MARK: - RAG Event

/// An SDK event emitted during RAG pipeline operations.
///
/// Subscribe to all RAG events:
/// ```swift
/// RunAnywhere.events.events(for: .rag)
///     .sink { event in print(event.type, event.properties) }
/// ```
public struct RAGEvent: SDKEvent {

    // MARK: - SDKEvent

    public let id: String
    public let type: String
    public let category: EventCategory
    public let timestamp: Date
    public let sessionId: String?
    public let destination: EventDestination
    public let properties: [String: String]

    // MARK: - Init

    private init(
        type: String,
        properties: [String: String] = [:],
        destination: EventDestination = .publicOnly
    ) {
        self.id = UUID().uuidString
        self.type = type
        self.category = .rag
        self.timestamp = Date()
        self.sessionId = nil
        self.destination = destination
        self.properties = properties
    }

    // MARK: - Factory Methods

    /// Emitted when document ingestion begins
    public static func ingestionStarted(documentLength: Int) -> RAGEvent {
        RAGEvent(
            type: "rag.ingestion.started",
            properties: ["documentLength": String(documentLength)]
        )
    }

    /// Emitted when document ingestion completes successfully
    public static func ingestionComplete(chunkCount: Int, durationMs: Double) -> RAGEvent {
        RAGEvent(
            type: "rag.ingestion.complete",
            properties: [
                "chunkCount": String(chunkCount),
                "durationMs": String(format: "%.1f", durationMs)
            ]
        )
    }

    /// Emitted when a RAG query is submitted
    public static func queryStarted(question: String) -> RAGEvent {
        RAGEvent(
            type: "rag.query.started",
            properties: ["questionLength": String(question.count)]
        )
    }

    /// Emitted when a RAG query returns a result
    public static func queryComplete(result: RAGResult) -> RAGEvent {
        RAGEvent(
            type: "rag.query.complete",
            properties: [
                "answerLength": String(result.answer.count),
                "chunksRetrieved": String(result.retrievedChunks.count),
                "retrievalTimeMs": String(format: "%.1f", result.retrievalTimeMs),
                "generationTimeMs": String(format: "%.1f", result.generationTimeMs),
                "totalTimeMs": String(format: "%.1f", result.totalTimeMs)
            ]
        )
    }

    /// Emitted when the RAG pipeline is created
    public static func pipelineCreated() -> RAGEvent {
        RAGEvent(type: "rag.pipeline.created")
    }

    /// Emitted when the RAG pipeline is destroyed
    public static func pipelineDestroyed() -> RAGEvent {
        RAGEvent(type: "rag.pipeline.destroyed")
    }

    /// Emitted when a RAG operation encounters an error
    public static func error(message: String) -> RAGEvent {
        RAGEvent(
            type: "rag.error",
            properties: ["message": message],
            destination: .all
        )
    }
}
