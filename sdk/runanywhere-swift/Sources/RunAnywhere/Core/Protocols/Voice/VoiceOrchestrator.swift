import Foundation

/// Protocol for orchestrating the complete voice pipeline (STT → LLM → TTS)
public protocol VoiceOrchestrator {
    /// Process complete voice pipeline with streaming events
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - config: Pipeline configuration
    /// - Returns: Stream of pipeline events
    func processVoicePipeline(
        audio: Data,
        config: VoicePipelineConfig
    ) -> AsyncThrowingStream<VoicePipelineEvent, Error>

    /// Process voice query with completion handler (non-streaming)
    /// - Parameters:
    ///   - audio: Audio data to process
    ///   - config: Pipeline configuration
    /// - Returns: Complete pipeline result
    func processVoiceQuery(
        audio: Data,
        config: VoicePipelineConfig
    ) async throws -> VoicePipelineResult
}

/// Default implementation helper for timeout handling
extension VoiceOrchestrator {
    func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw VoiceOrchestratorError.timeout(seconds: timeout)
            }

            if let result = try await group.next() {
                group.cancelAll()
                return result
            }

            throw VoiceOrchestratorError.operationFailed
        }
    }
}

/// Voice orchestrator errors
public enum VoiceOrchestratorError: LocalizedError {
    case timeout(seconds: TimeInterval)
    case operationFailed
    case stageError(stage: PipelineStage, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .timeout(let seconds):
            return "Operation timed out after \(Int(seconds)) seconds"
        case .operationFailed:
            return "Voice pipeline operation failed"
        case .stageError(let stage, let error):
            return "Pipeline failed at \(stage): \(error.localizedDescription)"
        }
    }
}
