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
            currentFile = file.path.components(separatedBy: "/").last ?? file.path
            
            // Calculate overall progress
            let fileProgress = Double(index) / Double(files.count)
            currentProgress = fileProgress
            progress(fileProgress, "Downloading \(currentFile)...")
            
            try await downloadFile(
                repoId: repoId,
                filePath: file.path,
                fileInfo: file,
                baseDirectory: directoryPath,
                to: destinationURL
            )
            
            completedFiles = index + 1
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
        
        // Download the file
        var request = URLRequest(url: downloadURL)
        
        // Add auth if available
        if let hfAuth = HuggingFaceAuthService.shared.currentCredentials {
            request.setValue(hfAuth.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Move to destination
        if FileManager.default.fileExists(atPath: fileDestination.path) {
            try FileManager.default.removeItem(at: fileDestination)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: fileDestination)
        print("✅ Saved to \(fileDestination.path)")
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
        
        // Download using the directory downloader
        let finalURL = try await HuggingFaceDirectoryDownloader.shared.downloadDirectory(
            repoId: repoId,
            directoryPath: directoryPath,
            to: destinationURL
        ) { downloadProgress, status in
            // Convert to DownloadProgress format
            let downloadProgressInfo = DownloadProgress(
                bytesWritten: Int64(downloadProgress * 1_000_000_000), // Approximate
                totalBytes: 1_000_000_000, // Approximate
                fractionCompleted: downloadProgress,
                estimatedTimeRemaining: nil,
                downloadSpeed: 0
            )
            
            Task { @MainActor in
                self.activeDownloads[modelInfo.id] = downloadProgressInfo
            }
            
            progress(downloadProgressInfo)
        }
        
        return finalURL
    }
}