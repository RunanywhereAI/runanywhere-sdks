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
