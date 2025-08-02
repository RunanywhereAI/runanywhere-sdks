//
//  DownloadError.swift
//  RunAnywhere SDK
//
//  Download-specific error types
//

import Foundation

/// Download errors
public enum DownloadError: LocalizedError {
    case networkError(Error)
    case timeout
    case partialDownload
    case checksumMismatch
    case unsupportedArchive(String)
    case extractionFailed(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Download timeout"
        case .partialDownload:
            return "Partial download detected"
        case .checksumMismatch:
            return "Downloaded file checksum mismatch"
        case .unsupportedArchive(let format):
            return "Unsupported archive format: \(format)"
        case .extractionFailed(let error):
            return "Archive extraction failed: \(error.localizedDescription)"
        case .unknown:
            return "Unknown download error"
        }
    }
}
