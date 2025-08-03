//
//  OperationMemoryProfile.swift
//  RunAnywhere SDK
//
//  Memory profile for a specific operation
//

import Foundation

/// Memory profile for a specific operation
public struct OperationMemoryProfile {
    /// Name of the operation
    public let operationName: String

    /// Memory used by the operation in bytes
    public let memoryUsed: Int64

    /// Peak memory during the operation
    public let peakMemory: Int64

    /// Duration of the operation
    public let duration: TimeInterval

    /// Allocations made during the operation
    public let allocations: [AllocationInfo]

    public init(
        operationName: String,
        memoryUsed: Int64,
        peakMemory: Int64,
        duration: TimeInterval,
        allocations: [AllocationInfo]
    ) {
        self.operationName = operationName
        self.memoryUsed = memoryUsed
        self.peakMemory = peakMemory
        self.duration = duration
        self.allocations = allocations
    }
}
