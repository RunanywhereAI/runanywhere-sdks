//
//  MemorySnapshot.swift
//  RunAnywhere SDK
//
//  Memory snapshot at a point in time
//

import Foundation

/// Memory snapshot at a point in time
public struct MemorySnapshot {
    /// When this snapshot was taken
    public let timestamp: Date

    /// Used memory in bytes
    public let usedMemory: Int64

    /// Available memory in bytes
    public let availableMemory: Int64

    /// Number of allocations
    public let allocations: Int

    /// Memory pressure level
    public let pressure: MemoryPressure

    public init(
        timestamp: Date,
        usedMemory: Int64,
        availableMemory: Int64,
        allocations: Int,
        pressure: MemoryPressure
    ) {
        self.timestamp = timestamp
        self.usedMemory = usedMemory
        self.availableMemory = availableMemory
        self.allocations = allocations
        self.pressure = pressure
    }
}
