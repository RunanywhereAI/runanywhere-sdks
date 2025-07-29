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
    case authRequired

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
        case .authRequired:
            return "Authentication required. Please configure your API credentials in Settings."
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
    @Published var currentStep: String = ""

    // MARK: - Private Properties

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressHandlers: [String: (DownloadProgress) -> Void] = [:]
    private var completionHandlers: [String: (Result<URL, Error>) -> Void] = [:]
    internal var downloadStartTimes: [String: Date] = [:]
    private var lastBytesWritten: [String: Int64] = [:]
    private var downloadInfoMap: [String: ModelInfo] = [:]

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
        _ modelInfo: ModelInfo,
        progress: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Clean up any existing model files first if re-downloading
        cleanupExistingModel(modelInfo)
        
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
        let downloadId = modelInfo.id
        progressHandlers[downloadId] = progress
        completionHandlers[downloadId] = completion
        downloadStartTimes[downloadId] = Date()
        downloadInfoMap[downloadId] = modelInfo

        // Create download request with proper configuration
        guard let downloadURL = modelInfo.downloadURL else {
            completion(.failure(ModelDownloadError.noDownloadURL))
            return
        }
        
        // Check if this model requires special download handling
        let formatManager = ModelFormatManager.shared
        if formatManager.requiresSpecialDownload(downloadURL, format: modelInfo.format) {
            
            // Check authentication first if required
            if modelInfo.requiresAuth {
                if HuggingFaceAuthService.shared.currentCredentials == nil {
                    completion(.failure(ModelDownloadError.authRequired))
                    return
                }
            }
            
            // Use the HuggingFace directory downloader for directory-based models
            Task {
                do {
                    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let modelsDirectory = documentsURL.appendingPathComponent("Models").appendingPathComponent(modelInfo.framework.directoryName)
                    
                    let finalURL = try await downloadHuggingFaceDirectory(
                        modelInfo,
                        to: modelsDirectory,
                        progress: progress
                    )
                    
                    completion(.success(finalURL))
                } catch {
                    completion(.failure(error))
                }
            }
            return
        }
        var request = URLRequest(url: downloadURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3600 // 1 hour
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Add authentication headers if needed
        if modelInfo.requiresAuth {
            if downloadURL.host?.contains("kaggle") == true {
                // Kaggle authentication
                if let kaggleAuth = KaggleAuthService.shared.currentCredentials {
                    request.setValue(kaggleAuth.authorizationHeader, forHTTPHeaderField: "Authorization")
                } else {
                    completion(.failure(ModelDownloadError.authRequired))
                    return
                }
            } else if downloadURL.host?.contains("huggingface") == true {
                // Hugging Face authentication
                if let hfAuth = HuggingFaceAuthService.shared.currentCredentials {
                    request.setValue(hfAuth.authorizationHeader, forHTTPHeaderField: "Authorization")
                } else {
                    completion(.failure(ModelDownloadError.authRequired))
                    return
                }
            }
        }
        
        // Create download task
        let task = session.downloadTask(with: request)
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
            // Convert ModelInfo to ModelInfo
            guard let downloadURL = modelInfo.downloadURL else {
                continuation.resume(throwing: ModelDownloadError.noDownloadURL)
                return
            }

            downloadModel(modelInfo, progress: progress) { result in
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
    
    private func cleanupExistingModel(_ modelInfo: ModelInfo) {
        // Determine the framework from the model info
        let framework = modelInfo.framework
        
        // Get the models directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDirectory = documentsURL.appendingPathComponent("Models")
        
        // Check framework-specific directory
        let frameworkDir = modelsDirectory.appendingPathComponent(framework.directoryName)
        let modelPath = frameworkDir.appendingPathComponent(modelInfo.name)
        
        if FileManager.default.fileExists(atPath: modelPath.path) {
            do {
                try FileManager.default.removeItem(at: modelPath)
                print("Cleaned up existing model at: \(modelPath.path)")
            } catch {
                print("Failed to cleanup existing model: \(error)")
            }
        }
        
        // Also check root models directory (legacy)
        let rootModelPath = modelsDirectory.appendingPathComponent(modelInfo.name)
        if FileManager.default.fileExists(atPath: rootModelPath.path) {
            do {
                try FileManager.default.removeItem(at: rootModelPath)
                print("Cleaned up legacy model at: \(rootModelPath.path)")
            } catch {
                print("Failed to cleanup legacy model: \(error)")
            }
        }
        
        // Clean up any partial downloads
        let downloadsDir = documentsURL.appendingPathComponent("Downloads")
        if FileManager.default.fileExists(atPath: downloadsDir.path) {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.lastPathComponent.contains(modelInfo.id) {
                        try FileManager.default.removeItem(at: file)
                        print("Cleaned up partial download: \(file.lastPathComponent)")
                    }
                }
            } catch {
                print("Failed to cleanup partial downloads: \(error)")
            }
        }
    }
    

    private func moveAndProcessModel(
        from tempURL: URL,
        modelInfo: ModelInfo,
        to directory: URL
    ) async throws -> URL {
        // Create directory if needed with proper attributes
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )

        let downloadInfo = ModelURLRegistry.shared.getModelInfo(id: modelInfo.id)
        let fileName = downloadInfo?.name ?? modelInfo.name
        var finalURL = directory.appendingPathComponent(fileName)

        // Process based on file type
        if downloadInfo?.requiresUnzip == true {
            finalURL = try await unzipModel(from: tempURL, to: directory)
        } else {
            // Move file with better error handling
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            
            // Try to move first, fallback to copy if move fails
            do {
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
            } catch {
                print("Move failed, trying copy instead: \(error.localizedDescription)")
                try FileManager.default.copyItem(at: tempURL, to: finalURL)
                
                // Clean up temp file after successful copy
                try? FileManager.default.removeItem(at: tempURL)
            }
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

        // Handle tar.gz files
        if zipURL.pathExtension == "gz" || zipURL.lastPathComponent.contains(".tar.gz") {
            // Extract tar.gz files
            let extractedURL = try extractTarGz(at: zipURL, to: directory)
            return extractedURL
        }

        // For other file types, just copy them
        let destinationURL = directory.appendingPathComponent(zipURL.lastPathComponent)
        try FileManager.default.copyItem(at: zipURL, to: destinationURL)
        return destinationURL
    }

    private func extractTarGz(at sourceURL: URL, to directory: URL) throws -> URL {
        print("⚠️ MLX model extraction required")
        print("Model file: \(sourceURL.lastPathComponent)")
        
        // For now, on iOS we'll need to handle this differently
        // The proper solution would be to:
        // 1. Use a library like libarchive or GzipSwift
        // 2. Or pre-extract models server-side
        // 3. Or use a different format like zip
        
        // Create a directory for the model based on the tar.gz filename
        let modelName = sourceURL.deletingPathExtension().deletingPathExtension().lastPathComponent
        let modelDir = directory.appendingPathComponent(modelName)
        
        // Create the directory
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        // For now, copy the tar.gz file to indicate it needs manual extraction
        let needsExtractionURL = modelDir.appendingPathComponent("NEEDS_EXTRACTION.tar.gz")
        try FileManager.default.copyItem(at: sourceURL, to: needsExtractionURL)
        
        // Create a README file explaining the issue
        let readmeContent = """
        MLX Model Extraction Required
        ============================
        
        This MLX model (\(modelName)) was downloaded as a tar.gz archive but could not be 
        automatically extracted on iOS.
        
        To use this model:
        1. The model needs to be extracted to reveal:
           - config.json (model configuration)
           - *.safetensors files (model weights)
           - tokenizer files
        
        2. Current options:
           - Use a Mac to extract and transfer files
           - Wait for app update with extraction support
           - Use a different model format
        
        File: \(sourceURL.lastPathComponent)
        Location: \(needsExtractionURL.path)
        """
        
        let readmeURL = modelDir.appendingPathComponent("README.txt")
        try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        print("Created placeholder directory at: \(modelDir.path)")
        print("Tar.gz extraction is not yet supported on iOS")
        print("Consider using a different model format or pre-extracted models")
        
        return modelDir
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

    internal func parseSize(_ sizeString: String) -> Int64 {
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
        downloadInfoMap.removeValue(forKey: downloadId)

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
        // Handle file operations synchronously to prevent deletion
        let taskIdentifier = downloadTask.taskIdentifier
        
        // Create a safe location immediately
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsDir = documentsDir.appendingPathComponent("Downloads", isDirectory: true)
        let tempFileName = "download_\(taskIdentifier)_\(UUID().uuidString).tmp"
        let safeURL = downloadsDir.appendingPathComponent(tempFileName)
        
        var moveError: Error?
        var moveSuccess = false
        
        do {
            // Create downloads directory if needed
            try FileManager.default.createDirectory(
                at: downloadsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Move file immediately to prevent deletion
            try FileManager.default.moveItem(at: location, to: safeURL)
            moveSuccess = true
            
            print("Successfully moved download to: \(safeURL.path)")
        } catch {
            moveError = error
            print("Failed to move downloaded file: \(error)")
            print("Source: \(location.path)")
            print("Source exists: \(FileManager.default.fileExists(atPath: location.path))")
            print("Destination: \(safeURL.path)")
            print("Downloads dir: \(downloadsDir.path)")
            
            // Try to get more details about the error
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
        }
        
        // Now notify on main actor
        Task { @MainActor in
            guard let modelId = self.downloadTasks.first(where: { $0.value.taskIdentifier == taskIdentifier })?.key else {
                // Clean up the file if we can't find the model ID
                if moveSuccess {
                    try? FileManager.default.removeItem(at: safeURL)
                }
                return
            }
            
            if moveSuccess {
                print("Download completed for model: \(modelId)")
                print("File saved to: \(safeURL.path)")
                print("File exists: \(FileManager.default.fileExists(atPath: safeURL.path))")
                
                // If we have download info, rename the file to its proper name
                var finalURL = safeURL
                if let downloadInfo = self.downloadInfoMap[modelId] {
                    let properFileName = downloadInfo.name
                    let properFileURL = downloadsDir.appendingPathComponent(properFileName)
                    
                    do {
                        // Remove existing file if it exists
                        if FileManager.default.fileExists(atPath: properFileURL.path) {
                            try FileManager.default.removeItem(at: properFileURL)
                        }
                        
                        // Rename temp file to proper name
                        try FileManager.default.moveItem(at: safeURL, to: properFileURL)
                        finalURL = properFileURL
                        print("Renamed downloaded file to: \(properFileName)")
                    } catch {
                        print("Failed to rename file to proper name: \(error)")
                        // Continue with temp name if rename fails
                    }
                }
                
                self.completionHandlers[modelId]?(.success(finalURL))
                self.cleanup(downloadId: modelId)
            } else {
                let error = moveError ?? ModelDownloadError.networkError(
                    NSError(domain: "ModelDownload", code: -1, 
                           userInfo: [NSLocalizedDescriptionKey: "Failed to save downloaded file"])
                )
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
        let taskIdentifier = downloadTask.taskIdentifier
        
        Task { @MainActor in
            guard let modelId = self.downloadTasks.first(where: { $0.value.taskIdentifier == taskIdentifier })?.key else {
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
        guard let downloadTask = task as? URLSessionDownloadTask else {
            return
        }
        
        let taskIdentifier = downloadTask.taskIdentifier
        
        Task { @MainActor in
            guard let modelId = self.downloadTasks.first(where: { $0.value.taskIdentifier == taskIdentifier })?.key else {
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
