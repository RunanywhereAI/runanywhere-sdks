import Foundation

/// Implementation of generation analytics service
public actor GenerationAnalyticsServiceImpl: GenerationAnalyticsService {
    // MARK: - Properties

    private let repository: GenerationAnalyticsRepository
    private let telemetryService: any TelemetryRepository
    private let performanceMonitor: PerformanceMonitor
    private let logger = SDKLogger(category: "GenerationAnalytics")

    // In-memory caches
    private var activeSessions: [UUID: GenerationSession] = [:]
    private var activeTrackers: [UUID: PerformanceTracker] = [:]

    // MARK: - Initialization

    public init(
        repository: GenerationAnalyticsRepository,
        telemetryService: any TelemetryRepository,
        performanceMonitor: PerformanceMonitor
    ) {
        self.repository = repository
        self.telemetryService = telemetryService
        self.performanceMonitor = performanceMonitor
    }

    // MARK: - Session Management

    public func startSession(modelId: String, type: SessionType) async -> GenerationSession {
        let session = GenerationSession(
            modelId: modelId,
            sessionType: type
        )

        activeSessions[session.id] = session

        do {
            try await repository.saveSession(session)

            // Track telemetry event
            let telemetryData = TelemetryData(
                id: UUID().uuidString,
                eventType: "generation_session_started",
                properties: [
                    "sessionId": session.id.uuidString,
                    "modelId": modelId,
                    "type": type.rawValue
                ],
                timestamp: Date(),
                syncPending: true
            )
            try await telemetryService.save(telemetryData)

            logger.info("Started generation session: \(session.id)")
        } catch {
            logger.error("Failed to save session: \(error)")
        }

        return session
    }

    public func endSession(_ sessionId: UUID) async {
        var session: GenerationSession?
        if let activeSession = activeSessions[sessionId] {
            session = activeSession
        } else {
            session = await getSession(sessionId)
        }

        guard var unwrappedSession = session else {
            logger.warning("Attempted to end non-existent session: \(sessionId)")
            return
        }

        unwrappedSession.endTime = Date()
        unwrappedSession.totalDuration = unwrappedSession.endTime?.timeIntervalSince(unwrappedSession.startTime) ?? 0

        activeSessions.removeValue(forKey: sessionId)

        do {
            try await repository.updateSession(unwrappedSession)

            // Track telemetry event
            let telemetryData = TelemetryData(
                id: UUID().uuidString,
                eventType: "generation_session_ended",
                properties: [
                    "sessionId": unwrappedSession.id.uuidString,
                    "modelId": unwrappedSession.modelId,
                    "type": unwrappedSession.sessionType.rawValue,
                    "duration": String(unwrappedSession.totalDuration),
                    "generationCount": String(unwrappedSession.generationCount)
                ],
                timestamp: Date(),
                syncPending: true
            )
            try await telemetryService.save(telemetryData)

            logger.info("Ended generation session: \(sessionId)")
        } catch {
            logger.error("Failed to update session: \(error)")
        }
    }

    public func getSession(_ id: UUID) async -> GenerationSession? {
        // Check cache first
        if let session = activeSessions[id] {
            return session
        }

        // Fall back to repository
        do {
            return try await repository.getSession(id)
        } catch {
            logger.error("Failed to fetch session: \(error)")
            return nil
        }
    }

    public func getActiveSessions() async -> [GenerationSession] {
        Array(activeSessions.values)
    }

    // MARK: - Generation Tracking

    public func startGeneration(sessionId: UUID) async -> Generation {
        let sequenceNumber = activeSessions[sessionId]?.generationCount ?? 0

        let generation = Generation(
            sessionId: sessionId,
            sequenceNumber: sequenceNumber
        )

        // Create performance tracker
        let tracker = PerformanceTracker(
            generationId: generation.id,
            sessionId: sessionId
        )
        activeTrackers[generation.id] = tracker

        // Update session generation count
        if var session = activeSessions[sessionId] {
            session.generationCount += 1
            activeSessions[sessionId] = session
        }

        do {
            try await repository.saveGeneration(generation)
            logger.info("Started generation: \(generation.id) in session: \(sessionId)")
        } catch {
            logger.error("Failed to save generation: \(error)")
        }

        return generation
    }

    public func completeGeneration(_ generationId: UUID, performance: GenerationPerformance) async {
        // Remove tracker
        activeTrackers.removeValue(forKey: generationId)

        // Update generation with performance data
        do {
            if var generation = try await repository.getGeneration(generationId) {
                generation.performance = performance
                try await repository.updateGeneration(generation)

                // Update session aggregates
                await updateSessionMetrics(generation.sessionId, with: performance)

                // Track telemetry event
                let telemetryData = TelemetryData(
                    id: UUID().uuidString,
                    eventType: "generation_completed",
                    properties: [
                        "generationId": generationId.uuidString,
                        "sessionId": generation.sessionId.uuidString,
                        "modelId": performance.modelId,
                        "timeToFirstToken": String(performance.timeToFirstToken),
                        "totalTime": String(performance.totalGenerationTime),
                        "tokensPerSecond": String(performance.tokensPerSecond),
                        "executionTarget": performance.executionTarget.rawValue
                    ],
                    timestamp: Date(),
                    syncPending: true
                )
                try await telemetryService.save(telemetryData)

                logger.info("Completed generation: \(generationId)")
            }
        } catch {
            logger.error("Failed to update generation: \(error)")
        }
    }

    public func getGenerations(for sessionId: UUID) async -> [Generation] {
        do {
            return try await repository.getGenerations(sessionId: sessionId)
        } catch {
            logger.error("Failed to fetch generations: \(error)")
            return []
        }
    }

    public func getGeneration(_ id: UUID) async -> Generation? {
        do {
            return try await repository.getGeneration(id)
        } catch {
            logger.error("Failed to fetch generation: \(error)")
            return nil
        }
    }

    // MARK: - Live Metrics

    public func observeLiveMetrics(for generationId: UUID) -> AsyncStream<LiveGenerationMetrics> {
        AsyncStream { continuation in
            Task { [weak self] in
                if let tracker = await self?.activeTrackers[generationId] {
                    for await metric in await tracker.liveMetricsStream {
                        continuation.yield(metric)
                    }
                }
                continuation.finish()
            }
        }
    }

    public func getTracker(for generationId: UUID) async -> PerformanceTracker? {
        activeTrackers[generationId]
    }

    // MARK: - Analytics Queries

    public func getSessionSummary(_ sessionId: UUID) async -> SessionSummary? {
        guard let session = await getSession(sessionId) else {
            return nil
        }

        return SessionSummary(
            sessionId: session.id,
            totalGenerations: session.generationCount,
            totalDuration: session.totalDuration,
            averageTimeToFirstToken: session.averageTimeToFirstToken,
            averageTokensPerSecond: session.averageTokensPerSecond,
            totalInputTokens: session.totalInputTokens,
            totalOutputTokens: session.totalOutputTokens
        )
    }

    public func getAverageMetrics(for modelId: String, limit: Int) async -> AverageMetrics? {
        do {
            let sessions = try await repository.getSessionsByModel(modelId, limit: limit)

            guard !sessions.isEmpty else { return nil }

            let totalGenerations = sessions.reduce(0) { $0 + $1.generationCount }
            let avgTimeToFirstToken = sessions.reduce(0.0) { $0 + $1.averageTimeToFirstToken } / Double(sessions.count)
            let avgTokensPerSecond = sessions.reduce(0.0) { $0 + $1.averageTokensPerSecond } / Double(sessions.count)
            let avgInputTokens = Double(sessions.reduce(0) { $0 + $1.totalInputTokens }) / Double(totalGenerations)
            let avgOutputTokens = Double(sessions.reduce(0) { $0 + $1.totalOutputTokens }) / Double(totalGenerations)

            return AverageMetrics(
                modelId: modelId,
                sessionCount: sessions.count,
                generationCount: totalGenerations,
                averageTimeToFirstToken: avgTimeToFirstToken,
                averageTokensPerSecond: avgTokensPerSecond,
                averageInputTokens: avgInputTokens,
                averageOutputTokens: avgOutputTokens
            )
        } catch {
            logger.error("Failed to calculate average metrics: \(error)")
            return nil
        }
    }

    public func getAllSessions() async -> [GenerationSession] {
        do {
            return try await repository.getAllSessions()
        } catch {
            logger.error("Failed to fetch all sessions: \(error)")
            return []
        }
    }

    public func getCurrentSessionId() async -> UUID? {
        // Return the most recently active session
        return activeSessions.values
            .filter { $0.endTime == nil }
            .sorted { $0.startTime > $1.startTime }
            .first?.id
    }

    // MARK: - Private Methods

    private func updateSessionMetrics(_ sessionId: UUID, with performance: GenerationPerformance) async {
        var session: GenerationSession?
        if let activeSession = activeSessions[sessionId] {
            session = activeSession
        } else {
            session = await getSession(sessionId)
        }

        guard var unwrappedSession = session else {
            return
        }

        // Update cumulative metrics
        unwrappedSession.totalInputTokens += performance.inputTokens
        unwrappedSession.totalOutputTokens += performance.outputTokens

        // Update averages
        let count = Double(unwrappedSession.generationCount)
        if count > 0 {
            // Running average calculation
            unwrappedSession.averageTimeToFirstToken =
                ((unwrappedSession.averageTimeToFirstToken * (count - 1)) + performance.timeToFirstToken) / count
            unwrappedSession.averageTokensPerSecond =
                ((unwrappedSession.averageTokensPerSecond * (count - 1)) + performance.tokensPerSecond) / count
        }

        // Update cache and persist
        activeSessions[sessionId] = unwrappedSession

        do {
            try await repository.updateSession(unwrappedSession)
        } catch {
            logger.error("Failed to update session metrics: \(error)")
        }
    }
}
