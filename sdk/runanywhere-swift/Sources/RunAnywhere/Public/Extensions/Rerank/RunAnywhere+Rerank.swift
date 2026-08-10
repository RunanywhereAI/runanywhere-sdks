//
//  RunAnywhere+Rerank.swift
//  RunAnywhere SDK
//
//  Deprecated flat rerank verbs. The v3 surface is `RunAnywhere.rerank`.
//

import Foundation

public extension RunAnywhere {

    /// Score documents against a query with the loaded cross-encoder.
    ///
    /// `RerankCandidate` was deleted outright (idl/rerank.proto: "every
    /// facade already builds it with id set to the stringified array
    /// index, so the wrapper carried no information the flat `documents`
    /// list below does not") — `RerankRequest.documents` is now a plain
    /// `repeated string`, and `RerankScoredItem.index` points back into it.
    @available(*, deprecated, renamed: "rerank.rerank(query:documents:topN:)")
    static func rerank(
        query: String,
        documents: [String],
        options: RARerankOptions = RARerankOptions()
    ) async throws -> RARerankResult {
        var request = RARerankRequest()
        request.query = query
        request.documents = documents
        request.options = options
        return try await rerankProto(request)
    }

    /// Canonical request-based cross-encoder reranking entry point.
    @available(*, deprecated, renamed: "rerank.rerank(query:documents:topN:)")
    static func rerank(_ request: RARerankRequest) async throws -> RARerankResult {
        try await rerankProto(request)
    }
}
