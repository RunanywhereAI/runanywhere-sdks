import Foundation

/// Individual generation within a session
public struct Generation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let sequenceNumber: Int
    public let timestamp: Date
    public var performance: GenerationPerformance?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        sequenceNumber: Int,
        timestamp: Date = Date(),
        performance: GenerationPerformance? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.performance = performance
    }
}
