import Foundation

/// Download status enumeration
public enum DownloadStatus {
    case pending
    case downloading
    case extracting
    case completed
    case failed(Error)
    case cancelled
    case retrying(attempt: Int)
}
