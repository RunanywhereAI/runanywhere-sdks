//
//  RAGAgent.swift
//  RunAnywhere SDK
//
//  Full RAG agent: retrieves context from memory, augments prompt, generates with LLM.
//

import CRACommons
import Foundation

/// Full RAG (Retrieval-Augmented Generation) agent
///
/// Composes vector memory with LLM generation for context-aware responses.
///
/// ## Usage
/// ```swift
/// let agent = try await RAGAgent(
///     memoryConfig: MemoryConfiguration(dimension: 384),
///     embedder: LlamaCppEmbeddingProvider(dimension: 384)
/// )
///
/// // Ingest knowledge
/// try await agent.ingest("Paris is the capital of France.")
/// try await agent.ingest("Berlin is the capital of Germany.")
///
/// // Query with RAG
/// let answer = try await agent.query("What is the capital of France?")
/// ```
public actor RAGAgent {

    private let memory: RAGMemoryService
    private let llm: CppBridge.LLM
    private let logger = SDKLogger(category: "RAGAgent")

    /// Default system prompt for RAG queries
    public var systemPrompt: String = """
        You are a helpful assistant. Use the provided context to answer the question.
        If the context doesn't contain relevant information, say so.
        """

    /// Create a RAG agent
    ///
    /// - Parameters:
    ///   - memoryConfig: Configuration for the vector memory index
    ///   - embedder: Embedding provider for text-to-vector conversion
    ///   - llm: LLM bridge instance for text generation (default: shared)
    ///   - memory: Optional pre-configured RAG memory service
    public init(
        memoryConfig: MemoryConfiguration,
        embedder: any EmbeddingProvider,
        llm: CppBridge.LLM = .shared,
        memory: RAGMemoryService? = nil
    ) async throws {
        self.llm = llm
        self.memory = try await memory ?? RAGMemoryService(
            config: memoryConfig,
            embedder: embedder
        )
        logger.info("RAG agent initialized")
    }

    // MARK: - RAG Operations

    /// Query with retrieval-augmented generation
    ///
    /// 1. Retrieves relevant context from memory
    /// 2. Builds an augmented prompt with context
    /// 3. Generates a response using the LLM
    ///
    /// - Parameters:
    ///   - question: The question to answer
    ///   - k: Number of context chunks to retrieve (default: 3)
    ///   - customSystemPrompt: Optional override for the system prompt
    /// - Returns: LLM-generated answer
    public func query(
        _ question: String,
        k: Int = 3,
        customSystemPrompt: String? = nil
    ) async throws -> String {
        // Step 1: Retrieve context
        let contexts = try await memory.recall(question, k: k)

        // Step 2: Build augmented prompt
        let contextText: String
        if contexts.isEmpty {
            contextText = "(No relevant context found)"
        } else {
            contextText = contexts.enumerated().map { idx, ctx in
                "[\(idx + 1)] \(ctx.text)"
            }.joined(separator: "\n")
        }

        let prompt = """
            \(customSystemPrompt ?? systemPrompt)

            Context:
            \(contextText)

            Question: \(question)
            Answer:
            """

        // Step 3: Generate with LLM
        let handle = try await llm.getHandle()

        var options = RAC_LLM_OPTIONS_DEFAULT
        options.max_tokens = 512
        options.temperature = 0.7

        var result = rac_llm_result_t()

        let genResult = prompt.withCString { promptPtr in
            rac_llm_generate(handle, promptPtr, &options, &result)
        }

        guard genResult == RAC_SUCCESS, let text = result.text else {
            throw SDKError.llm(.generationFailed,
                              "LLM generation failed: \(genResult)")
        }

        let answer = String(cString: text)
        rac_llm_result_free(&result)

        logger.info("RAG query completed: \(contexts.count) contexts, answer length=\(answer.count)")
        return answer
    }

    /// Ingest text into memory
    ///
    /// Optionally chunks text before storing. Each chunk is embedded and
    /// stored as a separate vector in the memory index.
    ///
    /// - Parameters:
    ///   - text: Text to ingest
    ///   - chunkSize: Optional max characters per chunk (nil = store as single entry)
    ///   - overlap: Character overlap between chunks (default: 50)
    ///   - metadata: Optional metadata to attach to each chunk
    /// - Returns: Array of assigned vector IDs
    @discardableResult
    public func ingest(
        _ text: String,
        chunkSize: Int? = nil,
        overlap: Int = 50,
        metadata: [String: Any]? = nil
    ) async throws -> [UInt64] {
        let chunks: [String]
        if let size = chunkSize, size > 0 {
            chunks = TextChunker.chunk(text, maxCharacters: size, overlap: overlap)
        } else {
            chunks = [text]
        }

        var ids: [UInt64] = []
        for chunk in chunks {
            let id = try await memory.remember(chunk, metadata: metadata)
            ids.append(id)
        }

        logger.info("Ingested text: \(chunks.count) chunks, \(text.count) characters")
        return ids
    }

    /// Get the underlying memory service for direct access
    public var memoryService: RAGMemoryService {
        memory
    }
}
