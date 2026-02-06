//
//  EmbeddingProvider.swift
//  RunAnywhere SDK
//
//  Protocol for embedding text into vectors for memory/RAG operations.
//

import CRACommons
import Foundation

/// Protocol for generating text embeddings
///
/// Implementations wrap backend-specific embedding extraction (e.g., llama.cpp, ONNX).
/// Used by RAGMemoryService to convert text to vectors for storage and search.
public protocol EmbeddingProvider: Sendable {

    /// Generate an embedding vector for the given text
    ///
    /// - Parameter text: Input text to embed
    /// - Returns: Float array of dimension `dimension`
    func embed(_ text: String) async throws -> [Float]

    /// The dimension of embeddings produced by this provider
    var dimension: UInt32 { get }
}

/// Embedding provider that uses llama.cpp's embedding mode
///
/// Uses the existing LlamaCPP backend to extract embeddings from
/// GGUF models that support it (e.g., all-MiniLM, nomic-embed-text, bge-small).
public actor LlamaCppEmbeddingProvider: EmbeddingProvider {

    private let llm: CppBridge.LLM
    private let _dimension: UInt32

    public nonisolated var dimension: UInt32 { _dimension }

    /// Create with an already-loaded LLM that supports embedding extraction
    ///
    /// - Parameters:
    ///   - llm: LLM bridge instance with a loaded embedding model
    ///   - dimension: The embedding dimension of the loaded model
    public init(llm: CppBridge.LLM = .shared, dimension: UInt32) {
        self.llm = llm
        self._dimension = dimension
    }

    public func embed(_ text: String) async throws -> [Float] {
        // Use the LlamaCPP backend's embedding extraction
        // This calls rac_llm_llamacpp_get_embeddings under the hood
        let handle = try await llm.getHandle()

        var embeddings: UnsafeMutablePointer<Float>?
        var outDim: UInt32 = 0

        let result = text.withCString { textPtr in
            rac_llm_llamacpp_get_embeddings(handle, textPtr, &embeddings, &outDim)
        }

        guard result == RAC_SUCCESS, let emb = embeddings else {
            throw SDKError.memory(.processingFailed,
                                  "Failed to extract embeddings: \(result)")
        }

        defer { rac_free(emb) }

        return Array(UnsafeBufferPointer(start: emb, count: Int(outDim)))
    }
}
