import Foundation

// MARK: - Download Stage

/// Current stage in the download pipeline
public enum DownloadStage: Sendable, Equatable {
    /// Downloading the file(s)
    case downloading

    /// Extracting archive contents
    case extracting

    /// Validating downloaded files
    case validating

    /// Download and all processing complete
    case completed

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .downloading: return "Downloading"
        case .extracting: return "Extracting"
        case .validating: return "Validating"
        case .completed: return "Completed"
        }
    }

    /// Weight of this stage for overall progress calculation
    /// Download: 0-80%, Extraction: 80-95%, Validation: 95-100%
    public var progressRange: (start: Double, end: Double) {
        switch self {
        case .downloading: return (0.0, 0.80)
        case .extracting: return (0.80, 0.95)
        case .validating: return (0.95, 0.99)
        case .completed: return (1.0, 1.0)
        }
    }
}

// MARK: - Download Progress

/// Download progress information with stage awareness
public struct DownloadProgress: Sendable {
    /// Current stage of the download pipeline
    public let stage: DownloadStage

    /// Bytes downloaded (for download stage)
    public let bytesDownloaded: Int64

    /// Total bytes to download
    public let totalBytes: Int64

    /// Current state (downloading, extracting, failed, etc.)
    public let state: DownloadState

    /// Estimated time remaining in seconds
    public let estimatedTimeRemaining: TimeInterval?

    /// Download speed in bytes per second
    public let speed: Double?

    /// Progress within current stage (0.0 to 1.0)
    public let stageProgress: Double

    /// Overall progress across all stages (0.0 to 1.0)
    public var overallProgress: Double {
        let range = stage.progressRange
        return range.start + (stageProgress * (range.end - range.start))
    }

    /// Legacy percentage property (maps to stageProgress for download stage, overallProgress otherwise)
    public var percentage: Double {
        switch stage {
        case .downloading:
            return stageProgress
        default:
            return overallProgress
        }
    }

    // MARK: - Initializers

    /// Full initializer with all fields
    public init(
        stage: DownloadStage,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        stageProgress: Double,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        state: DownloadState
    ) {
        self.stage = stage
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.stageProgress = stageProgress
        self.speed = speed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.state = state
    }

    /// Convenience init for download stage (calculates progress from bytes)
    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        state: DownloadState,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.stage = state == .extracting ? .extracting : .downloading
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.state = state
        self.speed = speed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.stageProgress = totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0
    }

    /// Convenience init with explicit percentage
    public init(
        bytesDownloaded: Int64,
        totalBytes: Int64,
        percentage: Double,
        speed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        state: DownloadState
    ) {
        self.stage = state == .extracting ? .extracting : .downloading
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.stageProgress = percentage
        self.speed = speed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.state = state
    }

    // MARK: - Factory Methods

    /// Create progress for extraction stage
    public static func extraction(
        modelId: String,
        progress: Double,
        totalBytes: Int64 = 0
    ) -> DownloadProgress {
        DownloadProgress(
            stage: .extracting,
            bytesDownloaded: Int64(progress * Double(totalBytes)),
            totalBytes: totalBytes,
            stageProgress: progress,
            state: .extracting
        )
    }

    /// Create completed progress
    public static func completed(totalBytes: Int64) -> DownloadProgress {
        DownloadProgress(
            stage: .completed,
            bytesDownloaded: totalBytes,
            totalBytes: totalBytes,
            stageProgress: 1.0,
            state: .completed
        )
    }

    /// Create failed progress
    public static func failed(_ error: Error, bytesDownloaded: Int64 = 0, totalBytes: Int64 = 0) -> DownloadProgress {
        DownloadProgress(
            stage: .downloading,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            stageProgress: 0,
            state: .failed(error)
        )
    }
}
