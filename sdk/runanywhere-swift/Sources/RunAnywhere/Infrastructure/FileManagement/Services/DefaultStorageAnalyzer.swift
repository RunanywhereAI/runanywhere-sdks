import Foundation

/// Default implementation of StorageAnalyzer protocol
public class DefaultStorageAnalyzer: StorageAnalyzer {
    private let fileManager: SimplifiedFileManager
    private let modelRegistry: ModelRegistry
    private let logger = SDKLogger(category: "DefaultStorageAnalyzer")

    public init(fileManager: SimplifiedFileManager, modelRegistry: ModelRegistry) {
        self.fileManager = fileManager
        self.modelRegistry = modelRegistry
    }

    /// Analyze overall storage situation
    public func analyzeStorage() async -> StorageInfo {
        // Get device storage info
        let deviceStorage = getDeviceStorageInfo()

        // Get model storage usage
        let modelStorage = await getModelStorageUsage()

        // Get app storage info
        let totalAppSize = fileManager.getTotalStorageSize()
        let appStorage = AppStorageInfo(
            documentsSize: totalAppSize,
            cacheSize: 0, // Could be enhanced to track cache separately
            appSupportSize: 0,
            totalSize: totalAppSize
        )

        // Get stored models list
        let storedModels = await getStoredModelsList()

        return StorageInfo(
            appStorage: appStorage,
            deviceStorage: deviceStorage,
            modelStorage: modelStorage,
            cacheSize: 0,
            storedModels: storedModels,
            lastUpdated: Date()
        )
    }

    /// Get model storage usage information
    public func getModelStorageUsage() async -> ModelStorageInfo {
        let modelStorageSize = fileManager.getModelStorageSize()
        let storedModelsData = fileManager.getAllStoredModels()

        // Count models by framework
        var modelsByFramework: [LLMFramework: [StoredModel]] = [:]
        let storedModels = await getStoredModelsList()

        for model in storedModels {
            if let framework = model.framework {
                modelsByFramework[framework, default: []].append(model)
            }
        }

        // Find largest model
        let largestModel = storedModels.max(by: { $0.size < $1.size })

        return ModelStorageInfo(
            totalSize: modelStorageSize,
            modelCount: storedModels.count,
            modelsByFramework: modelsByFramework,
            largestModel: largestModel
        )
    }

    /// Check storage availability for a model
    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 0.1) -> StorageAvailability {
        let availableSpace = fileManager.getAvailableSpace()
        let requiredSpace = Int64(Double(modelSize) * (1 + safetyMargin))

        let isAvailable = availableSpace > requiredSpace
        let hasWarning = availableSpace < requiredSpace * 2 // Warn if less than 2x space available

        let recommendation: String?
        if !isAvailable {
            let shortfall = requiredSpace - availableSpace
            let formatter = ByteCountFormatter()
            formatter.countStyle = .memory
            recommendation = "Need \(formatter.string(fromByteCount: shortfall)) more space. Clear cache or remove unused models."
        } else if hasWarning {
            recommendation = "Storage space is getting low. Consider clearing cache after download."
        } else {
            recommendation = nil
        }

        return StorageAvailability(
            isAvailable: isAvailable,
            requiredSpace: requiredSpace,
            availableSpace: availableSpace,
            hasWarning: hasWarning,
            recommendation: recommendation
        )
    }

    /// Get storage recommendations
    public func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation] {
        var recommendations: [StorageRecommendation] = []

        // Check if storage is low
        let freeSpace = storageInfo.deviceStorage.freeSpace
        let totalSpace = storageInfo.deviceStorage.totalSpace

        if totalSpace > 0 {
            let freePercentage = Double(freeSpace) / Double(totalSpace)

            if freePercentage < 0.1 {
                recommendations.append(
                    StorageRecommendation(
                        type: .warning,
                        message: "Low storage space. Clear cache to free up space.",
                        action: "Clear Cache"
                    )
                )
            }

            if freePercentage < 0.05 {
                recommendations.append(
                    StorageRecommendation(
                        type: .critical,
                        message: "Critical storage shortage. Consider removing unused models.",
                        action: "Delete Models"
                    )
                )
            }
        }

        // Check for old or unused models
        if storageInfo.storedModels.count > 5 {
            recommendations.append(
                StorageRecommendation(
                    type: .suggestion,
                    message: "Multiple models stored. Consider removing models you don't use.",
                    action: "Review Models"
                )
            )
        }

        return recommendations
    }

    /// Calculate size at URL
    public func calculateSize(at url: URL) async throws -> Int64 {
        // Check if it's a file or directory
        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: url)

        guard exists else {
            throw RunAnywhereError.modelNotFound("File not found at path: \(url.path)")
        }

        if isDirectory {
            // Use centralized directory size calculation
            return FileOperationsUtilities.calculateDirectorySize(at: url)
        } else {
            // Get file size
            return FileOperationsUtilities.fileSize(at: url) ?? 0
        }
    }

    // MARK: - Private Helpers

    private func getDeviceStorageInfo() -> DeviceStorageInfo {
        // Use SimplifiedFileManager's getDeviceStorageInfo method
        let storageInfo = fileManager.getDeviceStorageInfo()
        return DeviceStorageInfo(
            totalSpace: storageInfo.totalSpace,
            freeSpace: storageInfo.freeSpace,
            usedSpace: storageInfo.usedSpace
        )
    }

    private func getStoredModelsList() async -> [StoredModel] {
        var storedModels: [StoredModel] = []

        // Get all stored model data from file manager
        let storedModelsData = fileManager.getAllStoredModels()

        // Get all registered models from registry
        let registeredModels = await modelRegistry.discoverModels()

        // Create a map of registered models for quick lookup
        let registeredModelsMap = Dictionary(uniqueKeysWithValues: registeredModels.map { ($0.id, $0) })

        // Convert stored model data to StoredModel objects
        for modelInfo in storedModelsData {
            // Try to find corresponding registered model for additional metadata
            let registeredModel = registeredModelsMap[modelInfo.modelId]

            // Try to get the model URL
            let modelURL: URL
            if let url = try? fileManager.getModelURL(modelId: modelInfo.modelId, format: modelInfo.format) {
                modelURL = url
            } else if let url = fileManager.findModelFile(modelId: modelInfo.modelId) {
                modelURL = url
            } else {
                // Skip if we can't find the file
                continue
            }

            let storedModel = StoredModel(
                id: modelInfo.modelId,
                name: registeredModel?.name ?? modelInfo.modelId,
                path: modelURL,
                size: modelInfo.size,
                format: modelInfo.format,
                framework: modelInfo.framework ?? registeredModel?.preferredFramework,
                createdDate: fileManager.getFileCreationDate(at: modelURL) ?? Date(),
                lastUsed: fileManager.getFileAccessDate(at: modelURL),
                tags: registeredModel?.tags ?? [],
                description: registeredModel?.description,
                contextLength: registeredModel?.contextLength
            )

            storedModels.append(storedModel)
        }

        return storedModels
    }
}
