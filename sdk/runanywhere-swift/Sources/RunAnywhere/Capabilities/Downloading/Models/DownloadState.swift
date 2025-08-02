import Foundation

/// Download state enumeration
public enum DownloadState {
    case pending
    case downloading
    case extracting
    case retrying(attempt: Int)
    case completed
    case failed(Error)
    case cancelled
}
