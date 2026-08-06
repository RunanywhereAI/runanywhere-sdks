//
//  RagSession.swift
//  RunAnywhere SDK
//
//  A retrieval-augmented-generation session. Each session owns its own native
//  handle, so two sessions with different corpora can exist at once.
//

import CRACommons
import Foundation

/// Carries the opaque native session pointer across a `@Sendable` boundary; the
/// handle is only ever read and handed straight back to the C ABI.
private struct RagSessionHandleRef: @unchecked Sendable {
    let handle: rac_handle_t
}

/// An open RAG corpus you can ingest into, search, and query.
public actor RagSession {

    private let handle: rac_handle_t
    private let llmModelId: String
    private let defaultTopK: Int
    private var isClosed = false

    internal init(handle: rac_handle_t, llmModelId: String, defaultTopK: Int) {
        self.handle = handle
        self.llmModelId = llmModelId
        self.defaultTopK = defaultTopK
    }

    /// Add one document to the index.
    ///
    /// - Throws: `SDKException` when the session is closed or embedding fails.
    public func ingest(document: RagDocument) async throws {
        try requireOpen()
        _ = try CppBridge.RAG.shared.ingest(handle: handle, document.toProto())
    }

    /// Add several documents to the index.
    ///
    /// - Throws: `SDKException` when the session is closed or embedding fails.
    public func ingest(documents: [RagDocument]) async throws {
        try requireOpen()
        for document in documents {
            _ = try CppBridge.RAG.shared.ingest(handle: handle, document.toProto())
        }
    }

    /// Retrieve the closest chunks to `query` without generating an answer.
    ///
    /// Uses the commons retrieval-only ABI (`rac_rag_search_proto`); no LLM
    /// generation is started.
    ///
    /// - Throws: `SDKException` when the session is closed, the native search
    ///   symbol is unavailable, or retrieval fails.
    public func search(query: String, topK: Int? = nil) async throws -> [Match] {
        try requireOpen()
        var request = RARAGSearchRequest()
        request.query = query
        var retrieval = RARAGRetrievalOptions()
        retrieval.topK = Int32(topK ?? defaultTopK)
        request.retrieval = retrieval
        let response = try CppBridge.RAG.shared.search(handle: handle, request)
        try RagSession.throwIfFailed(response)
        return response.chunks.map(Match.init(proto:))
    }

    /// Answer `question` from the indexed corpus.
    ///
    /// - Throws: `SDKException` when the session has no LLM, is closed, or the
    ///   query fails.
    public func query(question: String, options: RagQueryOptions? = nil) async throws -> RagResult {
        try requireOpen()
        try requireGenerationModel()
        let result = try CppBridge.RAG.shared.query(
            handle: handle,
            queryOptions(question: question, options: options)
        )
        try RagSession.throwIfFailed(result)
        return RagResult(proto: result, model: llmModelId)
    }

    /// Deprecated: forwards `options` into `RagQueryOptions(generation:)`.
    @available(*, deprecated, message: "Use query(question:options: RagQueryOptions?)")
    public func query(question: String, options: LlmOptions?) async throws -> RagResult {
        try await query(question: question, options: RagQueryOptions(generation: options))
    }

    /// Answer `question`, streaming retrieval and tokens as they arrive.
    ///
    /// - Throws: `SDKException` from this call when the session has no LLM or is
    ///   closed, and into the returned stream when the query fails.
    public func queryStream(
        question: String,
        options: RagQueryOptions? = nil
    ) async throws -> AsyncThrowingStream<RagEvent, Error> {
        try requireOpen()
        try requireGenerationModel()
        let sessionHandle = RagSessionHandleRef(handle: handle)
        let events = try CppBridge.RAG.shared.runQueryStream(
            handle: handle,
            queryOptions(question: question, options: options)
        )
        let model = llmModelId

        return AsyncThrowingStream { continuation in
            let task = Task {
                var retrievedProtos: [RARAGSearchResult] = []
                var answer = ""
                var sawCompletion = false
                for await event in events {
                    if Task.isCancelled { break }
                    // RAGStreamEventKind collapsed to unspecified/token/
                    // completed/error (idl/rag.proto): the RETRIEVAL_STARTED/
                    // CHUNK_RETRIEVED/CONTEXT_READY progress cases were
                    // deleted outright, so retrieved chunks no longer stream
                    // incrementally. They arrive only on the terminal
                    // `.completed` event's `result.retrievedChunks`; this
                    // synthesizes the `.retrieved` event from that payload
                    // immediately before `.completed`, the closest
                    // equivalent the surviving wire shape supports.
                    switch event.kind {
                    case .token:
                        if !event.token.isEmpty {
                            answer += event.token
                            continuation.yield(.token(text: event.token, kind: .text))
                        }
                    case .completed:
                        let result = event.hasResult ? event.result : RARAGResult()
                        retrievedProtos = result.retrievedChunks
                        continuation.yield(.retrieved(retrievedProtos.map(Match.init(proto:))))
                        continuation.yield(.completed(RagResult(proto: result, model: model)))
                        sawCompletion = true
                    case .error:
                        continuation.finish(throwing: SDKException(proto: event.error))
                        return
                    default:
                        break
                    }
                }

                // End in `completed` or throw, never a silent finish.
                if !sawCompletion, !Task.isCancelled {
                    guard !answer.isEmpty else {
                        continuation.finish(throwing: SDKException(
                            code: .processingFailed,
                            message: "RAG query ended before producing an answer",
                            category: .component
                        ))
                        return
                    }
                    var synthesized = RARAGResult()
                    synthesized.answer = answer
                    synthesized.retrievedChunks = retrievedProtos
                    continuation.yield(.completed(RagResult(proto: synthesized, model: model)))
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable termination in
                task.cancel()
                if case .cancelled = termination {
                    Task { CppBridge.RAG.shared.cancelActiveQuery(handle: sessionHandle.handle) }
                }
            }
        }
    }

    /// Deprecated: forwards `options` into `RagQueryOptions(generation:)`.
    @available(*, deprecated, message: "Use queryStream(question:options: RagQueryOptions?)")
    public func queryStream(
        question: String,
        options: LlmOptions?
    ) async throws -> AsyncThrowingStream<RagEvent, Error> {
        try await queryStream(question: question, options: RagQueryOptions(generation: options))
    }

    /// Report how much this session currently holds.
    ///
    /// - Throws: `SDKException` when the session is closed.
    public func stats() async throws -> RagStats {
        try requireOpen()
        return RagStats(proto: try CppBridge.RAG.shared.statsProto(handle: handle))
    }

    /// Drop every ingested document from the index.
    ///
    /// - Throws: `SDKException` when the session is closed or the index cannot be cleared.
    public func clear() async throws {
        try requireOpen()
        _ = try CppBridge.RAG.shared.clearProto(handle: handle)
    }

    /// Release the session and its native index.
    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        CppBridge.RAG.shared.destroySession(handle: handle)
    }

    // MARK: - Private

    private func queryOptions(question: String, options: RagQueryOptions?) -> RARAGQueryOptions {
        var queryOptions = RARAGQueryOptions.defaults(question: question)
        // retrievalTopK/similarityThreshold moved onto the nested
        // `RAGRetrievalOptions retrieval` sub-message (idl/rag.proto).
        var retrieval = RARAGRetrievalOptions()
        retrieval.topK = Int32(options?.retrievalTopK ?? defaultTopK)
        if let similarityThreshold = options?.similarityThreshold {
            retrieval.scoreThreshold = similarityThreshold
        }
        queryOptions.retrieval = retrieval
        if let generation = options?.generation {
            queryOptions.generation = generation.toProto()
        }
        return queryOptions
    }

    private func requireOpen() throws {
        guard !isClosed else {
            throw SDKException(
                code: .invalidState,
                message: "RAG session is closed",
                category: .component
            )
        }
    }

    private func requireGenerationModel() throws {
        guard !llmModelId.isEmpty else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "This RAG session is retrieval-only; open it with an llmModel to generate answers",
                category: .validation
            )
        }
    }

    private static func throwIfFailed(_ result: RARAGResult) throws {
        guard result.hasError else { return }
        throw SDKException(proto: result.error)
    }

    private static func throwIfFailed(_ response: RARAGSearchResponse) throws {
        guard response.hasError else { return }
        throw SDKException(proto: response.error)
    }
}
