//
//  MemoryLeak.swift
//  RunAnywhere SDK
//
//  Detected memory leak information
//

import Foundation

/// Detected memory leak
public struct MemoryLeak {
    /// Unique identifier
    public let id: String

    /// Name of the allocation
    public let name: String

    /// Initial size in bytes
    public let initialSize: Int64

    /// Current size in bytes
    public let currentSize: Int64

    /// Growth rate in bytes per second
    public let growthRate: Double

    /// How long this allocation has been active
    public let duration: TimeInterval

    public init(
        id: String,
        name: String,
        initialSize: Int64,
        currentSize: Int64,
        growthRate: Double,
        duration: TimeInterval
    ) {
        self.id = id
        self.name = name
        self.initialSize = initialSize
        self.currentSize = currentSize
        self.growthRate = growthRate
        self.duration = duration
    }
}
