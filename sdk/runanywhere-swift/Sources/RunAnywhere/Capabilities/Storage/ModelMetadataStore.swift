import Foundation

/// Stores model metadata persistently
public class ModelMetadataStore {
    private let userDefaults = UserDefaults.standard
    private let metadataKey = "com.runanywhere.modelMetadata"

    private let logger = SDKLogger(category: "ModelMetadataStore")

    /// Model metadata that gets persisted
    struct StoredModelMetadata: Codable {
        let id: String
        let name: String
        let format: String
        let framework: String
        let localPath: String
        let estimatedMemory: Int64
        let contextLength: Int
        let downloadSize: Int64?
        let checksum: String?
        let author: String?
        let license: String?
        let description: String?
        let tags: [String]
        let downloadedAt: Date
        let lastUsed: Date?
        let supportsThinking: Bool
        let thinkingOpenTag: String?
        let thinkingCloseTag: String?
    }

    public init() {}

    /// Save model metadata after successful download
    public func saveModelMetadata(_ model: ModelInfo) {
        guard let localPath = model.localPath else {
            logger.error("Cannot save metadata for model without local path")
            return
        }

        let metadata = StoredModelMetadata(
            id: model.id,
            name: model.name,
            format: model.format.rawValue,
            framework: model.preferredFramework?.rawValue ?? model.compatibleFrameworks.first?.rawValue ?? "",
            localPath: localPath.path,
            estimatedMemory: model.estimatedMemory,
            contextLength: model.contextLength,
            downloadSize: model.downloadSize,
            checksum: model.checksum,
            author: model.metadata?.author,
            license: model.metadata?.license,
            description: model.metadata?.description,
            tags: model.metadata?.tags ?? [],
            downloadedAt: Date(),
            lastUsed: nil,
            supportsThinking: model.supportsThinking,
            thinkingOpenTag: model.thinkingTagPattern?.openingTag,
            thinkingCloseTag: model.thinkingTagPattern?.closingTag
        )

        var allMetadata = loadAllMetadata()
        allMetadata[model.id] = metadata
        saveAllMetadata(allMetadata)

        logger.info("Saved metadata for model: \(model.id)")
    }

    /// Load all stored model metadata
    public func loadStoredModels() -> [ModelInfo] {
        let allMetadata = loadAllMetadata()

        return allMetadata.compactMap { (id, metadata) in
            // Check if the file still exists
            let localURL = URL(fileURLWithPath: metadata.localPath)
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                logger.warning("Model file missing for \(id), removing metadata")
                removeModelMetadata(id)
                return nil
            }

            let format = ModelFormat(rawValue: metadata.format) ?? .unknown
            let framework = LLMFramework(rawValue: metadata.framework)

            // Get actual file size from disk
            var actualFileSize = metadata.downloadSize
            if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
               let fileSize = attributes[.size] as? Int64 {
                actualFileSize = fileSize
            }

            // Reconstruct thinking tag pattern if available
            let thinkingTagPattern: ThinkingTagPattern? = {
                if metadata.supportsThinking,
                   let openTag = metadata.thinkingOpenTag,
                   let closeTag = metadata.thinkingCloseTag {
                    return ThinkingTagPattern(openingTag: openTag, closingTag: closeTag)
                }
                return metadata.supportsThinking ? ThinkingTagPattern.defaultPattern : nil
            }()

            return ModelInfo(
                id: metadata.id,
                name: metadata.name,
                format: format,
                localPath: localURL,
                estimatedMemory: metadata.estimatedMemory,
                contextLength: metadata.contextLength,
                downloadSize: actualFileSize,
                checksum: metadata.checksum,
                compatibleFrameworks: framework != nil ? [framework!] : [],
                preferredFramework: framework,
                metadata: ModelInfoMetadata(
                    author: metadata.author,
                    license: metadata.license,
                    tags: metadata.tags,
                    description: metadata.description
                ),
                supportsThinking: metadata.supportsThinking,
                thinkingTagPattern: thinkingTagPattern
            )
        }
    }

    /// Load models for specific frameworks
    public func loadModelsForFrameworks(_ frameworks: [LLMFramework]) -> [ModelInfo] {
        return loadStoredModels().filter { model in
            model.compatibleFrameworks.contains { frameworks.contains($0) }
        }
    }

    /// Update last used date
    public func updateLastUsed(for modelId: String) {
        var allMetadata = loadAllMetadata()
        if let metadata = allMetadata[modelId] {
            allMetadata[modelId] = StoredModelMetadata(
                id: metadata.id,
                name: metadata.name,
                format: metadata.format,
                framework: metadata.framework,
                localPath: metadata.localPath,
                estimatedMemory: metadata.estimatedMemory,
                contextLength: metadata.contextLength,
                downloadSize: metadata.downloadSize,
                checksum: metadata.checksum,
                author: metadata.author,
                license: metadata.license,
                description: metadata.description,
                tags: metadata.tags,
                downloadedAt: metadata.downloadedAt,
                lastUsed: Date(),
                supportsThinking: metadata.supportsThinking,
                thinkingOpenTag: metadata.thinkingOpenTag,
                thinkingCloseTag: metadata.thinkingCloseTag
            )
            saveAllMetadata(allMetadata)
        }
    }

    /// Update thinking support for an existing model
    public func updateThinkingSupport(for modelId: String, supportsThinking: Bool, thinkingTagPattern: ThinkingTagPattern?) {
        var allMetadata = loadAllMetadata()
        if let metadata = allMetadata[modelId] {
            allMetadata[modelId] = StoredModelMetadata(
                id: metadata.id,
                name: metadata.name,
                format: metadata.format,
                framework: metadata.framework,
                localPath: metadata.localPath,
                estimatedMemory: metadata.estimatedMemory,
                contextLength: metadata.contextLength,
                downloadSize: metadata.downloadSize,
                checksum: metadata.checksum,
                author: metadata.author,
                license: metadata.license,
                description: metadata.description,
                tags: metadata.tags,
                downloadedAt: metadata.downloadedAt,
                lastUsed: metadata.lastUsed,
                supportsThinking: supportsThinking,
                thinkingOpenTag: thinkingTagPattern?.openingTag,
                thinkingCloseTag: thinkingTagPattern?.closingTag
            )
            saveAllMetadata(allMetadata)
            logger.info("Updated thinking support for model: \(modelId)")
        }
    }

    /// Remove model metadata
    public func removeModelMetadata(_ modelId: String) {
        var allMetadata = loadAllMetadata()
        allMetadata.removeValue(forKey: modelId)
        saveAllMetadata(allMetadata)
        logger.info("Removed metadata for model: \(modelId)")
    }

    // MARK: - Private Methods

    private func loadAllMetadata() -> [String: StoredModelMetadata] {
        guard let data = userDefaults.data(forKey: metadataKey),
              let metadata = try? JSONDecoder().decode([String: StoredModelMetadata].self, from: data) else {
            return [:]
        }
        return metadata
    }

    private func saveAllMetadata(_ metadata: [String: StoredModelMetadata]) {
        if let data = try? JSONEncoder().encode(metadata) {
            userDefaults.set(data, forKey: metadataKey)
        }
    }
}
