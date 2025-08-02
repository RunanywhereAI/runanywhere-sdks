import Foundation

/// Calculates various storage metrics
public class StorageCalculator {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logger = SDKLogger(category: "StorageCalculator")

    // MARK: - Public Methods

    /// Calculate directory size recursively
    public func calculateDirectorySize(at url: URL) async throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false {
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
        }

        return totalSize
    }

    /// Calculate file size
    public func calculateFileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Calculate total size of files with specific extensions
    public func calculateSizeForExtensions(_ extensions: [String], in directory: URL) async throws -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if extensions.contains(fileURL.pathExtension.lowercased()) {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if resourceValues.isDirectory == false {
                        totalSize += Int64(resourceValues.fileSize ?? 0)
                    }
                }
            }
        }

        return totalSize
    }

    /// Calculate model sizes by framework
    public func calculateModelSizesByFramework(models: [StoredModel]) -> [(framework: LLMFramework, size: Int64, count: Int)] {
        var sizesByFramework: [LLMFramework: (size: Int64, count: Int)] = [:]

        for model in models {
            if let framework = model.framework {
                var current = sizesByFramework[framework] ?? (size: 0, count: 0)
                current.size += model.size
                current.count += 1
                sizesByFramework[framework] = current
            }
        }

        return sizesByFramework.map { (framework: $0.key, size: $0.value.size, count: $0.value.count) }
            .sorted { $0.size > $1.size }
    }

    /// Calculate average model size
    public func calculateAverageModelSize(models: [StoredModel]) -> Int64 {
        guard !models.isEmpty else { return 0 }
        let totalSize = models.reduce(0) { $0 + $1.size }
        return totalSize / Int64(models.count)
    }

    /// Estimate download size with overhead
    public func estimateDownloadSize(baseSize: Int64, compressionRatio: Double = 0.7) -> Int64 {
        // Estimate compressed download size
        let compressedSize = Int64(Double(baseSize) * compressionRatio)
        // Add 10% overhead for headers, retries, etc.
        return Int64(Double(compressedSize) * 1.1)
    }

    /// Calculate storage required for model with safety margin
    public func calculateRequiredStorage(modelSize: Int64, extractionNeeded: Bool = false) -> Int64 {
        var required = modelSize

        if extractionNeeded {
            // Need space for both compressed and extracted files temporarily
            required *= 2
        }

        // Add 20% safety margin
        return Int64(Double(required) * 1.2)
    }
}
