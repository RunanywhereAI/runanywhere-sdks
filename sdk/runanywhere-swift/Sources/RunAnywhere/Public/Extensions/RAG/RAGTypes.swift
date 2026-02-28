//
//  RAGTypes.swift
//  RunAnywhere SDK
//
//  Public types for Retrieval-Augmented Generation.
//  These are thin wrappers over C types in rac_rag_pipeline.h
//

import CRACommons
import Foundation

// MARK: - RAG Configuration

/// Configuration for a RAG pipeline
public struct RAGConfiguration: Sendable {

    /// Path to the embedding model (ONNX)
    public let embeddingModelPath: String

    /// Path to the LLM model (GGUF)
    public let llmModelPath: String

    /// Embedding vector dimension (default: 384 for all-MiniLM-L6-v2)
    public let embeddingDimension: Int

    /// Number of top chunks to retrieve per query (default: 3)
    public let topK: Int

    /// Minimum cosine similarity threshold 0.0–1.0 (default: 0.12)
    public let similarityThreshold: Float

    /// Maximum tokens to use for context sent to the LLM (default: 2048)
    public let maxContextTokens: Int

    /// Tokens per chunk when splitting documents (default: 180)
    public let chunkSize: Int

    /// Overlap tokens between consecutive chunks (default: 30)
    public let chunkOverlap: Int

    /// Prompt template with `{context}` and `{query}` placeholders.
    /// Pass `nil` to use the C default template.
    public let promptTemplate: String?

    /// Optional configuration JSON for the embedding model
    public let embeddingConfigJSON: String?

    /// Optional configuration JSON for the LLM model
    public let llmConfigJSON: String?

    public init(
        embeddingModelPath: String,
        llmModelPath: String,
        embeddingDimension: Int = 384,
        topK: Int = 3,
        similarityThreshold: Float = 0.12,
        maxContextTokens: Int = 2048,
        chunkSize: Int = 180,
        chunkOverlap: Int = 30,
        promptTemplate: String? = nil,
        embeddingConfigJSON: String? = nil,
        llmConfigJSON: String? = nil
    ) {
        self.embeddingModelPath = embeddingModelPath
        self.llmModelPath = llmModelPath
        self.embeddingDimension = embeddingDimension
        self.topK = topK
        self.similarityThreshold = similarityThreshold
        self.maxContextTokens = maxContextTokens
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
        self.promptTemplate = promptTemplate
        self.embeddingConfigJSON = embeddingConfigJSON
        self.llmConfigJSON = llmConfigJSON
    }

    // MARK: - C Bridge (rac_rag_config_t)

    /// Execute a synchronous closure with the equivalent C struct.
    ///
    /// All C string pointers remain valid only for the duration of the closure call.
    public func withCConfig<T>(_ body: (rac_rag_config_t) throws -> T) rethrows -> T {
        try embeddingModelPath.withCString { embPathPtr in
            try llmModelPath.withCString { llmPathPtr in
                try withOptionalCString(promptTemplate) { promptPtr in
                    try withOptionalCString(embeddingConfigJSON) { embConfigPtr in
                        try withOptionalCString(llmConfigJSON) { llmConfigPtr in
                            var config = rac_rag_config_t()
                            config.embedding_model_path = embPathPtr
                            config.llm_model_path = llmPathPtr
                            config.embedding_dimension = embeddingDimension
                            config.top_k = topK
                            config.similarity_threshold = similarityThreshold
                            config.max_context_tokens = maxContextTokens
                            config.chunk_size = chunkSize
                            config.chunk_overlap = chunkOverlap
                            config.prompt_template = promptPtr
                            config.embedding_config_json = embConfigPtr
                            config.llm_config_json = llmConfigPtr
                            return try body(config)
                        }
                    }
                }
            }
        }
    }

}

// MARK: - RAG Query Options

/// Options for querying the RAG pipeline
public struct RAGQueryOptions: Sendable {

    /// The user question to answer
    public let question: String

    /// Optional system prompt override. `nil` uses the pipeline default.
    public let systemPrompt: String?

    /// Maximum tokens to generate in the answer (default: 512)
    public let maxTokens: Int

    /// Sampling temperature (default: 0.7)
    public let temperature: Float

    /// Nucleus sampling parameter (default: 0.9)
    public let topP: Float

    /// Top-k sampling (default: 40)
    public let topK: Int

