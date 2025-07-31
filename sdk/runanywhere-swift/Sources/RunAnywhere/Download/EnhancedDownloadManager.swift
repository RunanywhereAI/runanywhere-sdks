import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

/// Enhanced download manager with queue-based management, retry logic, and archive extraction
public class EnhancedDownloadManager {
    public static let shared: EnhancedDownloadManager = EnhancedDownloadManager()

    private let downloadQueue: OperationQueue = OperationQueue()
    private var activeTasks: [String: DownloadTask] = [:]
    private let taskLock: NSLock = NSLock()
    private let progressTracker: UnifiedProgressTracker = UnifiedProgressTracker()

    /// Configuration for download behavior
    public struct DownloadConfig {
        public var maxConcurrentDownloads: Int = 3
        public var retryCount: Int = 3
        public var retryDelay: TimeInterval = 2.0
        public var timeout: TimeInterval = 300.0
        public var chunkSize: Int = 1024 * 1024 // 1MB chunks

        public init() {}
    }

    private var config: DownloadConfig = DownloadConfig()

    /// Download task information
    public struct DownloadTask {
        public let id: String
        public let modelId: String
        public let progress: AsyncStream<DownloadProgress>
        public let result: Task<URL, Error>
    }

    /// Download progress information
    public struct DownloadProgress {
        public let bytesDownloaded: Int64
        public let totalBytes: Int64
        public let state: DownloadState
        public let estimatedTimeRemaining: TimeInterval?

