//
//  HuggingFaceDirectoryDownloader.swift
//  RunAnywhereAI
//
//  Downloads directory-based models (like .mlpackage) from Hugging Face
//

import Foundation

// MARK: - HF File Info

struct HFFileInfo: Codable {
    let type: String
    let oid: String
    let size: Int
    let path: String
    let lfs: LFSInfo?
    
    struct LFSInfo: Codable {
        let oid: String
        let size: Int
        let pointerSize: Int
    }
}

// MARK: - HF Directory Downloader

@MainActor
class HuggingFaceDirectoryDownloader: ObservableObject {
    static let shared = HuggingFaceDirectoryDownloader()
    
    @Published var isDownloading = false
    @Published var currentProgress: Double = 0
    @Published var currentFile: String = ""
    @Published var totalFiles: Int = 0
    @Published var completedFiles: Int = 0
    @Published var currentFileProgress: Double = 0
    @Published var currentFileSize: String = ""
    @Published var isDownloadingFile: Bool = false
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Download a directory-based model (like .mlpackage) from Hugging Face
    func downloadDirectory(
        repoId: String,
        directoryPath: String,
        to destinationURL: URL,
        progress: @escaping (Double, String) -> Void
    ) async throws -> URL {
        isDownloading = true
        currentProgress = 0
        completedFiles = 0
        
        defer {
            isDownloading = false
        }
        
        // List all files in the directory
        let files = try await listFiles(repoId: repoId, path: directoryPath)
        totalFiles = files.count
        
        print("📦 Found \(files.count) files in \(directoryPath)")
        print("📁 Destination: \(destinationURL.path)")
        
        // Download each file
        for (index, file) in files.enumerated() {
            // Extract just the filename for display
            let fileName = file.path.components(separatedBy: "/").last ?? file.path
            currentFile = fileName
            
            // Calculate overall progress
            let fileProgress = Double(index) / Double(files.count)
            currentProgress = fileProgress
            
            // Create a detailed status message
            let fileSize = formatBytes(file.lfs?.size ?? file.size)
            let status = "Downloading \(fileName) (\(fileSize))"
            progress(fileProgress, status)
            
            try await downloadFile(
                repoId: repoId,
                filePath: file.path,
                fileInfo: file,
                baseDirectory: directoryPath,
                to: destinationURL
            )
            
            completedFiles = index + 1
            
            // Update progress after file completion
            let completedProgress = Double(completedFiles) / Double(files.count)
            currentProgress = completedProgress
            progress(completedProgress, "Completed \(completedFiles)/\(files.count) files")
        }
        
        currentProgress = 1.0
        progress(1.0, "Download complete")
        
        // Return the path to the .mlpackage directory
        let mlpackageURL = destinationURL.appendingPathComponent(directoryPath)
        return mlpackageURL
    }
    
    // MARK: - Private Methods
    
    private func listFiles(repoId: String, path: String) async throws -> [HFFileInfo] {
        var allFiles: [HFFileInfo] = []
        
        // First, get files in the root directory
        let rootFiles = try await listFilesAtPath(repoId: repoId, path: path)
        
        // Process each item
        for item in rootFiles {
            if item.type == "file" {
                allFiles.append(item)
            } else if item.type == "directory" {
                // Recursively get files from subdirectories
                let subFiles = try await listFiles(repoId: repoId, path: item.path)
                allFiles.append(contentsOf: subFiles)
            }
        }
        
        return allFiles
    }
    
