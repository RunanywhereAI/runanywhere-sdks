//
//  MemoryConfiguration.swift
//  RunAnywhere SDK
//
//  Configuration for creating a memory index.
//

import Foundation

/// Configuration for creating a vector memory index
public struct MemoryConfiguration: Sendable {

    /// Embedding dimension (e.g., 384, 768, 1536). Required.
    public var dimension: UInt32

    /// Distance metric (default: cosine)
    public var metric: DistanceMetric

    /// Index type (default: HNSW)
    public var indexType: MemoryIndexType

    /// HNSW: max connections per node (default: 16)
    public var hnswM: UInt32

    /// HNSW: construction ef parameter (default: 200)
    public var hnswEfConstruction: UInt32

    /// HNSW: search ef parameter (default: 50)
    public var hnswEfSearch: UInt32

    /// Max elements capacity. 0 = auto-grow (default: 0)
    public var maxElements: UInt64

    /// Enable auto-persist after writes
    public var autoPersist: Bool

    /// File path for persistence (nil = default location)
    public var persistPath: String?

    public init(
        dimension: UInt32,
        metric: DistanceMetric = .cosine,
        indexType: MemoryIndexType = .hnsw,
        hnswM: UInt32 = 16,
        hnswEfConstruction: UInt32 = 200,
        hnswEfSearch: UInt32 = 50,
        maxElements: UInt64 = 0,
        autoPersist: Bool = false,
        persistPath: String? = nil
    ) {
        self.dimension = dimension
        self.metric = metric
        self.indexType = indexType
        self.hnswM = hnswM
        self.hnswEfConstruction = hnswEfConstruction
        self.hnswEfSearch = hnswEfSearch
        self.maxElements = maxElements
        self.autoPersist = autoPersist
        self.persistPath = persistPath
    }
}
