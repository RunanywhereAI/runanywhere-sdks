import Foundation
import Combine
import CryptoKit
import Compression
import ZIPFoundation

// MARK: - Download Error

enum ModelDownloadError: LocalizedError {
    case noDownloadURL
    case insufficientStorage(required: Int64, available: Int64)
    case networkError(Error)
    case invalidChecksum
    case unzipFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDownloadURL:
            return "No download URL available for this model"
        case .insufficientStorage(let required, let available):
            let formatter = ByteCountFormatter()
            return "Not enough storage. Required: \(formatter.string(fromByteCount: required)), Available: \(formatter.string(fromByteCount: available))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidChecksum:
            return "Downloaded file is corrupted (checksum mismatch)"
        case .unzipFailed:
            return "Failed to extract model files"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

// MARK: - Download Progress

struct DownloadProgress {
    let bytesWritten: Int64
    let totalBytes: Int64
    let fractionCompleted: Double
    let estimatedTimeRemaining: TimeInterval?
    let downloadSpeed: Double // bytes per second
}

// MARK: - Model Download Manager

@MainActor
class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    // MARK: - Published Properties

    @Published var activeDownloads: [String: DownloadProgress] = [:]
    @Published var downloadQueue: [ModelInfo] = []
    @Published var isDownloading = false

    // MARK: - Private Properties

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressHandlers: [String: (DownloadProgress) -> Void] = [:]
    private var completionHandlers: [String: (Result<URL, Error>) -> Void] = [:]
    private var downloadStartTimes: [String: Date] = [:]
    private var lastBytesWritten: [String: Int64] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600 // 1 hour for large models
        config.allowsCellularAccess = false // Don't use cellular for large downloads
        config.isDiscretionary = true // Allow system to schedule downloads
        config.sessionSendsLaunchEvents = true // Background downloads

        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.runanywhereai.modeldownloads")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true

        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Public Methods

    /// Download a model with progress tracking
    func downloadModel(
        _ downloadInfo: ModelDownloadInfo,
        progress: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Check storage before starting
        // Estimate size from filename if not provided
        let estimatedSize: Int64 = 100_000_000 // Default 100MB
        if !hasEnoughStorage(for: estimatedSize) {
            let available = getAvailableStorage()
            completion(.failure(ModelDownloadError.insufficientStorage(
                required: estimatedSize,
                available: available
            )))
            return
        }

        // Setup download
        let downloadId = downloadInfo.id
        progressHandlers[downloadId] = progress
        completionHandlers[downloadId] = completion
        downloadStartTimes[downloadId] = Date()

        // Create download task
        let task = session.downloadTask(with: downloadInfo.url)
        downloadTasks[downloadId] = task

        // Start download
        task.resume()
        isDownloading = true

        // Add to active downloads
        activeDownloads[downloadId] = DownloadProgress(
            bytesWritten: 0,
            totalBytes: estimatedSize,
            fractionCompleted: 0,
            estimatedTimeRemaining: nil,
            downloadSpeed: 0
        )
    }

