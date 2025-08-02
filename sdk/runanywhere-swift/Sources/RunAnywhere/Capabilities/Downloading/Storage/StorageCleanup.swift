import Foundation

/// Handles cleanup of download-related storage
public class StorageCleanup {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "StorageCleanup")

    private var cacheDirectory: URL {
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Public Methods

    /// Clean up old download caches
    public func cleanupOldDownloads(olderThan days: Int = 7) async {
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))

        await cleanupDirectory(cacheDirectory, olderThan: cutoffDate)

        // Also clean temp directory
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunAnywhereDownloads", isDirectory: true)
        await cleanupDirectory(tempDirectory, olderThan: cutoffDate)
    }

    /// Clean up partial downloads
    public func cleanupPartialDownloads() async {
        let downloadsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads/Temp", isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            if file.pathExtension == "tmp" || file.pathExtension == "partial" {
                do {
                    try fileManager.removeItem(at: file)
                    logger.debug("Removed partial download: \(file.lastPathComponent)")
                } catch {
                    logger.error("Failed to remove partial download: \(error)")
                }
            }
        }
    }

    /// Calculate total cache size
    public func calculateCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        let directories = [
            cacheDirectory,
            FileManager.default.temporaryDirectory.appendingPathComponent("RunAnywhereDownloads")
        ]

        for directory in directories {
            totalSize += calculateDirectorySize(directory)
        }

        return totalSize
    }

    /// Clear all download caches
    public func clearAllCaches() async throws {
        let directories = [
            cacheDirectory,
            FileManager.default.temporaryDirectory.appendingPathComponent("RunAnywhereDownloads")
        ]

        for directory in directories {
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
                logger.info("Cleared cache directory: \(directory.path)")
            }
        }

        // Recreate directories
        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Perform automatic cleanup based on available space
    public func performAutomaticCleanup(
        targetFreeSpace: Int64,
        preserveRecent: Bool = true
    ) async throws {
        let currentFreeSpace = getAvailableSpace()

        guard currentFreeSpace < targetFreeSpace else {
            logger.debug("Sufficient free space available, no cleanup needed")
            return
        }

        let spaceNeeded = targetFreeSpace - currentFreeSpace
        logger.info("Need to free up \(formatBytes(spaceNeeded)) of space")

        // Start with old downloads
        await cleanupOldDownloads(olderThan: 1)

        // Check if we have enough space now
        if getAvailableSpace() >= targetFreeSpace {
            return
        }

        // Clean partial downloads
        await cleanupPartialDownloads()

        // Check again
        if getAvailableSpace() >= targetFreeSpace {
            return
        }

        // If still not enough, clear all caches
        if !preserveRecent {
            try await clearAllCaches()
        }
    }

    // MARK: - Private Methods

    private func cleanupDirectory(_ directory: URL, olderThan date: Date) async {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < date {
                do {
                    try fileManager.removeItem(at: file)
                    logger.debug("Removed old file: \(file.lastPathComponent)")
                } catch {
                    logger.error("Failed to remove file: \(error)")
                }
            }
        }
    }

    private func calculateDirectorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attributes.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    private func getAvailableSpace() -> Int64 {
        do {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsURL.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            logger.error("Failed to get available space: \(error)")
            return 0
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
