//
//  RAGProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical RAG proto types. Defaults/validation are
//  owned by commons (P2-T14, `rac_rag_request_with_defaults_proto`); the
//  Swift side keeps only proto-ergonomics that have no C equivalent: JSON
//  decode into the `metadata` map, lifecycle-id stamping, and TimeInterval
//  / Date conveniences over the raw `*Ms` Int64 fields.
//

import Foundation

// MARK: - RARAGConfiguration

extension RARAGConfiguration {
    /// Canonical RAG defaults resolved by commons via
    /// `rac_rag_request_with_defaults_proto` (P2-T14). Falls back to a
    /// pure-Swift defaults populator when the native symbol is not exported
    /// (e.g. RAG backend disabled in the linked binary).
    public static func defaults(
        embeddingModelID: String = "",
        llmModelID: String = ""
    ) -> RARAGConfiguration {
        var request = RARAGConfiguration()
        request.embeddingModelID = embeddingModelID
        request.llmModelID = llmModelID
        if let resolved = resolveRAGConfigurationDefaults(request) {
            return resolved
        }
        // Symbol unavailable — mirror commons defaults so callers keep working.
        request.embeddingDimension = 384
        request.topK = 5
        request.similarityThreshold = 0.7
        request.chunkSize = 512
        request.chunkOverlap = 64
        return request
    }

    /// D-6: Commons owns model-id → path resolution; this helper now only
    /// stamps resolved model ids onto the configuration. Callers pass
    /// `RAModelLoadResult` values so the lifecycle has been invoked (and the
    /// models are registered) before the native session-create runs.
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
}

// MARK: - RARAGStatistics

extension RARAGStatistics {
    public var lastUpdated: Date? {
        guard lastUpdatedMs > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUpdatedMs) / 1000.0)
    }
}
