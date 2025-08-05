import Foundation

/// No-op implementation of GenerationAnalyticsService for when database is disabled
public actor NoOpGenerationAnalyticsService: GenerationAnalyticsService {
    private let logger = SDKLogger(category: "NoOpGenerationAnalytics")

    public init() {
        logger.info("Initialized no-op generation analytics service")
    }

    // MARK: - Session lifecycle

    public func startSession(modelId: String, type: SessionType) async -> GenerationSession {
        logger.debug("startSession called (no-op)")
        return GenerationSession(
            id: UUID(),
            modelId: modelId,
            sessionType: type,
            startTime: Date(),
            endTime: nil
        )
    }

    public func endSession(_ sessionId: UUID) async {
        logger.debug("endSession called (no-op)")
    }

    public func getSession(_ id: UUID) async -> GenerationSession? {
        logger.debug("getSession called (no-op)")
        return nil
    }

    public func getActiveSessions() async -> [GenerationSession] {
        logger.debug("getActiveSessions called (no-op)")
        return []
    }

    // MARK: - Generation tracking

    public func startGeneration(sessionId: UUID) async -> Generation {
        logger.debug("startGeneration called (no-op)")
        return Generation(
            id: UUID(),
            sessionId: sessionId,
            sequenceNumber: 0,
            timestamp: Date(),
            performance: nil
        )
    }

    public func completeGeneration(_ generationId: UUID, performance: GenerationPerformance) async {
        logger.debug("completeGeneration called (no-op)")
    }

    public func getGenerations(for sessionId: UUID) async -> [Generation] {
        logger.debug("getGenerations called (no-op)")
        return []
    }

    public func getGeneration(_ id: UUID) async -> Generation? {
        logger.debug("getGeneration called (no-op)")
        return nil
    }

    // MARK: - Live metrics

    public func observeLiveMetrics(for generationId: UUID) -> AsyncStream<LiveGenerationMetrics> {
        logger.debug("observeLiveMetrics called (no-op)")
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func getTracker(for generationId: UUID) async -> PerformanceTracker? {
        logger.debug("getTracker called (no-op)")
        return nil
    }

    // MARK: - Analytics queries

    public func getSessionSummary(_ sessionId: UUID) async -> SessionSummary? {
        logger.debug("getSessionSummary called (no-op)")
        return nil
    }

    public func getAverageMetrics(for modelId: String, limit: Int) async -> AverageMetrics? {
        logger.debug("getAverageMetrics called (no-op)")
        return nil
    }

    public func getAllSessions() async -> [GenerationSession] {
        logger.debug("getAllSessions called (no-op)")
        return []
    }

    public func getCurrentSessionId() async -> UUID? {
        logger.debug("getCurrentSessionId called (no-op)")
        return nil
    }
}
