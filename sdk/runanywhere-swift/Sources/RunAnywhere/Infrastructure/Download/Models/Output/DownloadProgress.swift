//
//  DownloadProgress.swift
//  RunAnywhere SDK
//
//  Unified DownloadProgress / DownloadStage / DownloadState are now
//  generated from `idl/download_service.proto` via protoc-gen-swift.
//  This file exposes canonical aliases and the small amount of Swift
//  sugar (factory helpers + stage weighting) that SDK consumers use.
//

import Foundation

// MARK: - Stage Helpers

public extension RADownloadStage {
    /// Display name for UI.
    var displayName: String {
        switch self {
        case .unspecified: return "Pending"
        case .downloading: return "Downloading"
        case .extracting: return "Extracting"
        case .validating: return "Validating"
        case .completed: return "Completed"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// Weight of this stage for overall progress calculation.
    /// Download: 0-80%, Extraction: 80-95%, Validation: 95-99%, Completed: 100%.
    var progressRange: (start: Double, end: Double) {
        switch self {
        case .downloading: return (0.0, 0.80)
        case .extracting: return (0.80, 0.95)
        case .validating: return (0.95, 0.99)
        case .completed: return (1.0, 1.0)
        default: return (0.0, 0.0)
        }
    }
}

// MARK: - Progress Helpers

public extension RADownloadProgress {
    /// Download speed (bytes/sec). `nil` when unknown.
    var speed: Double? {
        overallSpeedBps > 0 ? Double(overallSpeedBps) : nil
    }

    /// Estimated time remaining. `nil` when unknown.
    var estimatedTimeRemaining: TimeInterval? {
        etaSeconds >= 0 ? TimeInterval(etaSeconds) : nil
    }

    // MARK: - Factories

    /// Progress for the extraction stage.
    static func extraction(
        modelId: String,
        progress: Double,
        totalBytes: Int64 = 0
    ) -> RADownloadProgress {
        var msg = RADownloadProgress()
        msg.modelID = modelId
        msg.stage = .extracting
        msg.state = .extracting
        msg.bytesDownloaded = Int64(progress * Double(totalBytes))
        msg.totalBytes = totalBytes
        msg.stageProgress = Float(progress)
        msg.etaSeconds = -1
        return msg
    }

    /// Completed progress.
    static func completed(modelId: String = "", totalBytes: Int64) -> RADownloadProgress {
        var msg = RADownloadProgress()
        msg.modelID = modelId
        msg.stage = .completed
        msg.state = .completed
        msg.bytesDownloaded = totalBytes
        msg.totalBytes = totalBytes
        msg.stageProgress = 1.0
        msg.etaSeconds = 0
        return msg
    }

    /// Failed progress. The canonical proto uses a string error message
    /// rather than a Swift `Error`; we capture `localizedDescription`.
    static func failed(
        _ error: Error,
        modelId: String = "",
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0
    ) -> RADownloadProgress {
        var msg = RADownloadProgress()
        msg.modelID = modelId
        msg.stage = .downloading
        msg.state = .failed
        msg.bytesDownloaded = bytesDownloaded
        msg.totalBytes = totalBytes
        msg.stageProgress = 0
        msg.etaSeconds = -1
        msg.errorMessage = error.localizedDescription
        return msg
    }

    // MARK: - Convenience Init

    /// Common-case init for the download stage.
    init(
        modelId: String = "",
        stage: RADownloadStage,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        stageProgress: Double,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        state: RADownloadState,
        retryAttempt: Int32 = 0,
        errorMessage: String = ""
    ) {
        self.init()
        self.modelID = modelId
        self.stage = stage
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.stageProgress = Float(stageProgress)
        self.overallSpeedBps = Float(speed ?? 0)
        self.etaSeconds = estimatedTimeRemaining.map { Int64($0) } ?? -1
        self.state = state
        self.retryAttempt = retryAttempt
        self.errorMessage = errorMessage
    }
}

// MARK: - State Helpers

public extension RADownloadState {
    /// Human-readable error text for the `.failed` state (mirrors the
    /// previous hand-rolled enum case's associated `Error`).
    var errorDescription: String? { nil }
}