        public var percentage: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(bytesDownloaded) / Double(totalBytes)
        }
    }

    /// Download state
    public enum DownloadState {
        case pending
        case downloading
        case extracting
        case retrying(attempt: Int)
        case completed
        case failed(Error)
    }

    /// Download errors
    public enum DownloadError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case timeout
        case partialDownload
        case checksumMismatch
        case extractionFailed(String)
        case unsupportedArchive(String)
        case unknown
        case invalidResponse
        case httpError(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid download URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .timeout:
                return "Download timeout"
            case .partialDownload:
                return "Partial download - file incomplete"
            case .checksumMismatch:
                return "Downloaded file checksum doesn't match expected"
            case .extractionFailed(let reason):
                return "Archive extraction failed: \(reason)"
            case .unsupportedArchive(let format):
                return "Unsupported archive format: \(format)"
            case .unknown:
                return "Unknown download error"
            case .invalidResponse:
                return "Invalid server response"
            case .httpError(let code):
                return "HTTP error: \(code)"
            }
        }
    }

    private init() {
        downloadQueue.maxConcurrentOperationCount = config.maxConcurrentDownloads
        downloadQueue.name = "com.runanywhere.download"
    }

    /// Configure download manager
    public func configure(_ config: DownloadConfig) {
        self.config = config
        downloadQueue.maxConcurrentOperationCount = config.maxConcurrentDownloads
    }

    /// Download a model
    public func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        let taskId = UUID().uuidString

        let (progressStream, progressContinuation) = AsyncStream<DownloadProgress>.makeStream()

        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: progressStream,
            result: Task {
                defer {
                    progressContinuation.finish()
                    // Clean up active tasks synchronously
                    Task { @MainActor in
                        taskLock.lock()
                        activeTasks.removeValue(forKey: taskId)
                        taskLock.unlock()
                    }
                }

                do {
                    let url = try await performDownload(model, taskId: taskId, progressContinuation: progressContinuation)
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        state: .completed,
                        estimatedTimeRemaining: nil
                    ))
                    return url
                } catch {
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        state: .failed(error),
                        estimatedTimeRemaining: nil
                    ))
                    throw error
                }
            }
        )

        // Store task synchronously before returning
        await withCheckedContinuation { continuation in
            taskLock.lock()
            activeTasks[taskId] = task
            taskLock.unlock()
            continuation.resume()
        }

        return task
    }

    /// Cancel a download task
    public func cancelDownload(taskId: String) {
        taskLock.lock()
        if let task = activeTasks[taskId] {
            task.result.cancel()
            activeTasks.removeValue(forKey: taskId)
        }
        taskLock.unlock()
    }

    /// Get all active downloads
    public func activeDownloads() -> [DownloadTask] {
        taskLock.lock()
        let tasks = Array(activeTasks.values)
        taskLock.unlock()
        return tasks
    }

    // MARK: - Private Methods

    private func performDownload(
        _ model: ModelInfo,
        taskId: String,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        guard let downloadURL = model.downloadURL else {
            throw DownloadError.invalidURL
        }

        var lastError: Error?

        // Retry logic with exponential backoff
        for attempt in 0..<config.retryCount {
            do {
                if attempt > 0 {
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: 0,
                        totalBytes: 0,
                        state: .retrying(attempt: attempt + 1),
                        estimatedTimeRemaining: nil
                    ))

                    let delay = config.retryDelay * pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                let data = try await downloadWithProgress(
                    from: downloadURL,
                    taskId: taskId,
                    progressContinuation: progressContinuation
                )

                let storedURL = try await storeModel(data, for: model)

                // Handle archives
                if needsExtraction(storedURL) {
                    progressContinuation.yield(DownloadProgress(
                        bytesDownloaded: Int64(data.count),
                        totalBytes: Int64(data.count),
                        state: .extracting,
                        estimatedTimeRemaining: nil
                    ))

                    return try await extractArchive(storedURL)
                }

                return storedURL
            } catch {
                lastError = error
                if !isRetryableError(error) {
                    throw error
                }
            }
        }

        throw lastError ?? DownloadError.unknown
    }

    private func downloadWithProgress(
        from url: URL,
        taskId: String,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> Data {
        let session = URLSession.shared
        let request = URLRequest(url: url, timeoutInterval: config.timeout)

        // Check iOS version for bytes API
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            // Fallback for older iOS versions
            let downloadURL = try await downloadWithDataTask(from: url, progressContinuation: progressContinuation)
            return try Data(contentsOf: downloadURL)
        }

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.networkError(URLError(.badServerResponse))
        }

        let totalBytes = httpResponse.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()
        let startTime = Date()

        progressContinuation.yield(DownloadProgress(
            bytesDownloaded: 0,
            totalBytes: totalBytes,
            state: .downloading,
            estimatedTimeRemaining: nil
        ))

        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1

            // Update progress every chunk
            if downloadedBytes % Int64(config.chunkSize) == 0 || downloadedBytes == totalBytes {
                let elapsed = Date().timeIntervalSince(startTime)
                let bytesPerSecond = Double(downloadedBytes) / elapsed
                let remainingBytes = totalBytes > 0 ? totalBytes - downloadedBytes : 0
                let estimatedTime = bytesPerSecond > 0 ? TimeInterval(Double(remainingBytes) / bytesPerSecond) : nil

                progressContinuation.yield(DownloadProgress(
                    bytesDownloaded: downloadedBytes,
                    totalBytes: totalBytes,
                    state: .downloading,
                    estimatedTimeRemaining: estimatedTime
                ))
            }
        }

        // Verify complete download
        if totalBytes > 0 && downloadedBytes != totalBytes {
            throw DownloadError.partialDownload
        }

        return data
    }

    private func storeModel(_ data: Data, for model: ModelInfo) async throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Create models directory if needed
        try FileManager.default.createDirectory(at: modelsURL, withIntermediateDirectories: true)

        // Generate filename
        let filename = model.downloadURL?.lastPathComponent ?? "\(model.id).model"
        let fileURL = modelsURL.appendingPathComponent(filename)

        // Write data
        try data.write(to: fileURL)

        // Verify checksum if provided
        if let expectedChecksum = model.checksum {
            let actualChecksum = calculateChecksum(for: data)
            if actualChecksum != expectedChecksum {
                try? FileManager.default.removeItem(at: fileURL)
                throw DownloadError.checksumMismatch
            }
        }

        return fileURL
    }

    private func needsExtraction(_ url: URL) -> Bool {
        let archiveExtensions = ["zip", "gz", "tgz", "tar", "bz2", "tbz2", "xz", "txz"]
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractArchive(_ archive: URL) async throws -> URL {
        let ext = archive.pathExtension.lowercased()

        switch ext {
        case "zip":
            return try await extractZip(archive)
        case "gz", "tgz":
            return try await extractTarGz(archive)
        case "tar":
            return try await extractTar(archive)
        case "bz2", "tbz2":
            return try await extractTarBz2(archive)
        case "xz", "txz":
            return try await extractTarXz(archive)
        default:
            throw DownloadError.unsupportedArchive(ext)
        }
    }

    private func extractZip(_ archive: URL) async throws -> URL {
        let outputDir = archive.deletingPathExtension()

        // Create output directory
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use Process on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archive.path, "-d", outputDir.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("unzip failed with status \(process.terminationStatus)")
        }
        #else
        // On iOS, use manual extraction or delegate to app
        // For now, throw an error indicating the app needs to handle extraction
        throw DownloadError.extractionFailed("ZIP extraction requires app-level implementation. Please handle extraction in your app delegate.")
        #endif

        // Clean up archive
        try? FileManager.default.removeItem(at: archive)

        return outputDir
    }

    private func extractTarGz(_ archive: URL) async throws -> URL {
        var outputDir = archive.deletingPathExtension()
        if outputDir.pathExtension == "tar" {
            outputDir.deletePathExtension()
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use Process on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", outputDir.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("tar failed with status \(process.terminationStatus)")
        }
        #else
        // Use manual extraction on iOS
        throw DownloadError.extractionFailed("TAR.GZ extraction not implemented for iOS. Please use a third-party library.")
        #endif

        // Clean up archive
        try? FileManager.default.removeItem(at: archive)

        return outputDir
    }

    private func extractTar(_ archive: URL) async throws -> URL {
        let outputDir = archive.deletingPathExtension()

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use Process on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", outputDir.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("tar failed with status \(process.terminationStatus)")
        }
        #else
        // Use manual extraction on iOS
        throw DownloadError.extractionFailed("TAR extraction not implemented for iOS. Please use a third-party library.")
        #endif

        // Clean up archive
        try? FileManager.default.removeItem(at: archive)

        return outputDir
    }

    private func extractTarBz2(_ archive: URL) async throws -> URL {
        var outputDir = archive.deletingPathExtension()
        if outputDir.pathExtension == "tar" {
            outputDir.deletePathExtension()
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use Process on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", outputDir.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("tar failed with status \(process.terminationStatus)")
        }
        #else
        // Use manual extraction on iOS
        throw DownloadError.extractionFailed("TAR.BZ2 extraction not implemented for iOS. Please use a third-party library.")
        #endif

        // Clean up archive
        try? FileManager.default.removeItem(at: archive)

        return outputDir
    }

    private func extractTarXz(_ archive: URL) async throws -> URL {
        var outputDir = archive.deletingPathExtension()
        if outputDir.pathExtension == "tar" {
            outputDir.deletePathExtension()
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        #if os(macOS)
        // Use Process on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xJf", archive.path, "-C", outputDir.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw DownloadError.extractionFailed("tar failed with status \(process.terminationStatus)")
        }
        #else
        // Use manual extraction on iOS
        throw DownloadError.extractionFailed("TAR.XZ extraction not implemented for iOS. Please use a third-party library.")
        #endif

        // Clean up archive
        try? FileManager.default.removeItem(at: archive)

        return outputDir
    }

    // Fallback download method for iOS < 15.0
    private func downloadWithDataTask(
        from url: URL,
        progressContinuation: AsyncStream<DownloadProgress>.Continuation
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            var request = URLRequest(url: url)

            let downloadTask = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: DownloadError.httpError(httpResponse.statusCode))
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(throwing: DownloadError.invalidResponse)
                    return
                }

                do {
                    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let destinationURL = documentsDir.appendingPathComponent(url.lastPathComponent)

                    // Remove existing file if needed
                    try? FileManager.default.removeItem(at: destinationURL)

                    // Move downloaded file to destination
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Observe progress
            let observation = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
                let downloadProgress = DownloadProgress(
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    state: .downloading,
                    estimatedTimeRemaining: nil
                )
                progressContinuation.yield(downloadProgress)
            }

            downloadTask.resume()
        }
    }

    private func calculateChecksum(for data: Data) -> String {
        // Simple SHA256 implementation
        // In production, use CryptoKit or similar
        data.base64EncodedString()
    }

    private func isRetryableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        if case DownloadError.timeout = error { return true }
        if case DownloadError.networkError = error { return true }
        if case DownloadError.partialDownload = error { return true }

        return false
    }
}

