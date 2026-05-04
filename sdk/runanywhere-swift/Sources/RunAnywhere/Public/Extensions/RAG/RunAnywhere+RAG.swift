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
    /// - Throws: `SDKException` if the SDK is not initialized or pipeline creation fails
    static func ragCreatePipeline(config: RAGConfiguration) async throws {
        try await ragCreatePipeline(config: config.toRARAGConfiguration())
    }

    /// Create the RAG pipeline through the generated-proto C++ RAG ABI.
    static func ragCreatePipeline(config: RARAGConfiguration) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        try await CppBridge.RAG.shared.createPipeline(config: config)
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
    /// - Throws: `SDKException` if the SDK or pipeline is not ready, or ingestion fails
    static func ragIngest(text: String, metadataJSON: String? = nil) async throws {
        try await ragIngest(RAGDocument(text: text, metadataJSON: metadataJSON).toRARAGDocument())
    }

    /// Ingest a generated-proto document through the C++ RAG ABI.
    @discardableResult
    static func ragIngest(_ document: RARAGDocument) async throws -> RARAGStatistics {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        EventBus.shared.publish(RAGEvent.ingestionStarted(documentLength: document.text.count))
        let startTime = Date()

        let stats = try await CppBridge.RAG.shared.ingest(document)

        let durationMs = Date().timeIntervalSince(startTime) * 1000
        let chunkCount = Int(stats.indexedChunks)
        EventBus.shared.publish(RAGEvent.ingestionComplete(chunkCount: chunkCount, durationMs: durationMs))
        return stats
    }

    /// Ingest multiple text documents into the RAG pipeline in a single batch.
    ///
    /// Equivalent to calling `ragIngest` for each document but more efficient because
    /// the C++ layer can embed all documents in a single pass.
    ///
    /// - Parameter documents: Array of `RAGDocument` values (each with `text` and optional `metadataJSON`).
    /// - Throws: `SDKException` if the SDK or pipeline is not ready, or ingestion fails.
    static func ragAddDocumentsBatch(documents: [RAGDocument]) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        guard !documents.isEmpty else { return }
        try await ensureServicesReady()

        let totalLength = documents.reduce(0) { $0 + $1.text.count }
        EventBus.shared.publish(RAGEvent.ingestionStarted(documentLength: totalLength))
        let startTime = Date()

        var latestStats = RARAGStatistics()
        for document in documents {
            latestStats = try await CppBridge.RAG.shared.ingest(document.toRARAGDocument())
        }

        let durationMs = Date().timeIntervalSince(startTime) * 1000
        let chunkCount = Int(latestStats.indexedChunks)
        EventBus.shared.publish(RAGEvent.ingestionComplete(chunkCount: chunkCount, durationMs: durationMs))
    }

    /// Get the number of indexed document chunks in the pipeline as a function call.
    ///
    /// This is the canonical `ragGetDocumentCount()` form required by the spec (§9).
    /// The computed var `ragDocumentCount` is retained as a convenience accessor.
    ///
    /// - Returns: Number of indexed chunks in the pipeline, or 0 if not initialized.
    static func ragGetDocumentCount() async -> Int {
        if let stats = try? await CppBridge.RAG.shared.statsProto() {
            return Int(stats.indexedChunks)
        }
        return await CppBridge.RAG.shared.documentCount
    }

    /// Get RAG pipeline statistics.
    ///
    /// Returns an `RARAGStatistics` proto with `indexedDocuments`, `indexedChunks`,
    /// `totalTokensIndexed`, `lastUpdatedMs`, and `indexPath`.
    ///
    /// - Throws: `SDKException` if the SDK is not initialized or the pipeline is not ready.
    static func ragGetStatistics() async throws -> RARAGStatistics {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        return try await CppBridge.RAG.shared.statsProto()
    }

    /// Clear all previously ingested documents from the pipeline.
    ///
    /// - Throws: `SDKException` if the SDK is not initialized or the pipeline is not ready
    static func ragClearDocuments() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        _ = try await CppBridge.RAG.shared.clearProto()
    }

    /// The current number of indexed document chunks in the pipeline.
    static var ragDocumentCount: Int {
        get async {
            await ragGetDocumentCount()
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
    /// - Throws: `SDKException` if the SDK or pipeline is not ready, or the query fails
    static func ragQuery(question: String, options: RAGQueryOptions? = nil) async throws -> RAGResult {
        let queryOptions = options ?? RAGQueryOptions(question: question)
        let result = try await ragQuery(queryOptions.toRARAGQueryOptions())
        return RAGResult(from: result)
    }

    /// Query through the generated-proto C++ RAG ABI.
    static func ragQuery(_ options: RARAGQueryOptions) async throws -> RARAGResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        EventBus.shared.publish(RAGEvent.queryStarted(question: options.question))

        let result = try await CppBridge.RAG.shared.query(options)

        EventBus.shared.publish(RAGEvent.queryComplete(result: RAGResult(from: result)))
        return result
    }
}
