//
//  RunAnywhere+Rerank.swift
//  RunAnywhere SDK
//
//  Deprecated flat rerank verbs. The v3 surface is `RunAnywhere.rerank`.
//

import Foundation

public extension RunAnywhere {

    /// Score candidates against a query with the loaded cross-encoder.
    @available(*, deprecated, renamed: "rerank.rerank(query:documents:topN:)")
    static func rerank(
        query: String,
        candidates: [RARerankCandidate],
        options: RARerankOptions = RARerankOptions()
    ) async throws -> RARerankResult {
        var request = RARerankRequest()
        request.query = query
        request.candidates = candidates
        request.options = options
        return try await rerankProto(request)
    }

    /// Canonical request-based cross-encoder reranking entry point.
    @available(*, deprecated, renamed: "rerank.rerank(query:documents:topN:)")
    static func rerank(_ request: RARerankRequest) async throws -> RARerankResult {
        try await rerankProto(request)
    }
}
