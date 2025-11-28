import Foundation

/// Error types for voice service operations
public enum VoiceError: LocalizedError {
    case serviceNotInitialized
    case modelNotFound(String)
    case transcriptionFailed(Error)
    case insufficientMemory
    case unsupportedAudioFormat

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "Voice service is not initialized"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .insufficientMemory:
            return "Insufficient memory for voice processing"
        case .unsupportedAudioFormat:
            return "Unsupported audio format"
        }
    }
}
