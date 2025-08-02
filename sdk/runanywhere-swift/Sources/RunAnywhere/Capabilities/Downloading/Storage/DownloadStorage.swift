import Foundation

/// Manages storage for downloaded models
public class DownloadStorage {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "DownloadStorage")

    private var downloadsDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    private var tempDirectory: URL {
        return downloadsDirectory.appendingPathComponent("Temp", isDirectory: true)
    }

    // MARK: - Initialization

    public init() {
        setupDirectories()
    }

    // MARK: - Public Methods

    /// Get temporary file URL for download
    public func temporaryURL(for model: ModelInfo) -> URL {
        let filename = "\(model.id)_\(UUID().uuidString).tmp"
        return tempDirectory.appendingPathComponent(filename)
    }

    /// Move downloaded file to final location
    public func finalizeDownload(from tempURL: URL, for model: ModelInfo) throws -> URL {
        let filename = model.downloadURL?.lastPathComponent ?? "\(model.id).model"
        let finalURL = downloadsDirectory.appendingPathComponent(filename)

        // Remove existing file if needed
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        // Move temp file to final location
        try fileManager.moveItem(at: tempURL, to: finalURL)

        logger.info("Finalized download for model \(model.id) at: \(finalURL.path)")

        return finalURL
    }

    /// Check if partial download exists
    public func partialDownloadExists(for model: ModelInfo) -> (exists: Bool, url: URL?, size: Int64?) {
        let tempFiles = (try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for tempFile in tempFiles {
            if tempFile.lastPathComponent.contains(model.id) {
                if let attributes = try? fileManager.attributesOfItem(atPath: tempFile.path),
                   let size = attributes[.size] as? Int64 {
                    return (true, tempFile, size)
                }
            }
        }

        return (false, nil, nil)
    }

    /// Clean up temporary files
    public func cleanupTempFiles(olderThan date: Date = Date().addingTimeInterval(-86400)) {
        guard let tempFiles = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in tempFiles {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < date {
                try? fileManager.removeItem(at: file)
                logger.debug("Cleaned up old temp file: \(file.lastPathComponent)")
            }
        }
    }

    /// Get available storage space
    public func availableSpace() -> Int64 {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: downloadsDirectory.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            logger.error("Failed to get available space: \(error)")
            return 0
        }
    }

    /// Verify storage space for download
    public func verifySpace(required: Int64) -> Bool {
        let available = availableSpace()
        // Require 10% buffer
        let requiredWithBuffer = Int64(Double(required) * 1.1)
        return available >= requiredWithBuffer
    }

    // MARK: - Private Methods

    private func setupDirectories() {
        do {
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to setup directories: \(error)")
        }
    }
}
