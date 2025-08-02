import Foundation

/// Implementation of storage cleanup operations
public class StorageCleanerImpl: StorageCleaner {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "StorageCleaner")
    private let analyzer = StorageAnalyzerImpl()

    // MARK: - StorageCleaner Protocol

    public func cleanupCache() async throws -> CleanupResult {
        let startSize = await analyzer.calculateCacheSize()

        // Clean various cache locations
        let cacheURLs = getCacheDirectories()
        var cleanedSize: Int64 = 0
        var errors: [Error] = []

        for cacheURL in cacheURLs {
            do {
                let cleaned = try await cleanDirectory(at: cacheURL)
                cleanedSize += cleaned
            } catch {
                errors.append(error)
                logger.error("Failed to clean cache at \(cacheURL.path): \(error)")
            }
        }

        let endSize = await analyzer.calculateCacheSize()

        return CleanupResult(
            startSize: startSize,
            endSize: endSize,
            freedSpace: cleanedSize,
            errors: errors
        )
    }

    public func deleteModel(at path: URL) async throws -> Int64 {
        let size = try await analyzer.calculateSize(at: path)

        try fileManager.removeItem(at: path)
        logger.info("Deleted model at \(path.path), freed \(ByteCountFormatter.string(fromByteCount: size, countStyle: .memory))")

        return size
    }

    public func cleanDirectory(at url: URL) async throws -> Int64 {
        var freedSpace: Int64 = 0

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        for fileURL in contents {
            do {
                let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                try fileManager.removeItem(at: fileURL)
                freedSpace += Int64(size)
            } catch {
                // Continue with other files
                logger.warning("Failed to delete cache file at \(fileURL.path): \(error)")
            }
        }

        return freedSpace
    }

    public func getCacheDirectories() -> [URL] {
        var directories: [URL] = []

        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cacheURL)
        }

        let tempURL = fileManager.temporaryDirectory
        directories.append(tempURL)

        return directories
    }

    // MARK: - Additional Methods

    /// Clean old models that haven't been used recently
    public func cleanOldModels(olderThan days: Int) async throws -> CleanupResult {
        let models = await analyzer.scanForModels()
        let cutoffDate = Date().addingTimeInterval(-Double(days * 86400))

        var freedSpace: Int64 = 0
        var errors: [Error] = []

        for model in models {
            if let lastUsed = model.lastUsed, lastUsed < cutoffDate {
                do {
                    let size = try await deleteModel(at: model.path)
                    freedSpace += size
                } catch {
                    errors.append(error)
                }
            }
        }

        return CleanupResult(
            startSize: 0,
            endSize: 0,
            freedSpace: freedSpace,
            errors: errors
        )
    }

    /// Clean temporary download files
    public func cleanTempDownloads() async throws -> Int64 {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempDownloadsURL = documentsURL.appendingPathComponent("Downloads/Temp", isDirectory: true)

        guard fileManager.fileExists(atPath: tempDownloadsURL.path) else { return 0 }

        return try await cleanDirectory(at: tempDownloadsURL)
    }
}
