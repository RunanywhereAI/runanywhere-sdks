//
//  DownloadProgress.swift
//  RunAnywhere SDK
//
//  Unified DownloadProgress / DownloadState are generated from
//  `idl/download_service.proto` via protoc-gen-swift. This file exposes the
//  small amount of Swift sugar (factory helpers + display/weighting) that
//  SDK consumers use.
//
//  idl/download_service.proto folded the separate DownloadStage enum into
//  DownloadState (11 cases: unspecified/pending/downloading/extracting/
//  retrying/completed/failed/cancelled/paused/resuming/validating) and
//  renamed overallSpeedBps -> bytesPerSecond. `.state` alone now carries
//  what `.stage` + `.state` used to carry between them.
//

import Foundation

// MARK: - State Helpers

public extension RADownloadState {
    /// Display name for UI.
    var displayName: String {
        switch self {
        case .unspecified, .pending: return "Pending"
        case .downloading: return "Downloading"
        case .extracting: return "Extracting"
        case .validating: return "Validating"
        case .retrying: return "Retrying"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .paused: return "Paused"
        case .resuming: return "Resuming"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// Human-readable error text for the `.failed` state (mirrors the
    /// previous hand-rolled enum case's associated `Error`).
    var errorDescription: String? { nil }
}

// MARK: - Progress Helpers

public extension RADownloadProgress {
    /// Download speed (bytes/sec). `nil` when unknown.
    var speed: Double? {
        bytesPerSecond > 0 ? Double(bytesPerSecond) : nil
    }

    /// Estimated time remaining. `nil` when unknown.
    var estimatedTimeRemaining: TimeInterval? {
        etaSeconds >= 0 ? TimeInterval(etaSeconds) : nil
    }

    // MARK: - Factories

    /// Completed progress.
    static func completed(modelId: String = "", totalBytes: Int64) -> RADownloadProgress {
        var msg = RADownloadProgress()
        msg.modelID = modelId
        msg.state = .completed
        msg.bytesDownloaded = totalBytes
        msg.totalBytes = totalBytes
        msg.stageProgress = 1.0
        msg.etaSeconds = 0
        return msg
    }

    /// Failed progress. The canonical proto carries a structured `SDKError`
    /// submessage; we capture the Swift error's `localizedDescription`.
    static func failed(
        _ error: Error,
        modelId: String = "",
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0
    ) -> RADownloadProgress {
        var msg = RADownloadProgress()
        msg.modelID = modelId
        msg.state = .failed
        msg.bytesDownloaded = bytesDownloaded
        msg.totalBytes = totalBytes
        msg.stageProgress = 0
        msg.etaSeconds = -1
        msg.error = RASDKError.make(
            code: .internal,
            message: error.localizedDescription,
            category: .internal
        )
        return msg
    }

    // MARK: - Convenience Init

    /// Common-case init for the download state.
    init(
        modelId: String = "",
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
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.stageProgress = Float(stageProgress)
        self.bytesPerSecond = Float(speed ?? 0)
        self.etaSeconds = estimatedTimeRemaining.map { Int64($0) } ?? -1
        self.state = state
        self.retryAttempt = retryAttempt
        if !errorMessage.isEmpty {
            self.error = RASDKError.make(
                code: .internal,
                message: errorMessage,
                category: .internal
            )
        }
    }
}
