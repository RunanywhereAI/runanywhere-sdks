//
//  MemoryTypes.swift
//  RunAnywhere SDK
//
//  Types for vector similarity search and memory/RAG functionality.
//

import Foundation

// MARK: - Distance Metrics

/// Distance metric for vector similarity search
public enum DistanceMetric: Int32, Sendable, Codable {
    case l2 = 0             /// Euclidean (L2) distance
    case cosine = 1         /// Cosine similarity (1 - cosine)
    case innerProduct = 2   /// Inner product (max inner product search)
}

// MARK: - Index Types

/// Index type for vector similarity search
public enum MemoryIndexType: Int32, Sendable, Codable {
    case flat = 0   /// Brute-force exact search (good for <10K vectors)
    case hnsw = 1   /// HNSW approximate nearest neighbor (scalable)
}

// MARK: - Search Results

/// A single result from vector similarity search
public struct MemorySearchResult: Sendable {
    /// Vector ID
    public let id: UInt64

    /// Distance/similarity score (lower is closer for L2/cosine)
    public let score: Float

    /// Associated metadata (parsed from JSON)
    public let metadata: [String: Any]?

    public init(id: UInt64, score: Float, metadata: [String: Any]? = nil) {
        self.id = id
        self.score = score
        self.metadata = metadata
    }
}

/// Result from a recall operation (includes original text)
public struct MemoryRecallResult: Sendable {
    /// Vector ID
    public let id: UInt64

    /// Original text stored with this vector
    public let text: String

    /// Similarity score
    public let score: Float

    /// User-provided metadata
    public let metadata: [String: Any]?

    public init(id: UInt64, text: String, score: Float, metadata: [String: Any]? = nil) {
        self.id = id
        self.text = text
        self.score = score
        self.metadata = metadata
    }
}

// MARK: - Index Statistics

/// Statistics about a memory index
public struct MemoryStats: Sendable {
    /// Number of vectors in the index
    public let numVectors: UInt64

    /// Vector dimension
    public let dimension: UInt32

    /// Distance metric
    public let metric: DistanceMetric

    /// Index type
    public let indexType: MemoryIndexType

    /// Approximate memory usage in bytes
    public let memoryUsageBytes: UInt64
}
