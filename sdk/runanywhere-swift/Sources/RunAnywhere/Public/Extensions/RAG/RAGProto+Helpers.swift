//
//  RAGProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical RAG proto types.
//

import Foundation

// MARK: - RARAGConfiguration

extension RARAGConfiguration {
    public static func defaults(
        embeddingModelPath: String = "",
        llmModelPath: String = ""
    ) -> RARAGConfiguration {
        var c = RARAGConfiguration()
        c.embeddingModelPath = embeddingModelPath
        c.llmModelPath = llmModelPath
        c.embeddingDimension = 384
        c.topK = 5
        c.similarityThreshold = 0.7
        c.chunkSize = 512
        c.chunkOverlap = 64
        return c
    }

    public func validate() throws {
        guard topK > 0 else {
            throw SDKException.validationFailed("topK must be > 0 (got \(topK))")
        }
        guard similarityThreshold >= 0 && similarityThreshold <= 1.0 else {
            throw SDKException.validationFailed(
                "Similarity threshold must be in 0...1.0 (got \(similarityThreshold))"
            )
        }
        guard chunkSize > 0 else {
            throw SDKException.validationFailed("Chunk size must be > 0")
        }
        guard chunkOverlap >= 0 && chunkOverlap < chunkSize else {
            throw SDKException.validationFailed(
                "Chunk overlap must be >= 0 and < chunkSize (got \(chunkOverlap) vs \(chunkSize))"
            )
        }
    }

    public func resolvingLifecycleArtifacts(
        embedding: RAModelLoadResult,
        llm: RAModelLoadResult
    ) throws -> RARAGConfiguration {
        guard let embeddingPath = embedding.lifecyclePrimaryArtifactPath else {
            throw SDKException.rag(
                .modelLoadFailed,
                "Embedding model '\(embedding.modelID)' did not return a lifecycle-resolved primary artifact"
            )
        }
        guard let llmPath = llm.lifecyclePrimaryArtifactPath else {
            throw SDKException.rag(
                .modelLoadFailed,
                "LLM model '\(llm.modelID)' did not return a lifecycle-resolved primary artifact"
            )
        }

        var resolved = self
        resolved.embeddingModelPath = embeddingPath
        resolved.llmModelPath = llmPath
        if let vocabularyPath = embedding.resolvedVocabularyPath {
            resolved.embeddingConfigJson = try resolved.embeddingConfigJson.mergingRAGConfig(
                key: "vocab_path",
                value: vocabularyPath
            )
        }
        return resolved
    }
}

// MARK: - RARAGDocument

extension RARAGDocument {
    public init(text: String, metadataJSON: String? = nil) {
        self.init()
        self.text = text
        if let metadataJSON {
            self.metadataJson = metadataJSON
        }
    }
}

// MARK: - RARAGQueryOptions

extension RARAGQueryOptions {
    public static func defaults(question: String) -> RARAGQueryOptions {
        var o = RARAGQueryOptions()
        o.question = question
        o.maxTokens = 512
        o.temperature = 0.7
        o.topP = 1.0
        o.topK = 0
        return o
    }
}

// MARK: - RARAGResult

extension RARAGResult {
    public var totalTime: TimeInterval { TimeInterval(totalTimeMs) / 1000.0 }
    public var retrievalTime: TimeInterval { TimeInterval(retrievalTimeMs) / 1000.0 }
    public var generationTime: TimeInterval { TimeInterval(generationTimeMs) / 1000.0 }
}

// MARK: - RARAGStatistics

extension RARAGStatistics {
    public var lastUpdated: Date? {
        guard lastUpdatedMs > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUpdatedMs) / 1000.0)
    }
}

private extension String {
    func mergingRAGConfig(key: String, value: String) throws -> String {
        var object: [String: Any] = [:]
        if !isEmpty {
            let existing = try JSONSerialization.jsonObject(with: Data(self.utf8)) as? [String: Any]
            guard let existing else {
                throw SDKException.rag(
                    .invalidConfiguration,
                    "RAG embeddingConfigJson must be a JSON object to merge lifecycle artifact metadata"
                )
            }
            object = existing
        }
        object[key] = value
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
