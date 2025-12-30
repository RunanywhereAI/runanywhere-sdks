import Foundation

/// Default implementation of StorageAnalyzer
public class DefaultStorageAnalyzer: StorageAnalyzer {
    private let fileManager: SimplifiedFileManager
    private let modelRegistry: ModelRegistry

    public init(fileManager: SimplifiedFileManager, modelRegistry: ModelRegistry) {
        self.fileManager = fileManager
        self.modelRegistry = modelRegistry
    }

    /// Analyze overall storage situation
    public func analyzeStorage() async -> StorageInfo {
        let deviceStorage = fileManager.getDeviceStorageInfo()
        let modelStorage = await getModelStorageUsage()
        let storedModels = await getStoredModelsList()

        let totalAppSize = fileManager.calculateDirectorySize(at: fileManager.getBaseDirectoryURL())

        return StorageInfo(
            appStorage: AppStorageInfo(
                documentsSize: totalAppSize,
                cacheSize: 0,
                appSupportSize: 0,
                totalSize: totalAppSize
            ),
            deviceStorage: deviceStorage,
            modelStorage: modelStorage,
            cacheSize: 0,
            storedModels: storedModels,
            lastUpdated: Date()
        )
    }

    /// Get model storage usage
    public func getModelStorageUsage() async -> ModelStorageInfo {
        let downloadedModels = fileManager.getDownloadedModels()

        var totalSize: Int64 = 0
        var modelCount = 0
        var modelsByFramework: [InferenceFramework: [StoredModel]] = [:]

        for (framework, modelIds) in downloadedModels {
            for modelId in modelIds {
                guard let folderURL = try? fileManager.getModelFolderURL(modelId: modelId, framework: framework) else {
                    continue
                }

                let size = fileManager.calculateDirectorySize(at: folderURL)
                totalSize += size
                modelCount += 1

                let storedModel = StoredModel(
                    id: modelId,
                    name: modelId,
                    path: folderURL,
                    size: size,
                    format: .unknown,
                    framework: framework,
                    createdDate: Date(),
                    description: nil,
                    contextLength: nil
                )
                modelsByFramework[framework, default: []].append(storedModel)
            }
        }

        let allModels = modelsByFramework.values.flatMap { $0 }
        let largestModel = allModels.max(by: { $0.size < $1.size })

        return ModelStorageInfo(
            totalSize: totalSize,
            modelCount: modelCount,
            modelsByFramework: modelsByFramework,
            largestModel: largestModel
        )
    }

    /// Check if storage is available for a model download
    public func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double = 0.1) -> StorageAvailability {
        let availableSpace = fileManager.getAvailableSpace()
        let requiredSpace = Int64(Double(modelSize) * (1 + safetyMargin))

        let isAvailable = availableSpace > requiredSpace
        let hasWarning = availableSpace < requiredSpace * 2

        let recommendation: String?
        if !isAvailable {
            let shortfall = requiredSpace - availableSpace
            let formatter = ByteCountFormatter()
            formatter.countStyle = .memory
            recommendation = "Need \(formatter.string(fromByteCount: shortfall)) more space."
        } else if hasWarning {
            recommendation = "Storage space is getting low."
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

    /// Calculate size at URL
    public func calculateSize(at url: URL) async throws -> Int64 {
        let (exists, isDirectory) = FileOperationsUtilities.existsWithType(at: url)

        guard exists else {
            throw SDKError.fileManagement(.fileNotFound, "File not found: \(url.path)")
        }

        if isDirectory {
            return fileManager.calculateDirectorySize(at: url)
        } else {
            return FileOperationsUtilities.fileSize(at: url) ?? 0
        }
    }

    // MARK: - Private

    private func getStoredModelsList() async -> [StoredModel] {
        var storedModels: [StoredModel] = []
        let downloadedModels = fileManager.getDownloadedModels()
        let registeredModels = await modelRegistry.discoverModels()
        let registeredModelsMap = Dictionary(uniqueKeysWithValues: registeredModels.map { ($0.id, $0) })

        for (framework, modelIds) in downloadedModels {
            for modelId in modelIds {
                guard let folderURL = try? fileManager.getModelFolderURL(modelId: modelId, framework: framework) else {
                    continue
                }

                let registeredModel = registeredModelsMap[modelId]
                let size = fileManager.calculateDirectorySize(at: folderURL)

                storedModels.append(StoredModel(
                    id: modelId,
                    name: registeredModel?.name ?? modelId,
                    path: folderURL,
                    size: size,
                    format: registeredModel?.format ?? .unknown,
                    framework: framework,
                    createdDate: Date(),
                    description: registeredModel?.description,
                    contextLength: registeredModel?.contextLength
                ))
            }
        }

        return storedModels
    }
}
