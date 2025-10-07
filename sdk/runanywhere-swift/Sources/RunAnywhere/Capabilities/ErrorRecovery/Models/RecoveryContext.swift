//
//  RecoveryContext.swift
//  RunAnywhere SDK
//
//  Context information for error recovery
//

import Foundation

/// Context for error recovery
public struct RecoveryContext {
    public let model: ModelInfo
    public let stage: LifecycleStage
    public let attemptCount: Int
    public let previousErrors: [Error]
    public let availableResources: ResourceAvailability
    public let options: RecoveryOptions

    public init(
        model: ModelInfo,
        stage: LifecycleStage,
        attemptCount: Int = 1,
        previousErrors: [Error] = [],
        availableResources: ResourceAvailability,
        options: RecoveryOptions = RecoveryOptions()
    ) {
        self.model = model
        self.stage = stage
        self.attemptCount = attemptCount
        self.previousErrors = previousErrors
        self.availableResources = availableResources
        self.options = options
    }
}
