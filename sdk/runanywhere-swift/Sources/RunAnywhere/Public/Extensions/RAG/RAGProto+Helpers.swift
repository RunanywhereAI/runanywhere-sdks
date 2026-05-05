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
        embeddingModelID: String = "",
        llmModelID: String = ""
    ) -> RARAGConfiguration {
        var c = RARAGConfiguration()
        c.embeddingModelID = embeddingModelID
        c.llmModelID = llmModelID
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

    /// D-6: Since commons owns model-id → path resolution, this helper now
    /// only stamps the resolved model ids onto the configuration and defers
    /// path resolution to the native RAG session-create ABI. Callers still
    /// pass ``RAModelLoadResult`` so the lifecycle has been invoked (which
    /// ensures the models are registered) before the native create runs.
    public func resolvingLifecycleArtifacts(
        embedding: RAModelLoadResult,
        llm: RAModelLoadResult
    ) throws -> RARAGConfiguration {
        var resolved = self
        resolved.embeddingModelID = embedding.modelID
        resolved.llmModelID = llm.modelID
        return resolved
    }
}

// MARK: - RARAGDocument

extension RARAGDocument {
    public init(text: String, metadataJSON: String? = nil) {
        // IDL-13: `metadata_json` proto field was removed; decode the caller's
        // JSON blob (if any) into the typed `metadata` map.
        self.init()
        self.text = text
        if let metadataJSON, !metadataJSON.isEmpty,
           let data = metadataJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed {
                self.metadata[key] = String(describing: value)
            }
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

// D-6: `mergingRAGConfig` and its JSONSerialization-backed embedding config
// merger are deleted — commons now resolves vocabulary paths itself from the
// registered model descriptor, so Swift no longer assembles
// `embeddingConfigJson` on the SDK side.
