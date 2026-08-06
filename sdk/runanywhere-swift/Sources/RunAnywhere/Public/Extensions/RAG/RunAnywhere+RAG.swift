//
//  RunAnywhere+RAG.swift
//  RunAnywhere SDK
//
//  Deprecated flat RAG verbs, all driving the single shared pipeline they
//  always drove. The v3 surface is `RunAnywhere.rag.open(...)`, which hands
//  back an independent `RagSession`.
//

import Foundation

public extension RunAnywhere {

    // MARK: - Pipeline lifecycle

    /// Build a RAG configuration from registry models via lifecycle resolution.
    @available(*, deprecated, renamed: "rag.open(embeddingModel:llmModel:config:)")
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

    /// Create the shared RAG pipeline from registry models.
    @available(*, deprecated, renamed: "rag.open(embeddingModel:llmModel:config:)")
    static func ragCreatePipeline(
        embeddingModel: RAModelInfo,
        llmModel: RAModelInfo,
        baseConfiguration: RARAGConfiguration = .defaults()
    ) async throws {
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
        let config = try baseConfiguration.resolvingLifecycleArtifacts(embedding: embedding, llm: llm)
        try await ragCreatePipelineInternal(config: config)
    }

    /// Create the shared RAG pipeline with the given configuration.
    @available(*, deprecated, renamed: "rag.open(embeddingModel:llmModel:config:)")
    static func ragCreatePipeline(config: RARAGConfiguration) async throws {
        try await ragCreatePipelineInternal(config: config)
    }

    internal static func ragCreatePipelineInternal(config: RARAGConfiguration) async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        try await CppBridge.RAG.shared.replacePipeline(config)
    }

    /// Destroy the shared RAG pipeline and release its resources.
    @available(*, deprecated, renamed: "RagSession.close()")
    static func ragDestroyPipeline() async {
        await CppBridge.RAG.shared.destroy()
    }

    // MARK: - Document ingestion

    /// Ingest one document into the shared pipeline.
    @discardableResult
    @available(*, deprecated, renamed: "RagSession.ingest(document:)")
    static func ragIngest(_ document: RARAGDocument) async throws -> RARAGStatistics {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.RAG.shared.ingest(document)
    }

    /// Ingest several documents into the shared pipeline in one batch.
    @available(*, deprecated, renamed: "RagSession.ingest(documents:)")
    static func ragAddDocumentsBatch(documents: [RARAGDocument]) async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        guard !documents.isEmpty else { return }
        try await ensureServicesReady()
        try await CppBridge.RAG.shared.ingest(documents)
    }

    /// Number of indexed chunks in the shared pipeline, or 0 when unavailable.
    @available(*, deprecated, renamed: "RagSession.stats()")
    static func ragGetDocumentCount() async -> Int {
        if let stats = try? await CppBridge.RAG.shared.statistics() {
            return Int(stats.indexedChunks)
        }
        return 0
    }

    /// Statistics for the shared pipeline.
    @available(*, deprecated, renamed: "RagSession.stats()")
    static func ragGetStatistics() async throws -> RARAGStatistics {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        return try await CppBridge.RAG.shared.statistics()
    }

    /// Clear all ingested documents from the shared pipeline.
    @available(*, deprecated, renamed: "RagSession.clear()")
    static func ragClearDocuments() async throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        _ = try await CppBridge.RAG.shared.clearDocuments()
    }

    /// Current number of indexed chunks in the shared pipeline.
    @available(*, deprecated, renamed: "RagSession.stats()")
    static var ragDocumentCount: Int {
        get async {
            if let stats = try? await CppBridge.RAG.shared.statistics() {
                return Int(stats.indexedChunks)
            }
            return 0
        }
    }

    // MARK: - Query

    /// Query the shared pipeline with a natural-language question.
    @available(*, deprecated, renamed: "RagSession.query(question:options:)")
    static func ragQuery(question: String, options: RARAGQueryOptions? = nil) async throws -> RARAGResult {
        var queryOptions = options ?? RARAGQueryOptions.defaults(question: question)
        if queryOptions.query.isEmpty {
            queryOptions.query = question
        }
        return try await ragQueryInternal(queryOptions)
    }

    /// Query the shared pipeline through the generated-proto ABI.
    @available(*, deprecated, renamed: "RagSession.query(question:options:)")
    static func ragQuery(_ options: RARAGQueryOptions) async throws -> RARAGResult {
        try await ragQueryInternal(options)
    }

    internal static func ragQueryInternal(_ options: RARAGQueryOptions) async throws -> RARAGResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.RAG.shared.runQuery(options)
    }

    /// Streaming query against the shared pipeline.
    @available(*, deprecated, renamed: "RagSession.queryStream(question:options:)")
    static func ragQueryStream(
        question: String,
        options: RARAGQueryOptions? = nil
    ) async throws -> AsyncStream<RARAGStreamEvent> {
        var queryOptions = options ?? RARAGQueryOptions.defaults(question: question)
        if queryOptions.query.isEmpty {
            queryOptions.query = question
        }
        return try await ragQueryStreamInternal(queryOptions)
    }

    /// Streaming query against the shared pipeline through the generated-proto ABI.
    @available(*, deprecated, renamed: "RagSession.queryStream(question:options:)")
    static func ragQueryStream(_ options: RARAGQueryOptions) async throws -> AsyncStream<RARAGStreamEvent> {
        try await ragQueryStreamInternal(options)
    }

    internal static func ragQueryStreamInternal(
        _ options: RARAGQueryOptions
    ) async throws -> AsyncStream<RARAGStreamEvent> {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        return try await CppBridge.RAG.shared.runQueryStream(options)
    }

    /// Cancel the query running on the shared pipeline.
    @available(*, deprecated, message: "Cancel the Task consuming RagSession.queryStream instead")
    static func ragCancelQuery() async {
        await CppBridge.RAG.shared.cancelActiveQuery()
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
        let result = await performLoad(request)
        guard !result.hasError else {
            let message = result.error.message
            let code: RAErrorCode = message.contains(NativeProtoABI.unavailableMessage)
                ? .featureNotAvailable
                : .modelLoadFailed
            throw SDKException(code: code, message: "\(errorLabel) model '\(model.id)': \(message)", category: .component)
        }
        return result
    }
}
