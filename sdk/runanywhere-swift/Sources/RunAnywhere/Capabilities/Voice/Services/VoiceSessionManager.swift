import Foundation

/// Manages voice session lifecycle
public class VoiceSessionManager {
    private let logger = SDKLogger(category: "VoiceSessionManager")

    // Session storage
    private var sessions: [String: VoiceSession] = [:]
    private var activeSessionId: String?

    // Thread safety
    private let sessionQueue = DispatchQueue(label: "com.runanywhere.voice.session", attributes: .concurrent)

    public init() {}

    /// Initialize the session manager
    public func initialize() async {
        logger.info("Initializing voice session manager")
        // Any async initialization if needed
    }

    /// Create a new voice session
    /// - Parameter config: Session configuration
    /// - Returns: Created voice session
    public func createSession(config: VoiceSessionConfig) -> VoiceSession {
        let session = VoiceSession(
            id: UUID().uuidString,
            configuration: config,
            state: .idle
        )

        sessionQueue.async(flags: .barrier) {
            self.sessions[session.id] = session
            self.logger.info("Created voice session: \(session.id)")
        }

        return session
    }

    /// Start a voice session
    /// - Parameter sessionId: ID of the session to start
    public func startSession(_ sessionId: String) {
        sessionQueue.async(flags: .barrier) {
            if var session = self.sessions[sessionId] {
                session.state = .listening
                session.startTime = Date()
                self.sessions[sessionId] = session
                self.activeSessionId = sessionId
                self.logger.info("Started voice session: \(sessionId)")
            }
        }
    }

    /// End a voice session
    /// - Parameter sessionId: ID of the session to end
    public func endSession(_ sessionId: String) {
        sessionQueue.async(flags: .barrier) {
            if var session = self.sessions[sessionId] {
                session.state = .ended
                session.endTime = Date()
                self.sessions[sessionId] = session

                if self.activeSessionId == sessionId {
                    self.activeSessionId = nil
                }

                self.logger.info("Ended voice session: \(sessionId)")
            }
        }
    }

    /// Get the active session
    /// - Returns: Active voice session if any
    public func getActiveSession() -> VoiceSession? {
        return sessionQueue.sync {
            guard let activeId = activeSessionId else { return nil }
            return sessions[activeId]
        }
    }

    /// Get a session by ID
    /// - Parameter sessionId: Session ID
    /// - Returns: Voice session if found
    public func getSession(_ sessionId: String) -> VoiceSession? {
        return sessionQueue.sync {
            sessions[sessionId]
        }
    }

    /// Get all sessions
    /// - Returns: All voice sessions
    public func getAllSessions() -> [VoiceSession] {
        return sessionQueue.sync {
            Array(sessions.values)
        }
    }

    /// Update session state
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - state: New state
    public func updateSessionState(_ sessionId: String, state: VoiceSessionState) {
        sessionQueue.async(flags: .barrier) {
            if var session = self.sessions[sessionId] {
                session.state = state
                self.sessions[sessionId] = session
                self.logger.debug("Updated session \(sessionId) state to: \(state)")
            }
        }
    }

    /// Add transcript to session
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - transcript: Transcript to add
    public func addTranscript(_ sessionId: String, transcript: STTResult) {
        sessionQueue.async(flags: .barrier) {
            if var session = self.sessions[sessionId] {
                session.transcripts.append(transcript)
                self.sessions[sessionId] = session
                self.logger.debug("Added transcript to session \(sessionId)")
            }
        }
    }

    /// Clean up old sessions
    /// - Parameter olderThan: Time interval for session age
    public func cleanupSessions(olderThan: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-olderThan)

        sessionQueue.async(flags: .barrier) {
            let oldSessions = self.sessions.filter { _, session in
                guard let endTime = session.endTime else { return false }
                return endTime < cutoffDate
            }

            for (id, _) in oldSessions {
                self.sessions.removeValue(forKey: id)
            }

            if !oldSessions.isEmpty {
                self.logger.info("Cleaned up \(oldSessions.count) old sessions")
            }
        }
    }

    /// Check if the session manager is healthy
    public func isHealthy() -> Bool {
        return true
    }
}
