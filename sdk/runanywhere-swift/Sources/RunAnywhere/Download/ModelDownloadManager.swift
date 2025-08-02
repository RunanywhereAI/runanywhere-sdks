import Foundation
import Alamofire
import Files

/// Simple download manager using Alamofire for model downloads
public class ModelDownloadManager {
    private let storageManager: SimpleModelStorageManager
    private var activeDownloads: [String: DownloadRequest] = [:]

    /// Download progress information
    public struct DownloadProgress {
        public let bytesDownloaded: Int64
        public let totalBytes: Int64
        public let percentage: Double

        public init(bytesDownloaded: Int64, totalBytes: Int64, percentage: Double) {
            self.bytesDownloaded = bytesDownloaded
            self.totalBytes = totalBytes
            self.percentage = percentage
        }
    }

    /// Download result
    public struct DownloadResult {
        public let modelPath: URL
        public let framework: SimpleModelStorageManager.Framework
        public let modelId: String

        public init(modelPath: URL, framework: SimpleModelStorageManager.Framework, modelId: String) {
            self.modelPath = modelPath
            self.framework = framework
            self.modelId = modelId
        }
    }

    /// Initialize download manager
    public init() throws {
        self.storageManager = try SimpleModelStorageManager()
    }

    /// Download a model from URL
    public func downloadModel(
        url: URL,
        modelId: String,
        framework: SimpleModelStorageManager.Framework,
        progressHandler: ((DownloadProgress) -> Void)? = nil
    ) async throws -> DownloadResult {

        // Get destination folder
        let modelFolder = try storageManager.getModelFolder(
            framework: framework,
            modelId: modelId
        )

        // Determine filename from URL
        let filename = url.lastPathComponent
        let destinationFile: File
        if let existingFile = try? modelFolder.file(named: filename) {
            destinationFile = existingFile
        } else {
            destinationFile = try modelFolder.createFile(named: filename)
        }

        // Download using Alamofire
        let destination: DownloadRequest.Destination = { _, _ in
            return (destinationFile.url, [.removePreviousFile])
        }

        let request = AF.download(url, to: destination)
            .downloadProgress { progress in
                let downloadProgress = DownloadProgress(
                    bytesDownloaded: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    percentage: progress.fractionCompleted
                )
                progressHandler?(downloadProgress)
            }

        // Store active download
        activeDownloads[modelId] = request

        // Wait for download to complete
        let response = await request.serializingDownloadedFileURL().response

        // Remove from active downloads
        activeDownloads.removeValue(forKey: modelId)

        switch response.result {
        case .success(let fileURL):
            // Handle archives if needed
            if needsExtraction(fileURL) {
                let extractedURL = try await extractArchive(fileURL, in: modelFolder)
                return DownloadResult(
                    modelPath: extractedURL,
                    framework: framework,
                    modelId: modelId
                )
            }

            return DownloadResult(
                modelPath: fileURL,
                framework: framework,
                modelId: modelId
            )

        case .failure(let error):
            throw error
        }
    }

    /// Cancel an active download
    public func cancelDownload(modelId: String) {
        activeDownloads[modelId]?.cancel()
        activeDownloads.removeValue(forKey: modelId)
    }

    /// Get list of active downloads
    public func getActiveDownloads() -> [String] {
        return Array(activeDownloads.keys)
    }

    /// Check if extraction is needed
    private func needsExtraction(_ url: URL) -> Bool {
        let archiveExtensions = ["zip", "gz", "tar", "tgz"]
        return archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// Extract archive to destination folder
    private func extractArchive(_ archiveURL: URL, in folder: Folder) async throws -> URL {
        let fileExtension = archiveURL.pathExtension.lowercased()

        switch fileExtension {
        case "zip":
            return try await extractZip(archiveURL, in: folder)
        case "gz", "tgz":
            return try await extractTarGz(archiveURL, in: folder)
        case "tar":
            return try await extractTar(archiveURL, in: folder)
        default:
            throw NSError(
                domain: "ModelDownload",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported archive format: \(fileExtension)"]
            )
        }
    }

    /// Extract ZIP archive
    private func extractZip(_ archiveURL: URL, in folder: Folder) async throws -> URL {
        #if os(macOS)
        // Use unzip command on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", folder.url.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ModelDownload",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "ZIP extraction failed"]
            )
        }

        // Delete the archive after extraction
        try? FileManager.default.removeItem(at: archiveURL)

        // Return the first model file found
        for file in folder.files {
            if file.extension != "zip" {
                return file.url
            }
        }

        throw NSError(
            domain: "ModelDownload",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "No model file found after extraction"]
        )

        #else
        // For iOS, we need a different approach or third-party library
        throw NSError(
            domain: "ModelDownload",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "ZIP extraction not implemented for iOS. Consider using ZIPFoundation library."]
        )
        #endif
    }

    /// Extract TAR.GZ archive
    private func extractTarGz(_ archiveURL: URL, in folder: Folder) async throws -> URL {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", folder.url.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ModelDownload",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "TAR.GZ extraction failed"]
            )
        }

        // Delete the archive after extraction
        try? FileManager.default.removeItem(at: archiveURL)

        // Return the first model file found
        for file in folder.files {
            if !["gz", "tgz", "tar"].contains(file.extension ?? "") {
                return file.url
            }
        }

        throw NSError(
            domain: "ModelDownload",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "No model file found after TAR.GZ extraction"]
        )

        #else
        throw NSError(
            domain: "ModelDownload",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "TAR.GZ extraction not implemented for iOS"]
        )
        #endif
    }

    /// Extract TAR archive
    private func extractTar(_ archiveURL: URL, in folder: Folder) async throws -> URL {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archiveURL.path, "-C", folder.url.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ModelDownload",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "TAR extraction failed"]
            )
        }

        // Delete the archive after extraction
        try? FileManager.default.removeItem(at: archiveURL)

        // Return the first model file found
        for file in folder.files {
            if file.extension != "tar" {
                return file.url
            }
        }

        throw NSError(
            domain: "ModelDownload",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "No model file found after TAR extraction"]
        )

        #else
        throw NSError(
            domain: "ModelDownload",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "TAR extraction not implemented for iOS"]
        )
        #endif
    }
}
