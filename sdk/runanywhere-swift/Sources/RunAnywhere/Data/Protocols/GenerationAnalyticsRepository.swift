import Foundation

/// Repository protocol for generation analytics persistence
public protocol GenerationAnalyticsRepository: Actor {
    // Session operations
    func saveSession(_ session: GenerationSession) async throws
    func updateSession(_ session: GenerationSession) async throws
    func getSession(_ id: UUID) async throws -> GenerationSession?
    func getAllSessions() async throws -> [GenerationSession]
    func getActiveSessions() async throws -> [GenerationSession]
    func deleteSession(_ id: UUID) async throws

    // Generation operations
    func saveGeneration(_ generation: Generation) async throws
    func updateGeneration(_ generation: Generation) async throws
    func getGeneration(_ id: UUID) async throws -> Generation?
    func getGenerations(sessionId: UUID) async throws -> [Generation]
    func deleteGeneration(_ id: UUID) async throws

    // Analytics queries
    func getSessionsByModel(_ modelId: String, limit: Int) async throws -> [GenerationSession]
    func getRecentGenerations(limit: Int) async throws -> [Generation]

    // Sync operations
    func getPendingSyncSessions() async throws -> [GenerationSession]
    func getPendingSyncGenerations() async throws -> [Generation]
    func markSessionsSynced(_ ids: [UUID]) async throws
    func markGenerationsSynced(_ ids: [UUID]) async throws
}
