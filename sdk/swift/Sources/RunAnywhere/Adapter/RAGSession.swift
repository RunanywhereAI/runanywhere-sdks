// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RAG (retrieval-augmented generation) session — wraps the C++ RAG
// solution from `solutions/rag/`. The current implementation is a
// pure-Swift coordinator over EmbedSession + LLMSession + an in-memory
// HNSW-style index; the C ABI exposes the engine pieces but no
// `ra_rag_*` namespace today (RAG lives at the solution layer).

import Foundation
import CRACommonsCore

public struct RAGConfiguration: Sendable {
    public var embeddingModelId: String
    public var llmModelId: String
    public var topK: Int
    public var similarityThreshold: Float
    public var maxContextTokens: Int
    public var chunkSize: Int
    public var chunkOverlap: Int

    public init(embeddingModelId: String,
                llmModelId: String,
                topK: Int = 6,
                similarityThreshold: Float = 0.5,
                maxContextTokens: Int = 2048,
                chunkSize: Int = 512,
                chunkOverlap: Int = 64) {
        self.embeddingModelId = embeddingModelId
        self.llmModelId = llmModelId
        self.topK = topK
        self.similarityThreshold = similarityThreshold
        self.maxContextTokens = maxContextTokens
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
    }
}

public struct RAGResult: Sendable {
    public let answer: String
    public let citations: [String]
    public init(answer: String, citations: [String] = []) {
        self.answer = answer; self.citations = citations
    }
}

@MainActor
internal final class RAGPipeline {
    let config: RAGConfiguration
    var corpus: [(text: String, vec: [Float])] = []
    let embed: EmbedSession
    let chat: ChatSession

    init(config: RAGConfiguration,
         embedModelPath: String, llmModelPath: String) throws {
        self.config = config
        self.embed = try EmbedSession(modelId: config.embeddingModelId,
                                       modelPath: embedModelPath)
        self.chat = try ChatSession(modelId: config.llmModelId,
                                     modelPath: llmModelPath,
                                     systemPrompt: nil)
    }

    func ingest(_ text: String) throws {
        // Naive char-window chunking; production RAG would use a sentence
        // splitter (solutions/rag/SentenceSplitter handles this).
        let chunkSize = max(64, config.chunkSize)
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[i..<j])
            let vec = try embed.embed(chunk)
            corpus.append((text: chunk, vec: vec))
            i = j
        }
    }

    func query(_ question: String) async throws -> RAGResult {
        let qvec = try embed.embed(question)
        let scored = corpus.map { ($0.text, cosine($0.vec, qvec)) }
                            .sorted { $0.1 > $1.1 }
                            .prefix(config.topK)
                            .filter { $0.1 >= config.similarityThreshold }
        let context = scored.map { "- \($0.0)" }.joined(separator: "\n")
        let messages: [ChatSession.Message] = [
            .system("Use the following context to answer concisely.\n\n\(context)"),
            .user(question)
        ]
        let answer = try await chat.generateText(messages: messages)
        return RAGResult(answer: answer, citations: scored.map { $0.0 })
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}

@MainActor
internal enum RAGRegistry {
    static var current: RAGPipeline?
}

// MARK: - RunAnywhere.* RAG entry points

@MainActor
public extension RunAnywhere {

    static func ragCreatePipeline(config: RAGConfiguration) throws {
        guard let embedInfo = ModelCatalog.model(id: config.embeddingModelId) else {
            throw RunAnywhereError.invalidArgument("embed model not registered: \(config.embeddingModelId)")
        }
        guard let llmInfo = ModelCatalog.model(id: config.llmModelId) else {
            throw RunAnywhereError.invalidArgument("llm model not registered: \(config.llmModelId)")
        }
        let pipeline = try RAGPipeline(config: config,
                                         embedModelPath: embedInfo.localPath ?? "",
                                         llmModelPath: llmInfo.localPath ?? "")
        RAGRegistry.current = pipeline
    }

    static func ragIngest(text: String) throws {
        guard let pipeline = RAGRegistry.current else {
            throw RunAnywhereError.backendUnavailable("call ragCreatePipeline first")
        }
        try pipeline.ingest(text)
    }

    static func ragQuery(question: String) async throws -> RAGResult {
        guard let pipeline = RAGRegistry.current else {
            throw RunAnywhereError.backendUnavailable("call ragCreatePipeline first")
        }
        return try await pipeline.query(question)
    }

    static func ragDestroyPipeline() { RAGRegistry.current = nil }
}
