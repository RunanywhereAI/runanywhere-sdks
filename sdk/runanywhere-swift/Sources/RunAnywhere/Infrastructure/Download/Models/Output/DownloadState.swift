import Foundation

/// Download state enumeration
/// Note: @unchecked Sendable because Error protocol is not inherently Sendable
public enum DownloadState: Equatable, @unchecked Sendable {
    case pending
    case downloading
    case extracting
    case retrying(attempt: Int)
    case completed
    case failed(Error)
    case cancelled

    // Custom Equatable implementation since Error is not Equatable
    public static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.downloading, .downloading),
             (.extracting, .extracting),
             (.completed, .completed),
             (.cancelled, .cancelled):
            return true
        case (.retrying(let lhsAttempt), .retrying(let rhsAttempt)):
            return lhsAttempt == rhsAttempt
        case (.failed(let lhsError), .failed(let rhsError)):
            // Compare error descriptions since Error is not Equatable
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// Custom Sendable conformance for Error
extension DownloadState {
    /// Thread-safe wrapper for error
    public var errorDescription: String? {
        if case .failed(let error) = self {
            return error.localizedDescription
        }
        return nil
    }
}
