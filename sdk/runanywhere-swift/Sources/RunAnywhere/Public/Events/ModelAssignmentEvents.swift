import Foundation

// MARK: - Model Assignment Events

/// Event published when model assignments are successfully fetched
public struct ModelAssignmentsFetchedEvent: SDKEvent {
    /// Models that were fetched
    public let models: [ModelInfo]

    /// Timestamp when the event occurred
    public let timestamp: Date

    /// Type of event
    public let eventType: SDKEventType

    public init(models: [ModelInfo]) {
        self.models = models
        self.timestamp = Date()
        self.eventType = .model
    }

    public var description: String {
        "Model assignments fetched: \(models.count) models"
    }
}

/// Event published when model assignments fetch fails
public struct ModelAssignmentsFetchFailedEvent: SDKEvent {
    /// The error that occurred
    public let error: Error

    /// Timestamp when the event occurred
    public let timestamp: Date

    /// Type of event
    public let eventType: SDKEventType

    public init(error: Error) {
        self.error = error
        self.timestamp = Date()
        self.eventType = .error
    }

    public var description: String {
        "Model assignments fetch failed: \(error.localizedDescription)"
    }
}
