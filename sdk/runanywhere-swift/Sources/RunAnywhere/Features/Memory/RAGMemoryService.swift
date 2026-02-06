//
//  RAGMemoryService.swift
//  RunAnywhere SDK
//
//  High-level RAG memory service: remember/recall/forget.
//  Composes embedding provider + vector search for seamless text-based memory.
//

import Foundation

/// High-level RAG memory service
///
/// Provides a simple text-based interface for memory operations:
/// - `remember()` — embed text and store with metadata
/// - `recall()` — embed query and search for similar text
/// - `forget()` — delete entries by ID
///
/// ## Usage
/// ```swift
/// let memory = try await RAGMemoryService(
///     config: MemoryConfiguration(dimension: 384),
///     embedder: LlamaCppEmbeddingProvider(dimension: 384)
/// )
///
/// let id = try await memory.remember("The capital of France is Paris")
/// let results = try await memory.recall("What is France's capital?", k: 3)
/// ```
public actor RAGMemoryService {

    private let bridge: CppBridge.Memory
    private let embedder: any EmbeddingProvider
    private let config: MemoryConfiguration
    private var nextId: UInt64 = 1
    private let logger = SDKLogger(category: "RAGMemory")

    /// Create a new RAG memory service
    ///
    /// - Parameters:
    ///   - config: Memory index configuration
    ///   - embedder: Embedding provider for text-to-vector conversion
    ///   - bridge: Memory bridge instance (default: shared)
    public init(
        config: MemoryConfiguration,
        embedder: any EmbeddingProvider,
        bridge: CppBridge.Memory = .shared
    ) async throws {
        self.config = config
        self.embedder = embedder
        self.bridge = bridge

        try await bridge.create(config: config)
        logger.info("RAG memory service initialized: dim=\(config.dimension)")
    }

    // MARK: - High-Level RAG API

    /// Embed text and store in the index
    ///
    /// The original text is stored in metadata (key: `_text`) so it can be
    /// retrieved during recall operations.
    ///
    /// - Parameters:
    ///   - text: Text to remember
    ///   - metadata: Optional user metadata (merged with internal metadata)
    /// - Returns: The assigned vector ID
    public func remember(_ text: String, metadata: [String: Any]? = nil) async throws -> UInt64 {
        let embedding = try await embedder.embed(text)
        let id = generateId()

        // Build metadata JSON with _text key
        var fullMetadata: [String: Any] = metadata ?? [:]
        fullMetadata["_text"] = text

        let metadataJson = try serializeMetadata(fullMetadata)

        try await bridge.add(vectors: [embedding], ids: [id], metadata: [metadataJson])

        logger.debug("Remembered text (id=\(id), length=\(text.count))")
        return id
    }

    /// Embed query and search for similar text entries
    ///
    /// - Parameters:
    ///   - query: Query text to search for
    ///   - k: Number of results to return (default: 5)
    /// - Returns: Array of recall results with text, score, and metadata
    public func recall(_ query: String, k: Int = 5) async throws -> [MemoryRecallResult] {
        let queryEmbedding = try await embedder.embed(query)
        let results = try await bridge.search(query: queryEmbedding, k: k)

        return results.map { r in
            let text = (r.metadata?["_text"] as? String) ?? ""
            var userMetadata = r.metadata
            userMetadata?.removeValue(forKey: "_text")

            return MemoryRecallResult(
                id: r.id,
                text: text,
                score: r.score,
                metadata: userMetadata?.isEmpty == true ? nil : userMetadata
            )
        }
    }

    /// Delete entries by IDs
    ///
    /// - Parameter ids: IDs of entries to delete
    public func forget(_ ids: [UInt64]) async throws {
        try await bridge.remove(ids: ids)
        logger.debug("Forgot \(ids.count) entries")
    }

    /// Save the memory index to disk
    public func save() async throws {
        let path = config.persistPath ?? defaultPersistPath()
        try await bridge.save(to: path)
    }

    /// Load a memory index from disk
    public func load(from path: String? = nil) async throws {
        let loadPath = path ?? config.persistPath ?? defaultPersistPath()
        try await bridge.load(from: loadPath)
    }

    /// Get index statistics
    public func stats() async throws -> MemoryStats {
        try await bridge.getStats()
    }

    // MARK: - Private Helpers

    private func generateId() -> UInt64 {
        let id = nextId
        nextId += 1
        return id
    }

    private func serializeMetadata(_ metadata: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: metadata)
        guard let str = String(data: data, encoding: .utf8) else {
            throw SDKError.memory(.encodingError, "Failed to serialize metadata to JSON")
        }
        return str
    }

    private func defaultPersistPath() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("RunAnywhere/Memory/default.racm").path
    }
}
