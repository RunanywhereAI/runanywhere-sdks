//
//  RerankNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.rerank` — cross-encoder reranking. Results are index pointers
//  with scores, sorted best first.
//

import Foundation

public extension RunAnywhere {

    /// Cross-encoder reranking.
    static var rerank: Rerank { Rerank() }

    /// Score documents against a query.
    struct Rerank: Sendable {

        /// Rank `documents` by relevance to `query`.
        ///
        /// ```swift
        /// let ranked = try await RunAnywhere.rerank.rerank(query: "cats", documents: docs)
        /// print(ranked.first?.index ?? -1)
        /// ```
        ///
        /// - Parameter topN: Keep only this many results; `nil` returns all.
        /// - Throws: `SDKException` when no rerank model is loaded or scoring fails.
        public func rerank(
            query: String,
            documents: [String],
            topN: Int? = nil
        ) async throws -> [RankedResult] {
            guard !documents.isEmpty else { return [] }

            // RerankCandidate was deleted outright (idl/rerank.proto): every
            // facade already built it with id set to the stringified array
            // index, so the flat `documents` list carries the same
            // information — `RerankScoredItem.index` points back into it.
            var request = RARerankRequest()
            request.query = query
            request.documents = documents
            var options = RARerankOptions.defaults()
            if let topN { options.topN = UInt32(max(0, topN)) }
            request.options = options

            let result = try await RunAnywhere.rerankProto(request)
            return result.items.map(RankedResult.init(proto:))
        }
    }
}

// MARK: - Internal proto-level helper

extension RunAnywhere {

    internal static func rerankProto(_ request: RARerankRequest) async throws -> RARerankResult {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        try await ensureServicesReady()
        // Rerank has no `ModelCategory`, so the lifecycle cannot auto-load it;
        // the model must already be resident under the rerank component.
        guard let snapshot = componentLifecycleSnapshot(.rerank),
              !(snapshot.modelID.isEmpty && snapshot.model.id.isEmpty) else {
            throw SDKException(
                code: .modelNotLoaded,
                message: "Rerank model not loaded",
                category: .component
            )
        }
        return try await CppBridge.Rerank.shared.rerank(request, loadedModel: snapshot)
    }
}
