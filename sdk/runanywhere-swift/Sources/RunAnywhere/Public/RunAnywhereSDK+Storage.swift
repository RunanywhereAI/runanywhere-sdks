import Foundation

// MARK: - Storage Management APIs

extension RunAnywhereSDK {

    /// Get storage information
    /// - Returns: Storage information including app, device, and model storage details
    public func getStorageInfo() async -> StorageInfo {
        let totalSize = serviceContainer.fileManager.getTotalStorageSize()
        let availableSpace = serviceContainer.fileManager.getAvailableSpace()
        let modelStorageSize = serviceContainer.fileManager.getModelStorageSize()

        // Get stored models for detailed info
        let storedModels = await getStoredModels()

        // Group models by framework
        var modelsByFramework: [LLMFramework: [StoredModel]] = [:]
        for model in storedModels {
            if let framework = model.framework {
                if modelsByFramework[framework] == nil {
                    modelsByFramework[framework] = []
                }
                modelsByFramework[framework]?.append(model)
            }
        }

        // Find largest model
        let largestModel = storedModels.max { $0.size < $1.size }

        return StorageInfo(
            appStorage: AppStorageInfo(
                documentsSize: totalSize,
                cacheSize: 0, // Could be enhanced to track cache separately
                appSupportSize: 0,
                totalSize: totalSize
            ),
            deviceStorage: DeviceStorageInfo(
                totalSpace: availableSpace + totalSize, // Approximate
                freeSpace: availableSpace,
                usedSpace: totalSize
            ),
            modelStorage: ModelStorageInfo(
                totalSize: modelStorageSize,
                modelCount: storedModels.count,
                modelsByFramework: modelsByFramework,
                largestModel: largestModel
            ),
            cacheSize: 0, // Could be enhanced to track cache separately
            storedModels: storedModels,
            lastUpdated: Date()
        )
    }

    /// Get all stored models with their metadata
    /// - Returns: Array of stored model information
    public func getStoredModels() async -> [StoredModel] {
        // Get basic model info from file system
        let modelData = serviceContainer.fileManager.getAllStoredModels()

        // Get metadata from repository if available
        let repositoryModels: [ModelInfo]
        do {
            repositoryModels = try await listAvailableModels()
        } catch {
            repositoryModels = []
        }

        // Map to StoredModel
        return modelData.compactMap { modelId, format, size, detectedFramework in
            // Find matching model info from repository
            let modelInfo = repositoryModels.first { $0.id == modelId }

            // Try to construct the model path
            let baseURL = serviceContainer.fileManager.getBaseDirectoryURL()
            let modelsURL = baseURL.appendingPathComponent("Models")

            // Use detected framework from file system, or fall back to model info or format detection
            let framework = detectedFramework ?? modelInfo?.compatibleFrameworks.first ?? detectFramework(for: format)

            // Determine path based on framework and format
            var modelPath: URL
            if let framework = framework {
                let frameworkPath = modelsURL.appendingPathComponent(framework.rawValue)
                let modelFolderPath = frameworkPath.appendingPathComponent(modelId)

                // Check if this is a directory-based model (no single file)
                // Directory-based models (like compiled Core ML) don't have a single file
                let isDirectoryModel = !FileManager.default.fileExists(atPath: modelFolderPath.appendingPathComponent("\(modelId).\(format.rawValue)").path)

                if isDirectoryModel {
                    modelPath = modelFolderPath
                } else {
                    modelPath = modelFolderPath.appendingPathComponent("\(modelId).\(format.rawValue)")
                }
            } else {
                modelPath = modelsURL
                    .appendingPathComponent(modelId)
                    .appendingPathComponent("\(modelId).\(format.rawValue)")
            }

            // Extract a better display name for models
            let displayName: String
            if let modelName = modelInfo?.name {
                displayName = modelName
            } else {
                // Generic name extraction from modelId
                // Remove common prefixes
                var cleanId = modelId
                    .replacingOccurrences(of: "user-", with: "")
                    .replacingOccurrences(of: "openai_", with: "")
                    .replacingOccurrences(of: "_", with: " ")

                // Remove hash suffix if it looks like a hash (long number at the end)
                // Pattern: name-<large number>
                if let lastDashIndex = cleanId.lastIndex(of: "-") {
                    let suffix = String(cleanId[cleanId.index(after: lastDashIndex)...])
                    // Check if suffix is a large number (likely a hash)
                    if suffix.count > 10 && Int(suffix) != nil {
                        cleanId = String(cleanId[..<lastDashIndex])
                    }
                }

                // Clean up and capitalize
                displayName = cleanId
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: ".", with: " ")
                    .split(separator: " ")
                    .map { $0.capitalized }
                    .joined(separator: " ")
            }

            return StoredModel(
                id: modelId,  // Use the actual folder name as ID for deletion
                name: displayName,
                path: modelPath,
                size: size,
                format: format,
                framework: framework,
                createdDate: Date(), // Could be enhanced to get actual creation date
                lastUsed: nil, // Could be enhanced with usage tracking
                metadata: modelInfo?.metadata,
                contextLength: modelInfo?.contextLength,
                checksum: modelInfo?.checksum
            )
        }
    }

    /// Clear all cache files
    public func clearCache() async throws {
        try serviceContainer.fileManager.clearCache()
    }

    /// Clean temporary files
    public func cleanTempFiles() async throws {
        try serviceContainer.fileManager.cleanTempFiles()
    }

    /// Delete a specific model
    /// - Parameter modelId: The model ID to delete
    public func deleteStoredModel(_ modelId: String) async throws {
        try serviceContainer.fileManager.deleteModel(modelId: modelId)
    }

    /// Get the base storage directory URL
    /// - Returns: URL to the base RunAnywhere directory
    public func getBaseDirectoryURL() -> URL {
        return serviceContainer.fileManager.getBaseDirectoryURL()
    }

    // MARK: - Private Helpers

    private func detectFramework(for format: ModelFormat) -> LLMFramework? {
        switch format {
        case .gguf, .ggml:
            return .llamaCpp
        case .mlmodel, .mlpackage:
            // Note: WhisperKit models will be properly detected through model metadata
            // This is a fallback for Core ML models without metadata
            return .coreML
        case .onnx:
            return .onnx
        case .tflite:
            return .tensorFlowLite
        case .mlx:
            return .mlx
        default:
            return nil
        }
    }
}
