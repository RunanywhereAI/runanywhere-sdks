import Foundation

/// Download and file operation errors
public enum DownloadError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case timeout
    case partialDownload
    case checksumMismatch
    case extractionFailed(String)
    case unsupportedArchive(String)
    case unknown
    case invalidResponse
    case httpError(Int)
    case cancelled
    case insufficientSpace
    case modelNotFound
    case connectionLost

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Download timeout"
        case .partialDownload:
            return "Partial download - file incomplete"
        case .checksumMismatch:
            return "Downloaded file checksum doesn't match expected"
        case .extractionFailed(let reason):
            return "Archive extraction failed: \(reason)"
        case .unsupportedArchive(let format):
            return "Unsupported archive format: \(format)"
        case .unknown:
            return "Unknown download error"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .cancelled:
            return "Download was cancelled"
        case .insufficientSpace:
            return "Insufficient storage space"
        case .modelNotFound:
            return "Model not found"
        case .connectionLost:
            return "Network connection lost"
        }
    }
}