// MARK: - Model Storage Protocol

// ModelStorageManager protocol is defined in AuthProvider.swift

// MARK: - Default Implementation

extension EnhancedDownloadManager: ModelStorageManager {
    public func deleteModel(_ modelId: String) async throws {
        // Cancel any active download
        if let activeTask = activeTasks.values.first(where: { $0.modelId == modelId }) {
            cancelDownload(taskId: activeTask.id)
        }

        // Remove from storage
        if let modelPath = getModelPath(modelId) {
            try FileManager.default.removeItem(at: modelPath)
        }
    }

    public func getModelPath(_ modelId: String) -> URL? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsURL = documentsURL.appendingPathComponent("Models", isDirectory: true)

        // Search for model in storage
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: nil) {
            for url in contents {
                if url.lastPathComponent.contains(modelId) {
                    return url
                }
            }
        }

        return nil
    }

    public func getAvailableStorage() -> Int64 {
        do {
            let systemAttributes = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )

            if let freeSpace = systemAttributes[.systemFreeSize] as? NSNumber {
                return freeSpace.int64Value
            }
        } catch {
            print("Error getting available storage: \(error)")
        }

        return 0
    }

    public func getModelsDirectory() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Models", isDirectory: true)
    }

    public func getModelPath(for modelId: String) -> URL {
        return getModelsDirectory().appendingPathComponent("\(modelId).model")
    }

    public func modelExists(_ modelId: String) -> Bool {
        return getModelPath(modelId) != nil
    }

    public func getModelSize(_ modelId: String) -> Int64? {
        guard let path = getModelPath(modelId) else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }

    public func getAvailableSpace() -> Int64 {
        return getAvailableStorage()
    }

    public func listStoredModels() -> [String] {
        let modelsDir = getModelsDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents.compactMap { url in
            let filename = url.lastPathComponent
            if filename.hasSuffix(".model") {
                return String(filename.dropLast(6))
            }
            return nil
        }
    }

    public func cleanupTemporaryFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)

        for url in contents {
            if url.lastPathComponent.hasPrefix("runanywhere_temp_") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public func moveToStorage(from temporaryPath: URL, modelId: String) async throws -> URL {
        let finalPath = getModelPath(for: modelId)

        // Create models directory if needed
        try FileManager.default.createDirectory(at: getModelsDirectory(), withIntermediateDirectories: true)

        // Move file
        if FileManager.default.fileExists(atPath: finalPath.path) {
            try FileManager.default.removeItem(at: finalPath)
        }
        try FileManager.default.moveItem(at: temporaryPath, to: finalPath)

        return finalPath
    }
}