    private func listFilesAtPath(repoId: String, path: String) async throws -> [HFFileInfo] {
        let urlString = "https://huggingface.co/api/models/\(repoId)/tree/main/\(path)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth if available
        if let hfAuth = HuggingFaceAuthService.shared.currentCredentials {
            request.setValue(hfAuth.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let files = try JSONDecoder().decode([HFFileInfo].self, from: data)
        return files
    }
    
    private func downloadFile(
        repoId: String,
        filePath: String,
        fileInfo: HFFileInfo,
        baseDirectory: String,
        to destinationURL: URL
    ) async throws {
        // Construct download URL
        let downloadURLString = "https://huggingface.co/\(repoId)/resolve/main/\(filePath)"
        guard let downloadURL = URL(string: downloadURLString) else {
            throw URLError(.badURL)
        }
        
        // The file path includes the base directory, so we need the full path structure
        // For example: filePath = "OpenELM-270M-Instruct-128-float32.mlpackage/Data/com.apple.CoreML/model.mlmodel"
        // We want to save it to: destinationURL/OpenELM-270M-Instruct-128-float32.mlpackage/Data/com.apple.CoreML/model.mlmodel
        let fileDestination = destinationURL.appendingPathComponent(filePath)
        
        // Create parent directory if needed
        let parentDir = fileDestination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        print("⬇️ Downloading \(filePath) (\(formatBytes(fileInfo.lfs?.size ?? fileInfo.size)))")
        print("   Saving to: \(fileDestination.path)")
        
        // Download the file with timeout and retry
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 120 // 2 minutes timeout per file
        
        // Add auth if available
        if let hfAuth = HuggingFaceAuthService.shared.currentCredentials {
            request.setValue(hfAuth.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        
        // Create a custom session with better configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300 // 5 minutes total
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        var lastError: Error?
        var retryCount = 0
        let maxRetries = 3
        
        // Update file download state
        await MainActor.run {
            self.isDownloadingFile = true
            self.currentFileProgress = 0
            self.currentFileSize = formatBytes(fileInfo.lfs?.size ?? fileInfo.size)
        }
        
        // Retry logic for network failures
        while retryCount < maxRetries {
            do {
                // Create download task to track progress
                let downloadTask = session.downloadTask(with: request)
                
                // Track progress using delegate pattern would be ideal, but for now use async download
                let (tempURL, response) = try await session.download(for: request)
                
                // Simulate progress for now (since URLSession async doesn't provide progress)
                await MainActor.run {
                    self.currentFileProgress = 1.0
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if statusCode == 404 {
                        throw URLError(.fileDoesNotExist)
                    }
                    throw URLError(.badServerResponse)
                }
                
                // Success - move to next part of the function
                lastError = nil
                
                // Move to destination
                if FileManager.default.fileExists(atPath: fileDestination.path) {
                    try FileManager.default.removeItem(at: fileDestination)
                }
                
                try FileManager.default.moveItem(at: tempURL, to: fileDestination)
                print("✅ Saved to \(fileDestination.path)")
                
                // Reset file download state
                await MainActor.run {
                    self.isDownloadingFile = false
                    self.currentFileProgress = 0
                }
                
                return
                
            } catch {
                lastError = error
                retryCount += 1
                
                if retryCount < maxRetries {
                    print("⚠️ Download failed for \(filePath), retry \(retryCount)/\(maxRetries): \(error)")
                    // Wait before retry with exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                }
            }
        }
        
        // All retries failed
        throw lastError ?? URLError(.unknown)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Extension for ModelDownloadManager

extension ModelDownloadManager {
    /// Download a directory-based model from Hugging Face
    func downloadHuggingFaceDirectory(
        _ modelInfo: ModelInfo,
        to directory: URL,
        progress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        guard let downloadURL = modelInfo.downloadURL else {
            throw ModelDownloadError.noDownloadURL
        }
        
        // Extract repo ID and directory path from URL
        // Example: https://huggingface.co/corenet-community/coreml-OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-128-float32.mlpackage
        let urlComponents = downloadURL.absoluteString.components(separatedBy: "/")
        
        guard urlComponents.count >= 7,
              urlComponents[2] == "huggingface.co" else {
            throw ModelDownloadError.noDownloadURL
        }
        
        let repoId = "\(urlComponents[3])/\(urlComponents[4])"
        let directoryPath = urlComponents[7...].joined(separator: "/")
        
        print("🤗 Downloading HF directory: \(repoId) - \(directoryPath)")
        
        // The destination should be the directory itself, not directory + directoryPath
        // directory is already the Models/Core ML folder
        let destinationURL = directory
        
        // Track download start time
        downloadStartTimes[modelInfo.id] = Date()
        
        // Download using the directory downloader
        let downloader = HuggingFaceDirectoryDownloader.shared
        
        // Observe the downloader's progress for better UI updates
        var lastUpdateTime = Date()
        var downloadedBytes: Int64 = 0
        let estimatedTotalBytes = parseSize(modelInfo.size)
        
        let finalURL = try await downloader.downloadDirectory(
            repoId: repoId,
            directoryPath: directoryPath,
            to: destinationURL
        ) { downloadProgress, status in
            let now = Date()
            let timeDiff = now.timeIntervalSince(lastUpdateTime)
            
            // Calculate approximate bytes based on progress
            downloadedBytes = Int64(downloadProgress * Double(estimatedTotalBytes))
            
            // Calculate speed
            let elapsed = now.timeIntervalSince(self.downloadStartTimes[modelInfo.id] ?? now)
            let speed = elapsed > 0 ? Double(downloadedBytes) / elapsed : 0
            
            // Calculate time remaining
            let remaining = estimatedTotalBytes - downloadedBytes
            let timeRemaining = speed > 0 ? TimeInterval(Double(remaining) / speed) : nil
            
            // Create detailed progress info
            let downloadProgressInfo = DownloadProgress(
                bytesWritten: downloadedBytes,
                totalBytes: estimatedTotalBytes,
                fractionCompleted: downloadProgress,
                estimatedTimeRemaining: timeRemaining,
                downloadSpeed: speed
            )
            
            Task { @MainActor in
                self.activeDownloads[modelInfo.id] = downloadProgressInfo
                
                // Store current file info for UI display
                if !status.isEmpty && status != "Download complete" {
                    self.currentStep = status
                }
            }
            
            progress(downloadProgressInfo)
            lastUpdateTime = now
        }
        
        return finalURL
    }
}