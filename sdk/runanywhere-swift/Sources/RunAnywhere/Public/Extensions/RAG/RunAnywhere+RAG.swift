//
//  RunAnywhere+RAG.swift
//  RunAnywhere SDK
//
//  Public API for Retrieval-Augmented Generation (RAG) operations.
//  Delegates all pipeline work to CppBridge.RAG, publishes events to EventBus.
//

import Foundation

// MARK: - RAG Operations

public extension RunAnywhere {

    // MARK: - Pipeline Lifecycle

    /// Build a generated RAG configuration from registry models by using
    /// commons lifecycle resolution for primary and sidecar artifacts.
    static func ragResolvedConfiguration(
        embeddingModel: RAModelInfo,
        llmModel: RAModelInfo,
        baseConfiguration: RARAGConfiguration = .defaults()
    ) async throws -> RARAGConfiguration {
        let embedding = try await loadRAGArtifactModel(
            embeddingModel,
            fallbackCategory: .embedding,
            errorLabel: "Embedding"
        )
        let llm = try await loadRAGArtifactModel(
            llmModel,
            fallbackCategory: .language,
            errorLabel: "LLM"
        )
        return try baseConfiguration.resolvingLifecycleArtifacts(embedding: embedding, llm: llm)
    }

    /// Create the RAG pipeline from registry models. Model artifact layout is
    /// resolved by commons lifecycle rather than by Swift file-name heuristics.
    static func ragCreatePipeline(
        embeddingModel: RAModelInfo,
        llmModel: RAModelInfo,
        baseConfiguration: RARAGConfiguration = .defaults()
    ) async throws {
        let config = try await ragResolvedConfiguration(
            embeddingModel: embeddingModel,
            llmModel: llmModel,
            baseConfiguration: baseConfiguration
        )
        try await ragCreatePipeline(config: config)
    }

    /// Create the RAG pipeline with the given configuration.
    ///
    /// Must be called before ingesting documents or running queries.
    ///
    /// - Parameter config: RAG pipeline configuration (model paths, tuning parameters)
    /// - Throws: `SDKException` if the SDK is not initialized or pipeline creation fails
    static func ragCreatePipeline(config: RARAGConfiguration) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        try await CppBridge.RAG.shared.replacePipeline(config)
    }

    /// Destroy the RAG pipeline and release all resources.
    static func ragDestroyPipeline() async {
        await CppBridge.RAG.shared.destroy()
    }

    // MARK: - Document Ingestion

    /// Ingest a generated-proto document through the C++ RAG ABI.
    @discardableResult
    static func ragIngest(_ document: RARAGDocument) async throws -> RARAGStatistics {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        return try await CppBridge.RAG.shared.ingest(document)
    }

    /// Ingest multiple text documents into the RAG pipeline in a single batch.
    ///
    /// Equivalent to calling `ragIngest` for each document but more efficient because
    /// the C++ layer can embed all documents in a single pass.
    ///
    /// - Parameter documents: Array of `RARAGDocument` values.
    /// - Throws: `SDKException` if the SDK or pipeline is not ready, or ingestion fails.
    static func ragAddDocumentsBatch(documents: [RARAGDocument]) async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        guard !documents.isEmpty else { return }
        try await ensureServicesReady()

        try await CppBridge.RAG.shared.ingest(documents)
    }

    /// Get the number of indexed document chunks in the pipeline as a function call.
    ///
    /// This is the canonical `ragGetDocumentCount()` form required by the spec (§9).
    /// The computed var `ragDocumentCount` is retained as a convenience accessor.
    ///
    /// - Returns: Number of indexed chunks in the pipeline, or 0 if not initialized.
    static func ragGetDocumentCount() async -> Int {
        if let stats = try? await CppBridge.RAG.shared.statistics() {
            return Int(stats.indexedChunks)
        }
        return 0
    }

    /// Get RAG pipeline statistics.
    ///
    /// Returns an `RARAGStatistics` proto with `indexedDocuments`, `indexedChunks`,
    /// `totalTokensIndexed`, `lastUpdatedMs`, and `indexPath`.
    ///
    /// - Throws: `SDKException` if the SDK is not initialized or the pipeline is not ready.
    static func ragGetStatistics() async throws -> RARAGStatistics {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        return try await CppBridge.RAG.shared.statistics()
    }

    /// Clear all previously ingested documents from the pipeline.
    ///
    /// - Throws: `SDKException` if the SDK is not initialized or the pipeline is not ready
    static func ragClearDocuments() async throws {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        _ = try await CppBridge.RAG.shared.clearDocuments()
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
    /// - Returns: A `RARAGResult` containing the generated answer and retrieved chunks
    /// - Throws: `SDKException` if the SDK or pipeline is not ready, or the query fails
    static func ragQuery(question: String, options: RARAGQueryOptions? = nil) async throws -> RARAGResult {
        var queryOptions = options ?? RARAGQueryOptions.defaults(question: question)
        if queryOptions.question.isEmpty {
            queryOptions.question = question
        }
        return try await ragQuery(queryOptions)
    }

    /// Query through the generated-proto C++ RAG ABI.
    static func ragQuery(_ options: RARAGQueryOptions) async throws -> RARAGResult {
        guard isInitialized else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()

        return try await CppBridge.RAG.shared.runQuery(options)
    }
}

private extension RunAnywhere {
    static func loadRAGArtifactModel(
        _ model: RAModelInfo,
        fallbackCategory: RAModelCategory,
        errorLabel: String
    ) async throws -> RAModelLoadResult {
        guard !model.isLoRAAdapterArtifact else {
            let message = "\(errorLabel) model '\(model.id)' is a LoRA adapter artifact. " +
                "Select a compatible base LLM for RAG and apply the adapter through RunAnywhere.lora."
            throw SDKException(
                code: .invalidArgument,
                message: message,
                category: .validation
            )
        }

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = model.category == .unspecified ? fallbackCategory : model.category
        if model.framework != .unspecified {
            request.framework = model.framework
        }
        let result = await loadModel(request)
        guard result.success else {
            let message = result.errorMessage.isEmpty
                ? "\(errorLabel) model lifecycle artifact resolution failed"
                : result.errorMessage
            let code: RAErrorCode = message.contains(NativeProtoABI.unavailableMessage)
                ? .featureNotAvailable
                : .modelLoadFailed
            throw SDKException(code: code, message: "\(errorLabel) model '\(model.id)': \(message)", category: .component)
        }
        return result
    }
}
