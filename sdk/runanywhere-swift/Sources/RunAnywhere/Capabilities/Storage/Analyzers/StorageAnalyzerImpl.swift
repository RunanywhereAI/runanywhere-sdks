import Foundation

/// Implementation of storage analysis operations
public class StorageAnalyzerImpl: StorageAnalyzer {

    // MARK: - Properties

    private let logger = SDKLogger(category: "StorageAnalyzer")
    private let fileManager = FileManager.default

    // Storage thresholds
    private let warningThreshold: Double = 0.90 // 90% full
    private let criticalThreshold: Double = 0.95 // 95% full

    // MARK: - Initialization

    public init() {}

    // MARK: - StorageAnalyzer Protocol

    public func analyzeStorage() async -> StorageInfo {
        let deviceInfo = await getDeviceStorageInfo()
        let appInfo = await getAppStorageInfo()
        let modelInfo = await getModelStorageUsage()
        let models = await scanForModels()
        let cacheSize = await calculateCacheSize()

        return StorageInfo(
            appStorage: appInfo,
            deviceStorage: deviceInfo,
            modelStorage: modelInfo,
            cacheSize: cacheSize,
            storedModels: models,
            lastUpdated: Date()
        )
    }

    public func getModelStorageUsage() async -> ModelStorageInfo {
        let modelsDirectory = getModelsDirectory()
        let modelFiles = await scanForModels()

        var totalSize: Int64 = 0
        var modelsByFramework: [LLMFramework: [StoredModel]] = [:]

        for model in modelFiles {
            totalSize += model.size

            if let framework = model.framework {
                if modelsByFramework[framework] == nil {
                    modelsByFramework[framework] = []
                }
                modelsByFramework[framework]?.append(model)
            }
        }

        return ModelStorageInfo(
            totalSize: totalSize,
            modelCount: modelFiles.count,
            modelsByFramework: modelsByFramework,
            largestModel: modelFiles.max { $0.size < $1.size }
        )
    }

    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double) -> StorageAvailability {
        let requiredSpace = Int64(Double(modelSize) * safetyMargin)
        let deviceInfo = DeviceStorageMonitor().getDeviceStorageInfo()

        let available = deviceInfo.freeSpace > requiredSpace
        let warning = Double(deviceInfo.usedSpace + requiredSpace) / Double(deviceInfo.totalSpace) > warningThreshold

        return StorageAvailability(
            isAvailable: available,
            requiredSpace: requiredSpace,
            availableSpace: deviceInfo.freeSpace,
            hasWarning: warning,
            recommendation: available ? nil : "Free up at least \(ByteCountFormatter.string(fromByteCount: requiredSpace - deviceInfo.freeSpace, countStyle: .memory))"
        )
    }

    public func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation] {
        var recommendations: [StorageRecommendation] = []

        // Check device storage
        let deviceUsageRatio = Double(storageInfo.deviceStorage.usedSpace) / Double(storageInfo.deviceStorage.totalSpace)

        if deviceUsageRatio > criticalThreshold {
            recommendations.append(
                StorageRecommendation(
                    type: .critical,
                    message: "Device storage critically low",
                    action: "Delete unused apps or media to free space"
                )
            )
        } else if deviceUsageRatio > warningThreshold {
            recommendations.append(
                StorageRecommendation(
                    type: .warning,
                    message: "Device storage running low",
                    action: "Consider freeing up space"
                )
            )
        }

        // Check cache size
        if storageInfo.cacheSize > 1_000_000_000 { // 1GB
            recommendations.append(
                StorageRecommendation(
                    type: .suggestion,
                    message: "Large cache size detected",
                    action: "Run cache cleanup to free \(ByteCountFormatter.string(fromByteCount: storageInfo.cacheSize, countStyle: .memory))"
                )
            )
        }

        // Check for old models
        let oldModels = storageInfo.storedModels.filter { model in
            guard let lastUsed = model.lastUsed else { return false }
            return Date().timeIntervalSince(lastUsed) > 30 * 24 * 60 * 60 // 30 days
        }

        if !oldModels.isEmpty {
            let totalSize = oldModels.reduce(0) { $0 + $1.size }
            recommendations.append(
                StorageRecommendation(
                    type: .suggestion,
                    message: "\(oldModels.count) models unused for 30+ days",
                    action: "Delete to free \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .memory))"
                )
            )
        }

        return recommendations
    }

    public func calculateSize(at url: URL) async throws -> Int64 {
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

    // MARK: - Internal Methods

    private func getDeviceStorageInfo() async -> DeviceStorageInfo {
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            let totalSpace = systemAttributes[.systemSize] as? Int64 ?? 0
            let freeSpace = systemAttributes[.systemFreeSize] as? Int64 ?? 0

            return DeviceStorageInfo(
                totalSpace: totalSpace,
                freeSpace: freeSpace,
                usedSpace: totalSpace - freeSpace
            )
        } catch {
            logger.error("Failed to get device storage info: \(error)")
            return DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0)
        }
    }

    private func getAppStorageInfo() async -> AppStorageInfo {
        do {
            return try await calculateAppStorageUsage()
        } catch {
            logger.error("Failed to get app storage info: \(error)")
            return AppStorageInfo(
                documentsSize: 0,
                cacheSize: 0,
                appSupportSize: 0,
                totalSize: 0
            )
        }
    }

    func calculateAppStorageUsage() async throws -> AppStorageInfo {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let documentsSize = try await calculateSize(at: documentsURL)
        let cacheSize = try await calculateSize(at: cacheURL)
        let appSupportSize = try await calculateSize(at: appSupportURL)

        return AppStorageInfo(
            documentsSize: documentsSize,
            cacheSize: cacheSize,
            appSupportSize: appSupportSize,
            totalSize: documentsSize + cacheSize + appSupportSize
        )
    }

    func calculateCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        for cacheURL in getCacheDirectories() {
            do {
                let size = try await calculateSize(at: cacheURL)
                totalSize += size
            } catch {
                logger.error("Failed to calculate cache size at \(cacheURL.path): \(error)")
            }
        }

        return totalSize
    }

    func scanForModels() async -> [StoredModel] {
        let directory = getModelsDirectory()
        var models: [StoredModel] = []

        guard fileManager.fileExists(atPath: directory.path) else { return models }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
            )

            for url in contents {
                // Check if it's a model file based on extension
                let format = ModelFormat(rawValue: url.pathExtension) ?? .unknown

                let resourceValues = try url.resourceValues(
                    forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
                )

                let model = StoredModel(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url,
                    size: Int64(resourceValues.fileSize ?? 0),
                    format: format,
                    framework: extractFramework(from: url),
                    createdDate: resourceValues.creationDate ?? Date(),
                    lastUsed: resourceValues.contentModificationDate
                )

                models.append(model)
            }
        } catch {
            logger.error("Failed to scan for models: \(error)")
        }

        return models
    }

    // MARK: - Private Methods

    private func getModelsDirectory() -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models")
    }

    private func getCacheDirectories() -> [URL] {
        var directories: [URL] = []

        if let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cacheURL)
        }

        let tempURL = fileManager.temporaryDirectory
        directories.append(tempURL)

        return directories
    }

    private func extractFramework(from url: URL) -> LLMFramework? {
        // Try to extract framework from directory structure or filename
        let pathComponents = url.pathComponents

        for component in pathComponents {
            if let framework = LLMFramework(rawValue: component) {
                return framework
            }
        }

        // Try format-based inference
        switch ModelFormat(rawValue: url.pathExtension) {
        case .mlmodel, .mlpackage:
            return .coreML
        case .tflite:
            return .tensorFlowLite
        case .gguf, .ggml:
            return .llamaCpp
        case .onnx, .ort:
            return .onnx
        case .pte:
            return .execuTorch
        default:
            return nil
        }
    }
}
