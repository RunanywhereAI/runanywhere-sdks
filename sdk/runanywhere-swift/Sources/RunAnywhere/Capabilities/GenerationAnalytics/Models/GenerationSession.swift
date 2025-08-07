import Foundation

/// Session is a container for multiple related generations
public struct GenerationSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public let modelId: String
    public let sessionType: SessionType
    public let startTime: Date
    public var endTime: Date?

    // Aggregated metrics updated after each generation
    public var generationCount: Int = 0
    public var totalInputTokens: Int = 0
    public var totalOutputTokens: Int = 0
    public var averageTimeToFirstToken: TimeInterval = 0
    public var averageTokensPerSecond: Double = 0
    public var totalDuration: TimeInterval = 0

    public init(
        id: UUID = UUID(),
        modelId: String,
        sessionType: SessionType,
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.id = id
        self.modelId = modelId
        self.sessionType = sessionType
        self.startTime = startTime
        self.endTime = endTime
    }
}

public enum SessionType: String, Codable, CaseIterable, Sendable {
    case chat              // Chat conversation with multiple messages
    case document          // Document generation session
    case codeAssistant     // Code completion session
    case batch             // Batch processing
    case streaming         // Continuous streaming session
    case singleGeneration  // Single generation without session context
}
