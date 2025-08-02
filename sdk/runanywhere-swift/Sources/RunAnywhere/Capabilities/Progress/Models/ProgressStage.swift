//
//  ProgressStage.swift
//  RunAnywhere SDK
//
//  Progress stage information
//

import Foundation

/// Information about a single progress stage
public struct ProgressStage {
    public let stage: LifecycleStage
    public let startTime: Date
    public var endTime: Date?
    public var progress: Double
    public var message: String
    public var subStages: [String: Double]
    public var error: Error?

    public init(
        stage: LifecycleStage,
        startTime: Date = Date(),
        progress: Double = 0.0,
        message: String = ""
    ) {
        self.stage = stage
        self.startTime = startTime
        self.progress = progress
        self.message = message.isEmpty ? stage.defaultMessage : message
        self.subStages = [:]
        self.error = nil
    }

    /// Calculate duration from start to now or end
    public var duration: TimeInterval {
        let endTime = self.endTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }

    /// Whether the stage is completed
    public var isCompleted: Bool {
        return endTime != nil && error == nil
    }

    /// Whether the stage has failed
    public var hasFailed: Bool {
        return error != nil
    }

    /// Whether the stage is currently active
    public var isActive: Bool {
        return endTime == nil && error == nil
    }
}
