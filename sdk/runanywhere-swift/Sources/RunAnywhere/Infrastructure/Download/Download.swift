//
//  Download.swift
//  RunAnywhere SDK
//
//  Public entry point for the Download capability
//  Provides access to model downloading and file downloading functionality
//

import Foundation

/// Public entry point for the Download capability
/// Provides simplified access to download operations and download management
public final class Download {

    // MARK: - Shared Instance

    /// Shared singleton instance for convenient access
    public static let shared = Download()

    // MARK: - Properties

    private let downloadService: DownloadService
    private let logger = SDKLogger(category: "Download")

    // MARK: - Initialization

    /// Initialize with default download service
    public convenience init() {
        let configuration = DownloadConfiguration()
        let service = AlamofireDownloadService(configuration: configuration)
        self.init(downloadService: service)
    }

    /// Initialize with custom download service (for testing or customization)
    /// - Parameter downloadService: The download service to use
    internal init(downloadService: DownloadService) {
        self.downloadService = downloadService
        logger.debug("Download initialized")
    }

    /// Initialize with custom configuration
    /// - Parameter configuration: The download configuration to use
    public convenience init(configuration: DownloadConfiguration) {
        let service = AlamofireDownloadService(configuration: configuration)
        self.init(downloadService: service)
    }

    // MARK: - Public API

    /// Access the underlying download service
    /// Provides low-level download operations
    public var service: DownloadService {
        return downloadService
    }

    // MARK: - Convenience Methods

    /// Download a model
    /// - Parameter model: The model to download
    /// - Returns: A download task tracking the download
    /// - Throws: An error if download setup fails
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        logger.info("Starting download for model: \(model.id)")
        return try await downloadService.downloadModel(model)
    }

    /// Cancel a download
    /// - Parameter taskId: The ID of the task to cancel
    public func cancelDownload(taskId: String) {
        logger.info("Cancelling download task: \(taskId)")
        downloadService.cancelDownload(taskId: taskId)
    }

    // MARK: - Strategy Management

    /// Register a custom download strategy (if using AlamofireDownloadService)
    /// - Parameter strategy: The download strategy to register
    public func registerStrategy(_ strategy: DownloadStrategy) {
        if let alamofireService = downloadService as? AlamofireDownloadService {
            alamofireService.registerStrategy(strategy)
            logger.info("Registered custom download strategy")
        } else {
            logger.warning("Cannot register strategy: service does not support custom strategies")
        }
    }

    /// Refresh strategies (no-op as strategies are now managed by C++ layer)
    public func refreshStrategies() {
        // Download strategies are now managed by the C++ download manager
        logger.debug("Download strategies are managed by C++ layer")
    }
}
