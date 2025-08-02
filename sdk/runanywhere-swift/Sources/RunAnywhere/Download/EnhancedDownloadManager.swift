import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

/// Enhanced download manager - Compatibility wrapper for the new modular download system
/// This class maintains backward compatibility while delegating to the new modular components
@MainActor
public class EnhancedDownloadManager {
    public static let shared: EnhancedDownloadManager = EnhancedDownloadManager()

    private let downloadService: DownloadService
    private let modelInstaller: ModelInstaller
    private let storageCleanup: StorageCleanup

    /// Configuration for download behavior
    public struct DownloadConfig {
        public var maxConcurrentDownloads: Int = 3
        public var retryCount: Int = 3
        public var retryDelay: TimeInterval = 2.0
        public var timeout: TimeInterval = 300.0
        public var chunkSize: Int = 1024 * 1024 // 1MB chunks

        public init() {}
    }

    private var config: DownloadConfig = DownloadConfig() {
        didSet {
            updateServiceConfiguration()
        }
    }

    /// Download task information
    public typealias DownloadTask = RunAnywhere.DownloadTask

    /// Download progress information
    public typealias DownloadProgress = RunAnywhere.DownloadProgress

    /// Download state
    public typealias DownloadState = RunAnywhere.DownloadState

    /// Download errors
    public typealias DownloadError = RunAnywhere.DownloadError

    private init() {
        // Initialize with default configuration
        let downloadConfig = RunAnywhere.DownloadConfiguration(
            maxConcurrentDownloads: config.maxConcurrentDownloads,
            retryCount: config.retryCount,
            retryDelay: config.retryDelay,
            timeout: config.timeout,
            chunkSize: config.chunkSize
        )

        self.downloadService = DownloadService(configuration: downloadConfig)
        self.modelInstaller = ModelInstaller()
        self.storageCleanup = StorageCleanup()
    }

    /// Configure download manager
    public func configure(_ config: DownloadConfig) {
        self.config = config
        updateServiceConfiguration()
    }

    /// Download a model
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        return try await downloadService.downloadModel(model)
    }

    /// Cancel a download
    public func cancelDownload(taskId: String) {
        downloadService.cancelDownload(taskId: taskId)
    }

    /// Get active downloads
    public func activeDownloads() -> [DownloadTask] {
        return downloadService.activeDownloads()
    }

    /// Pause all downloads
    public func pauseAllDownloads() {
        downloadService.pauseAll()
    }

    /// Resume all downloads
    public func resumeAllDownloads() {
        downloadService.resumeAll()
    }

    /// Extract archive if needed
    public func extractArchiveIfNeeded(at url: URL) async throws -> URL {
        let archiveExtensions = ["zip", "gz", "tgz", "tar", "bz2", "tbz2", "xz", "txz"]

        guard archiveExtensions.contains(url.pathExtension.lowercased()) else {
            return url
        }

        let extractor = ArchiveExtractorFactory.createExtractor(for: url)
        return try await extractor.extract(archive: url)
    }

    /// Get download statistics
    public func getStatistics() -> (active: Int, completed: Int, failed: Int) {
        let stats = downloadService.getStatistics()
        return (
            active: stats.activeDownloads,
            completed: stats.completedDownloads,
            failed: stats.failedDownloads
        )
    }

    /// Clean up old downloads
    public func cleanupOldDownloads(olderThan days: Int = 7) async {
        await storageCleanup.cleanupOldDownloads(olderThan: days)
    }

    /// Calculate cache size
    public func calculateCacheSize() async -> Int64 {
        return await storageCleanup.calculateCacheSize()
    }

    /// Clear all caches
    public func clearAllCaches() async throws {
        try await storageCleanup.clearAllCaches()
    }

    // MARK: - Private Methods

    private func updateServiceConfiguration() {
        let downloadConfig = RunAnywhere.DownloadConfiguration(
            maxConcurrentDownloads: config.maxConcurrentDownloads,
            retryCount: config.retryCount,
            retryDelay: config.retryDelay,
            timeout: config.timeout,
            chunkSize: config.chunkSize
        )

        downloadService.configure(downloadConfig)
    }
}

// MARK: - Progress Service (for backward compatibility)

/// Progress tracking service for downloads
public class ProgressService {
    private let progressAggregator = DownloadProgressAggregator()

    public func trackDownload(taskId: String, stream: AsyncStream<DownloadProgress>) {
        progressAggregator.addProgressStream(taskId: taskId, stream: stream)
    }

    public func stopTracking(taskId: String) {
        progressAggregator.removeProgressStream(taskId: taskId)
    }

    public func getAggregatedProgress() async -> DownloadProgressAggregator.AggregatedProgress {
        return await progressAggregator.getCurrentProgress()
    }
}
