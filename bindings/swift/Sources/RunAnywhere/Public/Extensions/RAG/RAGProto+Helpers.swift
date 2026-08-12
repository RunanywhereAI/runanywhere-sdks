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
//  side keeps only proto-ergonomics that have no C equivalent: lifecycle-id
//  stamping and TimeInterval / Date conveniences over the raw `*Ms` Int64
//  fields.
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

// MARK: - RARAGQueryOptions

extension RARAGQueryOptions {
    /// Convenience factory for the required query string. `question` was
    /// renamed `query` (idl/rag.proto). `RARAGQueryOptions` has no generated
    /// zero-arg `defaults()` (its only field-level annotation is
    /// `rac_required`, not `rac_default`), so this builds the message
    /// directly rather than wrapping a non-existent generated factory.
    public static func defaults(question: String) -> RARAGQueryOptions {
        var options = RARAGQueryOptions()
        options.query = question
        return options
    }
}

// MARK: - RARAGResult

extension RARAGResult {
    /// `totalTimeMs` was deleted outright (idl/rag.proto); the sum of the
    /// two surviving measured phases (retrieval + generation) is the
    /// closest equivalent — never derived by subtraction from a wall clock.
    public var totalTime: TimeInterval { TimeInterval(retrievalTimeMs + generationTimeMs) / 1000.0 }
}

// MARK: - RARAGStatistics

extension RARAGStatistics {
    public var lastUpdated: Date? {
        guard lastUpdatedMs > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastUpdatedMs) / 1000.0)
    }
}
