//
//  MemoryProfile.swift
//  RunAnywhere SDK
//
//  Memory profile data model
//

import Foundation

/// Current memory profile
public struct MemoryProfile {
    /// Current memory usage in bytes
    public let currentUsage: Int64

    /// Peak memory usage in bytes
    public let peakUsage: Int64

    /// Baseline memory in bytes
    public let baseline: Int64

    /// Memory snapshots
    public let snapshots: [MemorySnapshot]

    public init(
        currentUsage: Int64 = 0,
        peakUsage: Int64 = 0,
        baseline: Int64 = 0,
        snapshots: [MemorySnapshot] = []
    ) {
        self.currentUsage = currentUsage
        self.peakUsage = peakUsage
        self.baseline = baseline
        self.snapshots = snapshots
    }
}
