//
//  GenerationTracking.swift
//  RunAnywhere SDK
//
//  Tracks generation performance for A/B tests
//

import Foundation

/// Generation tracking for A/B tests
public class GenerationTracking {
    // MARK: - Properties

    public let testId: UUID
    public let variantId: UUID
    public let startTime: Date
    public private(set) var endTime: Date?
    public private(set) var tokensGenerated: Int = 0
    public var completionHandler: ((GenerationTracking) -> Void)?

    // MARK: - Initialization

    public init(
        testId: UUID,
        variantId: UUID,
        startTime: Date = Date()
    ) {
        self.testId = testId
        self.variantId = variantId
        self.startTime = startTime
    }

    // MARK: - Public Methods

    /// Record a generated token
    public func recordToken() {
        tokensGenerated += 1
    }

    /// Complete the tracking
    public func complete() {
        endTime = Date()
        completionHandler?(self)
    }

    /// Get generation duration
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    /// Get tokens per second
    public var tokensPerSecond: Double? {
        guard let duration = duration, duration > 0 else { return nil }
        return Double(tokensGenerated) / duration
    }
}
