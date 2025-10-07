//
//  AllocationInfo.swift
//  RunAnywhere SDK
//
//  Memory allocation information
//

import Foundation

/// Memory allocation information
public struct AllocationInfo {
    /// Unique identifier
    public let id: String

    /// Name of the allocation
    public let name: String

    /// Initial size in bytes
    public let initialSize: Int64

    /// Current size in bytes
    public var currentSize: Int64

    /// When this allocation started
    public let startTime: Date

    /// Whether this allocation is still active
    public var isActive: Bool

    /// Duration of the allocation
    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    public init(
        id: String,
        name: String,
        initialSize: Int64,
        currentSize: Int64,
        startTime: Date,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.initialSize = initialSize
        self.currentSize = currentSize
        self.startTime = startTime
        self.isActive = isActive
    }
}
