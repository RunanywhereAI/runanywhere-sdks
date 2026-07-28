//
//  RunAnywhere+Rerank.swift
//  RunAnywhere SDK
//

import Foundation

public extension RunAnywhere {
    /// Score every candidate against `query` with the currently-loaded
    /// cross-encoder rerank model and return them ordered by descending
    /// relevance.
    ///
    /// The model must already have been imported/registered and loaded under
    /// the rerank component (`RASDKComponent.rerank`); this call never
    /// downloads weights or creates a second model owner.
    static func rerank(
        query: String,
        candidates: [RARerankCandidate],
        options: RARerankOptions = RARerankOptions()
    ) async throws -> RARerankResult {
        var request = RARerankRequest()
        request.query = query
        request.candidates = candidates
        request.options = options
        return try await rerank(request)
    }

    /// Canonical request-based cross-encoder reranking entry point.
    static func rerank(_ request: RARerankRequest) async throws -> RARerankResult {
        guard isInitialized else {
            throw SDKException(
                code: .notInitialized,
                message: "SDK not initialized",
                category: .internal
            )
        }
        try await ensureServicesReady()
        guard let snapshot = componentLifecycleSnapshot(.rerank),
              !(snapshot.modelID.isEmpty && snapshot.model.id.isEmpty) else {
            throw SDKException(
                code: .notInitialized,
                message: "Rerank model not loaded",
                category: .component
            )
        }
        return try await CppBridge.Rerank.shared.rerank(request, loadedModel: snapshot)
    }
}
