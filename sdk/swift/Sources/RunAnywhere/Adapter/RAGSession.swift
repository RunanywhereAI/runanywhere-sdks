// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RAG (retrieval-augmented generation) session — wraps the core
// `ra_rag_*` C ABI (chunker + in-memory vector store) + EmbedSession
// + ChatSession. Vector storage and chunking happen in C++ core for
// consistency across SDKs.

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
    let embed: EmbedSession
    let chat: ChatSession
    var store: OpaquePointer?  // ra_rag_vector_store_t
    var chunkTexts: [String] = []  // Kept Swift-side to return citations

    init(config: RAGConfiguration,
         embedModelPath: String, llmModelPath: String,
         embeddingDim: Int32 = 384) throws {
        self.config = config
        self.embed = try EmbedSession(modelId: config.embeddingModelId,
                                       modelPath: embedModelPath)
        self.chat = try ChatSession(modelId: config.llmModelId,
                                     modelPath: llmModelPath,
                                     systemPrompt: nil)
        var s: OpaquePointer?
        let rc = ra_rag_store_create(embeddingDim, &s)
        guard rc == RA_OK, s != nil else {
            throw RunAnywhereError.internalError("ra_rag_store_create failed: \(rc)")
        }
        self.store = s
    }

    deinit {
        // MainActor-isolated cleanup can't run in deinit; callers must
        // invoke `destroy()` to release the native vector store.
    }

    func destroy() {
        if let s = store { ra_rag_store_destroy(s) }
        store = nil
        chunkTexts.removeAll()
    }

    func ingest(_ text: String) throws {
        guard let store = store else {
            throw RunAnywhereError.backendUnavailable("RAG store destroyed")
        }
        // Use the core chunker so every SDK uses identical chunking logic.
        var chunks: UnsafeMutablePointer<ra_rag_chunk_t>?
        var count: Int32 = 0
        let rc = text.withCString { cstr in
            ra_rag_chunk_text(cstr,
                                Int32(config.chunkSize),
                                Int32(config.chunkOverlap),
                                &chunks, &count)
        }
        guard rc == RA_OK else {
            throw RunAnywhereError.internalError("ra_rag_chunk_text failed: \(rc)")
        }
        defer { if let c = chunks { ra_rag_chunks_free(c, count) } }

        for idx in 0..<Int(count) {
            let chunk = chunks![idx]
            let chunkText = String(cString: chunk.text)
            let vec = try embed.embed(chunkText)
            let rowId = "chunk-\(chunkTexts.count)"
            let rc2 = rowId.withCString { id in
                "".withCString { meta in
                    vec.withUnsafeBufferPointer { ptr in
                        ra_rag_store_add(store, id, meta,
                                           ptr.baseAddress,
                                           Int32(vec.count))
                    }
                }
            }
            guard rc2 == RA_OK else {
                throw RunAnywhereError.internalError("ra_rag_store_add failed: \(rc2)")
            }
            chunkTexts.append(chunkText)
        }
    }

    func query(_ question: String) async throws -> RAGResult {
        guard let store = store else {
            throw RunAnywhereError.backendUnavailable("RAG store destroyed")
        }
        let qvec = try embed.embed(question)
        var ids: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var metas: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var scores: UnsafeMutablePointer<Float>?
        var count: Int32 = 0
        let rc = qvec.withUnsafeBufferPointer { ptr in
            ra_rag_store_search(store, ptr.baseAddress,
                                  Int32(qvec.count),
                                  Int32(config.topK),
                                  &ids, &metas, &scores, &count)
        }
        guard rc == RA_OK else {
            throw RunAnywhereError.internalError("ra_rag_store_search failed: \(rc)")
        }
        defer {
            if let i = ids { ra_rag_strings_free(i, count) }
            if let m = metas { ra_rag_strings_free(m, count) }
            if let s = scores { ra_rag_floats_free(s) }
        }

        var hits: [(String, Float)] = []
        for i in 0..<Int(count) {
            let idPtr = ids![i]
            let score = scores![i]
            guard score >= config.similarityThreshold, let idRaw = idPtr else { continue }
            let idStr = String(cString: idRaw)
            if let idx = Int(idStr.dropFirst("chunk-".count)),
               idx >= 0, idx < chunkTexts.count {
                hits.append((chunkTexts[idx], score))
            }
        }

        let context = hits.map { "- \($0.0)" }.joined(separator: "\n")
        let messages: [ChatSession.Message] = [
            .system("Use the following context to answer concisely.\n\n\(context)"),
            .user(question)
        ]
        let answer = try await chat.generateText(messages: messages)
        return RAGResult(answer: answer, citations: hits.map { $0.0 })
    }
}

@MainActor
internal enum RAGRegistry {
    static var current: RAGPipeline?
}

// MARK: - RunAnywhere.* RAG entry points

@MainActor
public extension RunAnywhere {

    static func ragCreatePipeline(config: RAGConfiguration) async throws {
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

    static func ragIngest(text: String) async throws {
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

    static func ragDestroyPipeline() async {
        RAGRegistry.current?.destroy()
        RAGRegistry.current = nil
    }
}
