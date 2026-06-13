//
//  RAGProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical RAG proto types.
//
//  defaults() / validate() factories live in
//  Generated/RAConvenience.swift, emitted by
//  idl/codegen/generate_swift_convenience.py from the rac_default /
//  rac_min_float / rac_max_float annotations in idl/rag.proto. The Swift
//  side keeps only proto-ergonomics that have no C equivalent: JSON
//  decode into the `metadata` map, lifecycle-id stamping, and TimeInterval
//  / Date conveniences over the raw `*Ms` Int64 fields.
//

import Foundation

// MARK: - RARAGConfiguration

extension RARAGConfiguration {
    /// Commons owns model-id → path resolution; this helper now only
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
        // `metadata_json` proto field was removed; decode the caller's
        // JSON blob (if any) into the typed `metadata` map.
        self.init()
        self.text = text
        if let metadataJSON, !metadataJSON.isEmpty,
           let data = metadataJSON.data(using: .utf8),
           // swiftlint:disable:next avoid_any_type
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed {
                self.metadata[key] = String(describing: value)
            }
        }
    }

    public var metadataJSON: String? {
        guard !metadata.isEmpty,
              let data = try? JSONSerialization.data(
                withJSONObject: metadata,
                options: [.sortedKeys]
              ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - RARAGQueryOptions

extension RARAGQueryOptions {
    /// Convenience factory that wraps the generated `defaults()` with a
    /// required question string. Question is excluded from the proto
    /// annotation because it has no semantic default (caller-supplied).
    public static func defaults(question: String) -> RARAGQueryOptions {
        var options = RARAGQueryOptions.defaults()
        options.question = question
        return options
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