    /// Download a model to a specific directory
    func downloadModel(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // Convert ModelInfo to ModelDownloadInfo
            guard let downloadURL = modelInfo.downloadURL else {
                continuation.resume(throwing: ModelDownloadError.noDownloadURL)
                return
            }

            let downloadInfo = ModelDownloadInfo(
                id: modelInfo.id,
                name: modelInfo.name,
                url: downloadURL,
                sha256: nil,
                requiresUnzip: false,
                requiresAuth: false
            )

            downloadModel(downloadInfo, progress: progress) { result in
                switch result {
                case .success(let tempURL):
                    Task {
                        do {
                            let finalURL = try await self.moveAndProcessModel(
                                from: tempURL,
                                modelInfo: modelInfo,
                                to: directory
                            )
                            continuation.resume(returning: finalURL)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Batch download multiple models
    func downloadModels(
        _ models: [ModelInfo],
        progress: @escaping (String, DownloadProgress) -> Void,
        completion: @escaping ([String: Result<URL, Error>]) -> Void
    ) {
        var results: [String: Result<URL, Error>] = [:]
        let group = DispatchGroup()

        for model in models {
            group.enter()
            // Get download info from registry
            guard let downloadInfo = ModelURLRegistry.shared.getModelInfo(id: model.id) else {
                results[model.id] = .failure(ModelDownloadError.noDownloadURL)
                group.leave()
                continue
            }

            downloadModel(downloadInfo, progress: { downloadProgress in
                progress(model.id, downloadProgress)
            }) { result in
                results[model.id] = result
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results)
        }
    }

    /// Cancel a download
    func cancelDownload(_ modelId: String) {
        downloadTasks[modelId]?.cancel()
        cleanup(downloadId: modelId)

        if let handler = completionHandlers[modelId] {
            handler(.failure(ModelDownloadError.cancelled))
        }
    }

    /// Cancel all downloads
    func cancelAllDownloads() {
        for (modelId, _) in downloadTasks {
            cancelDownload(modelId)
        }
    }

    /// Pause a download
    func pauseDownload(_ modelId: String) {
        downloadTasks[modelId]?.suspend()
    }

    /// Resume a paused download
    func resumeDownload(_ modelId: String) {
        downloadTasks[modelId]?.resume()
    }

    // MARK: - Tokenizer Downloads

    /// Download tokenizer files for a model
    func downloadTokenizers(
        for modelId: String,
        to directory: URL
    ) async throws {
        let tokenizerFiles = ModelURLRegistry.shared.getTokenizerFiles(for: modelId)

        for file in tokenizerFiles {
            let (localURL, _) = try await session.download(from: file.url)
            let destinationURL = directory.appendingPathComponent(file.name)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: localURL, to: destinationURL)
        }
    }

    // MARK: - Private Methods

    private func moveAndProcessModel(
        from tempURL: URL,
        modelInfo: ModelInfo,
        to directory: URL
    ) async throws -> URL {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let downloadInfo = ModelURLRegistry.shared.getModelInfo(id: modelInfo.id)
        let fileName = downloadInfo?.name ?? modelInfo.name
        var finalURL = directory.appendingPathComponent(fileName)

        // Process based on file type
        if downloadInfo?.requiresUnzip == true {
            finalURL = try await unzipModel(from: tempURL, to: directory)
        } else {
            // Move file
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
        }

        // Verify checksum if available
        if let expectedHash = downloadInfo?.sha256 {
            try await verifyChecksum(of: finalURL, expectedHash: expectedHash)
        }

        // Download tokenizers if it's a model that needs them
        if shouldDownloadTokenizers(for: modelInfo) {
            try await downloadTokenizers(for: modelInfo.id, to: directory)
        }

        return finalURL
    }

    private func unzipModel(from zipURL: URL, to directory: URL) async throws -> URL {
        // Use ZIPFoundation for proper unzipping
        if zipURL.pathExtension == "zip" {
            do {
                try FileManager.default.unzipItem(at: zipURL, to: directory)

                // Find the extracted content
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                // Return the first extracted item (could be file or directory)
                if let firstItem = contents.first {
                    return firstItem
                } else {
                    return directory
                }
            } catch {
                print("ZIP extraction failed: \(error)")
                throw ModelDownloadError.unzipFailed
            }
        }

        // Handle tar.gz files - for now, just return the original file
        // In a production app, you might want to add support for tar.gz extraction
        if zipURL.pathExtension == "gz" || zipURL.lastPathComponent.contains(".tar.gz") {
            let destinationURL = directory.appendingPathComponent(zipURL.lastPathComponent)
            try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            return destinationURL
        }

        // For other file types, just copy them
        let destinationURL = directory.appendingPathComponent(zipURL.lastPathComponent)
        try FileManager.default.copyItem(at: zipURL, to: destinationURL)
        return destinationURL
    }

    private func verifyChecksum(of fileURL: URL, expectedHash: String) async throws {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        guard hashString == expectedHash else {
            throw ModelDownloadError.invalidChecksum
        }
    }

    private func shouldDownloadTokenizers(for model: ModelInfo) -> Bool {
        // Determine if this model type typically needs separate tokenizer files
        switch model.framework {
        case .coreML, .mlx, .onnxRuntime:
            return true
        case .llamaCpp, .tensorFlowLite:
            return false // Usually embedded in model
        default:
            return false
        }
    }

    private func parseSize(_ sizeString: String) -> Int64 {
        // Try common formats
        if sizeString.hasSuffix("GB") {
            let value = Double(sizeString.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(value * 1_000_000_000)
        } else if sizeString.hasSuffix("MB") {
            let value = Double(sizeString.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(value * 1_000_000)
        }

        return 1_000_000_000 // Default 1GB
    }

    private func hasEnoughStorage(for size: Int64) -> Bool {
        let available = getAvailableStorage()
        return available > size * 2 // Require 2x space for safety
    }

    private func getAvailableStorage() -> Int64 {
        do {
            let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    private func cleanup(downloadId: String) {
        downloadTasks.removeValue(forKey: downloadId)
        progressHandlers.removeValue(forKey: downloadId)
        completionHandlers.removeValue(forKey: downloadId)
        downloadStartTimes.removeValue(forKey: downloadId)
        lastBytesWritten.removeValue(forKey: downloadId)
        activeDownloads.removeValue(forKey: downloadId)

        if downloadTasks.isEmpty {
            isDownloading = false
        }
    }
}

// MARK: - URLSession Delegate

extension ModelDownloadManager: @preconcurrency URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            guard let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key else {
                return
            }

            // Move to temporary location to prevent deletion
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(UUID().uuidString)

            do {
                try FileManager.default.moveItem(at: location, to: tempURL)

                self.completionHandlers[modelId]?(.success(tempURL))
                self.cleanup(downloadId: modelId)
            } catch {
                self.completionHandlers[modelId]?(.failure(error))
                self.cleanup(downloadId: modelId)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key else {
                return
            }

            let fractionCompleted = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0

            // Calculate download speed
            let now = Date()
            let elapsed = now.timeIntervalSince(downloadStartTimes[modelId] ?? now)
            let speed = elapsed > 0 ? Double(totalBytesWritten) / elapsed : 0

            // Estimate time remaining
            let bytesRemaining = totalBytesExpectedToWrite - totalBytesWritten
            let estimatedTime = speed > 0 ? TimeInterval(Double(bytesRemaining) / speed) : nil

            let progress = DownloadProgress(
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite,
                fractionCompleted: fractionCompleted,
                estimatedTimeRemaining: estimatedTime,
                downloadSpeed: speed
            )

            self.activeDownloads[modelId] = progress
            self.progressHandlers[modelId]?(progress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            guard let downloadTask = task as? URLSessionDownloadTask,
                  let modelId = downloadTasks.first(where: { $0.value == downloadTask })?.key else {
                return
            }

            if let error = error {
                self.completionHandlers[modelId]?(.failure(ModelDownloadError.networkError(error)))
                self.cleanup(downloadId: modelId)
            }
        }
    }
}

// MARK: - Convenience Extensions

extension ModelDownloadManager {
    /// Get a formatted string for download progress
    static func formatProgress(_ progress: DownloadProgress) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary

        let downloaded = formatter.string(fromByteCount: progress.bytesWritten)
        let total = formatter.string(fromByteCount: progress.totalBytes)
        let percent = Int(progress.fractionCompleted * 100)

        var result = "\(downloaded) / \(total) (\(percent)%)"

        if progress.downloadSpeed > 0 {
            let speed = formatter.string(fromByteCount: Int64(progress.downloadSpeed))
            result += " - \(speed)/s"
        }

        if let timeRemaining = progress.estimatedTimeRemaining {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.hour, .minute, .second]
            if let timeString = formatter.string(from: timeRemaining) {
                result += " - \(timeString) remaining"
            }
        }

        return result
    }
}
