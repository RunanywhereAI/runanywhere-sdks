//
//  RunAnywhere+RAG.swift
//  RunAnywhere SDK
//
//  Public API for Retrieval-Augmented Generation (RAG) operations.
//  Delegates all pipeline work to CppBridge.RAG, publishes events to EventBus.
//

import CRACommons
import Foundation

// MARK: - RAG Operations

public extension RunAnywhere {

    // MARK: - Pipeline Lifecycle

    /// Create the RAG pipeline with the given configuration.
    ///
    /// Must be called before ingesting documents or running queries.
    ///
    /// - Parameter config: RAG pipeline configuration (model paths, tuning parameters)
    /// - Throws: `SDKError` if the SDK is not initialized or pipeline creation fails
    static func ragCreatePipeline(config: RAGConfiguration) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        try await CppBridge.RAG.shared.createPipeline(swiftConfig: config)
        EventBus.shared.publish(RAGEvent.pipelineCreated())
    }

    /// Destroy the RAG pipeline and release all resources.
    static func ragDestroyPipeline() async {
        await CppBridge.RAG.shared.destroy()
        EventBus.shared.publish(RAGEvent.pipelineDestroyed())
    }

    // MARK: - Document Ingestion

    /// Ingest a text document into the RAG pipeline.
    ///
    /// The document is split into overlapping chunks, each chunk is embedded
    /// and indexed for vector search. Large documents may take noticeable time.
    ///
    /// - Parameters:
    ///   - text: Plain text content of the document
    ///   - metadataJSON: Optional JSON string attached to all chunks from this document
    /// - Throws: `SDKError` if the SDK or pipeline is not ready, or ingestion fails
    static func ragIngest(text: String, metadataJSON: String? = nil) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        EventBus.shared.publish(RAGEvent.ingestionStarted(documentLength: text.count))
        let startTime = Date()

        try await CppBridge.RAG.shared.addDocument(text: text, metadataJSON: metadataJSON)

        let durationMs = Date().timeIntervalSince(startTime) * 1000
        let chunkCount = await CppBridge.RAG.shared.documentCount
        EventBus.shared.publish(RAGEvent.ingestionComplete(chunkCount: chunkCount, durationMs: durationMs))
    }

    /// Clear all previously ingested documents from the pipeline.
    ///
    /// - Throws: `SDKError` if the SDK is not initialized or the pipeline is not ready
    static func ragClearDocuments() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.RAG.shared.clearDocuments()
    }

    /// The current number of indexed document chunks in the pipeline.
    static var ragDocumentCount: Int {
        get async {
            await CppBridge.RAG.shared.documentCount
        }
    }

    // MARK: - Query

    /// Query the RAG pipeline with a natural-language question.
    ///
    /// Retrieves the most relevant chunks from the vector index and uses the
    /// on-device LLM to generate a grounded answer.
    ///
    /// - Parameters:
    ///   - question: The user's question
    ///   - options: Optional query parameters (temperature, max tokens, etc.).
    ///              Pass `nil` to use defaults derived from the question.
    /// - Returns: A `RAGResult` containing the generated answer and retrieved chunks
    /// - Throws: `SDKError` if the SDK or pipeline is not ready, or the query fails
    static func ragQuery(question: String, options: RAGQueryOptions? = nil) async throws -> RAGResult {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let queryOptions = options ?? RAGQueryOptions(question: question)
        EventBus.shared.publish(RAGEvent.queryStarted(question: question))

        let result = try await CppBridge.RAG.shared.query(swiftOptions: queryOptions)

        EventBus.shared.publish(RAGEvent.queryComplete(result: result))
        return result
    }
}
