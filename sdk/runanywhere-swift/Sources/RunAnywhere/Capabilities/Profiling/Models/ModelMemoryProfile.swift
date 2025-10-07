//
//  ModelMemoryProfile.swift
//  RunAnywhere SDK
//
//  Memory profile for model loading
//

import Foundation

/// Model memory tracking during loading
public struct ModelMemoryTracking {
    /// Framework being used
    public let framework: LLMFramework

    /// Model name
    public let modelName: String

    /// Expected size in bytes
    public let expectedSize: Int64

    /// Memory at start of loading
    public let startMemory: Int64

    /// When loading started
    public let startTime: Date

    public init(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64,
        startMemory: Int64,
        startTime: Date
    ) {
        self.framework = framework
        self.modelName = modelName
        self.expectedSize = expectedSize
        self.startMemory = startMemory
        self.startTime = startTime
    }
}

/// Model memory profile after loading
public struct ModelMemoryProfile {
    /// Framework used
    public let framework: LLMFramework

    /// Model name
    public let modelName: String

    /// Expected size in bytes
    public let expectedSize: Int64

    /// Actual memory used in bytes
    public let actualMemoryUsed: Int64

    /// Memory overhead in bytes
    public let memoryOverhead: Int64

    /// Time taken to load
    public let loadTime: TimeInterval

    /// Compression ratio
    public let compressionRatio: Double

    public init(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64,
        actualMemoryUsed: Int64,
        memoryOverhead: Int64,
        loadTime: TimeInterval,
        compressionRatio: Double
    ) {
        self.framework = framework
        self.modelName = modelName
        self.expectedSize = expectedSize
        self.actualMemoryUsed = actualMemoryUsed
        self.memoryOverhead = memoryOverhead
        self.loadTime = loadTime
        self.compressionRatio = compressionRatio
    }
}
