import Foundation

/// Service protocol for generation analytics tracking
public protocol GenerationAnalyticsService: Actor {
    // Session lifecycle
    func startSession(modelId: String, type: SessionType) async -> GenerationSession
    func endSession(_ sessionId: UUID) async
    func getSession(_ id: UUID) async -> GenerationSession?
    func getActiveSessions() async -> [GenerationSession]

    // Generation tracking
    func startGeneration(sessionId: UUID) async -> Generation
    func completeGeneration(_ generationId: UUID, performance: GenerationPerformance) async
    func getGenerations(for sessionId: UUID) async -> [Generation]
    func getGeneration(_ id: UUID) async -> Generation?

    // Live metrics
    func observeLiveMetrics(for generationId: UUID) -> AsyncStream<LiveGenerationMetrics>
    func getTracker(for generationId: UUID) async -> PerformanceTracker?

    // Analytics queries
    func getSessionSummary(_ sessionId: UUID) async -> SessionSummary?
    func getAverageMetrics(for modelId: String, limit: Int) async -> AverageMetrics?
    func getAllSessions() async -> [GenerationSession]
    func getCurrentSessionId() async -> UUID?
}

/// Summary statistics for a session
public struct SessionSummary: Sendable {
    public let sessionId: UUID
    public let totalGenerations: Int
    public let totalDuration: TimeInterval
    public let averageTimeToFirstToken: TimeInterval
    public let averageTokensPerSecond: Double
    public let totalInputTokens: Int
    public let totalOutputTokens: Int

    public init(
        sessionId: UUID,
        totalGenerations: Int,
        totalDuration: TimeInterval,
        averageTimeToFirstToken: TimeInterval,
        averageTokensPerSecond: Double,
        totalInputTokens: Int,
        totalOutputTokens: Int
    ) {
        self.sessionId = sessionId
        self.totalGenerations = totalGenerations
        self.totalDuration = totalDuration
        self.averageTimeToFirstToken = averageTimeToFirstToken
        self.averageTokensPerSecond = averageTokensPerSecond
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }
}

/// Average metrics across multiple sessions for a model
public struct AverageMetrics: Sendable {
    public let modelId: String
    public let sessionCount: Int
    public let generationCount: Int
    public let averageTimeToFirstToken: TimeInterval
    public let averageTokensPerSecond: Double
    public let averageInputTokens: Double
    public let averageOutputTokens: Double

    public init(
        modelId: String,
        sessionCount: Int,
        generationCount: Int,
        averageTimeToFirstToken: TimeInterval,
        averageTokensPerSecond: Double,
        averageInputTokens: Double,
        averageOutputTokens: Double
    ) {
        self.modelId = modelId
        self.sessionCount = sessionCount
        self.generationCount = generationCount
        self.averageTimeToFirstToken = averageTimeToFirstToken
        self.averageTokensPerSecond = averageTokensPerSecond
        self.averageInputTokens = averageInputTokens
        self.averageOutputTokens = averageOutputTokens
    }
}
