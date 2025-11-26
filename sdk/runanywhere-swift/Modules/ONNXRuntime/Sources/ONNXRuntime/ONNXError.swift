import Foundation

/// Errors that can occur when using ONNX Runtime
public enum ONNXError: Error, LocalizedError {
    case invalidHandle
    case initializationFailed
    case modelLoadFailed(String)
    case inferenceFailed(String)
    case invalidParameters
    case notImplemented
    case transcriptionFailed(String)
    case unknown(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidHandle:
            return "Invalid ONNX Runtime handle"
        case .initializationFailed:
            return "Failed to initialize ONNX Runtime"
        case .modelLoadFailed(let path):
            return "Failed to load ONNX model from: \(path)"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        case .invalidParameters:
            return "Invalid parameters provided"
        case .notImplemented:
            return "Feature not yet implemented"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .unknown(let code):
            return "Unknown error occurred (code: \(code))"
        }
    }

    /// Convert C error code to Swift error
    static func from(code: Int32) -> ONNXError {
        switch code {
        case 0: // RA_SUCCESS
            fatalError("Should not create error from success code")
        case -1: // RA_ERROR_INVALID_HANDLE
            return .invalidHandle
        case -2: // RA_ERROR_INIT_FAILED
            return .initializationFailed
        case -3: // RA_ERROR_MODEL_LOAD_FAILED
            return .modelLoadFailed("Unknown path")
        case -4: // RA_ERROR_INFERENCE_FAILED
            return .inferenceFailed("Unknown reason")
        case -5: // RA_ERROR_INVALID_PARAMS
            return .invalidParameters
        case -6: // RA_ERROR_NOT_IMPLEMENTED
            return .notImplemented
        default:
            return .unknown(code)
        }
    }
}