    public init(
        question: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.9,
        topK: Int = 40
    ) {
        self.question = question
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
    }

    // MARK: - C Bridge (rac_rag_query_t)

    /// Execute a synchronous closure with the equivalent C struct.
    ///
    /// All C string pointers remain valid only for the duration of the closure call.
    public func withCQuery<T>(_ body: (rac_rag_query_t) throws -> T) rethrows -> T {
        try question.withCString { questionPtr in
            try withOptionalCString(systemPrompt) { promptPtr in
                var query = rac_rag_query_t()
                query.question = questionPtr
                query.system_prompt = promptPtr
                query.max_tokens = Int32(maxTokens)
                query.temperature = temperature
                query.top_p = topP
                query.top_k = Int32(topK)
                return try body(query)
            }
        }
    }

}

// MARK: - RAG Search Result

/// A single retrieved document chunk with similarity score
public struct RAGSearchResult: Sendable {

    /// Unique identifier of the chunk
    public let chunkId: String

    /// Text content of the chunk
    public let text: String

    /// Cosine similarity score (0.0–1.0)
    public let similarityScore: Float

    /// Optional metadata JSON associated with the chunk
    public let metadataJSON: String?

    public init(chunkId: String, text: String, similarityScore: Float, metadataJSON: String?) {
        self.chunkId = chunkId
        self.text = text
        self.similarityScore = similarityScore
        self.metadataJSON = metadataJSON
    }

    /// Initialize from a C `rac_search_result_t`.
    ///
    /// - Note: Does NOT free the C struct — caller is responsible via `rac_rag_result_free`.
    init(from cResult: rac_search_result_t) {
        self.chunkId = cResult.chunk_id.map { String(cString: $0) } ?? ""
        self.text = cResult.text.map { String(cString: $0) } ?? ""
        self.similarityScore = cResult.similarity_score
        self.metadataJSON = cResult.metadata_json.map { String(cString: $0) }
    }
}

// MARK: - RAG Result

/// The result of a RAG query — includes the generated answer and retrieved chunks
public struct RAGResult: Sendable {

    /// The LLM-generated answer grounded in the retrieved context
    public let answer: String

    /// Document chunks retrieved during vector search
    public let retrievedChunks: [RAGSearchResult]

    /// Full context string passed to the LLM (may be nil for short contexts)
    public let contextUsed: String?

    /// Time spent in the retrieval phase (milliseconds)
    public let retrievalTimeMs: Double

    /// Time spent in the LLM generation phase (milliseconds)
    public let generationTimeMs: Double

    /// Total end-to-end query time (milliseconds)
    public let totalTimeMs: Double

    public init(
        answer: String,
        retrievedChunks: [RAGSearchResult],
        contextUsed: String?,
        retrievalTimeMs: Double,
        generationTimeMs: Double,
        totalTimeMs: Double
    ) {
        self.answer = answer
        self.retrievedChunks = retrievedChunks
        self.contextUsed = contextUsed
        self.retrievalTimeMs = retrievalTimeMs
        self.generationTimeMs = generationTimeMs
        self.totalTimeMs = totalTimeMs
    }

    // MARK: - C Bridge (rac_rag_result_t)

    /// Initialize from a C `rac_rag_result_t`.
    ///
    /// - Note: Does NOT call `rac_rag_result_free` — caller must free after this init.
    public init(from cResult: rac_rag_result_t) {
        self.answer = cResult.answer.map { String(cString: $0) } ?? ""

        var chunks: [RAGSearchResult] = []
        if cResult.num_chunks > 0, let cChunks = cResult.retrieved_chunks {
            chunks = (0..<cResult.num_chunks).map { i in
                RAGSearchResult(from: cChunks[Int(i)])
            }
        }
        self.retrievedChunks = chunks

        self.contextUsed = cResult.context_used.map { String(cString: $0) }
        self.retrievalTimeMs = cResult.retrieval_time_ms
        self.generationTimeMs = cResult.generation_time_ms
        self.totalTimeMs = cResult.total_time_ms
    }
}

// MARK: - Private Helpers

/// Execute a synchronous closure with an optional C string pointer.
///
/// If `string` is nil the closure receives `nil`.
private func withOptionalCString<T>(
    _ string: String?,
    body: (UnsafePointer<CChar>?) throws -> T
) rethrows -> T {
    if let string {
        return try string.withCString { ptr in
            try body(ptr)
        }
    } else {
        return try body(nil)
    }
}

