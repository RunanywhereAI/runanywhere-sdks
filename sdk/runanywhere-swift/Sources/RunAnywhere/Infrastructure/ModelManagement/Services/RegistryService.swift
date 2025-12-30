import Foundation

/// Implementation of model registry with integrated local model discovery
public class RegistryService: ModelRegistry {
    private var models: [String: ModelInfo] = [:]
    private let accessQueue = DispatchQueue(label: "com.runanywhere.registry", attributes: .concurrent)
    private let logger = SDKLogger(category: "RegistryService")

    public init() {
        logger.debug("Initializing RegistryService")
    }

    /// Initialize registry with configuration
    public func initialize(with _: String) async {
        logger.info("Initializing registry with configuration")

        // Load pre-configured models
        await loadPreconfiguredModels()

        // Discover local models that are already downloaded
        logger.debug("Discovering local models from cache")
        let localModels = await discoverLocalModels()
        logger.info("Found \(localModels.count) cached models on disk")

        // Update existing registered models with discovered local paths
        for discoveredModel in localModels {
            if let existingModel = getModel(by: discoveredModel.id) {
                if existingModel.localPath == nil && discoveredModel.localPath != nil {
                    var updatedModel = existingModel
                    updatedModel.localPath = discoveredModel.localPath
                    updateModel(updatedModel)
                    logger.info("Updated model '\(discoveredModel.id)' with cached localPath")
                }
            } else {
                logger.info("Registering cached model: \(discoveredModel.id)")
                registerModel(discoveredModel)
            }
        }

        logger.info("Registry initialization complete")
    }

    public func discoverModels() async -> [ModelInfo] {
        let allModels = accessQueue.sync { Array(models.values) }
        ModelInfoCache.shared.cacheModels(allModels)
        return allModels
    }

    public func registerModel(_ model: ModelInfo) {
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        var updatedModel = model
        if updatedModel.localPath == nil {
            let fileManager = ServiceContainer.shared.fileManager
            if fileManager.modelFolderExists(modelId: model.id, framework: model.framework) {
                if let folderURL = try? fileManager.getModelFolderURL(modelId: model.id, framework: model.framework) {
                    updatedModel.localPath = resolveModelPath(in: folderURL)
                    logger.info("Found downloaded model \(model.id)")
                }
            }
        }

        accessQueue.async(flags: .barrier) {
            self.models[updatedModel.id] = updatedModel
        }
        ModelInfoCache.shared.cacheModels([updatedModel])
    }

    /// Register model and save to in-memory storage
    public func registerModelPersistently(_ model: ModelInfo) async {
        guard !model.id.isEmpty else {
            logger.error("Attempted to register model with empty ID")
            return
        }

        var updatedModel = model
        let fileManager = ServiceContainer.shared.fileManager
        if fileManager.modelFolderExists(modelId: model.id, framework: model.framework) {
            if let folderURL = try? fileManager.getModelFolderURL(modelId: model.id, framework: model.framework) {
                updatedModel.localPath = resolveModelPath(in: folderURL)
            }
        } else {
            updatedModel.localPath = nil
        }

        registerModel(updatedModel)

        do {
            let modelInfoService = await ServiceContainer.shared.modelInfoService
            try await modelInfoService.saveModel(updatedModel)
            logger.debug("Saved model persistently: \(updatedModel.id)")
        } catch {
            logger.error("Failed to save model \(updatedModel.id): \(error)")
        }
    }

    public func getModel(by id: String) -> ModelInfo? {
        accessQueue.sync { models[id] }
    }

    public func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        accessQueue.sync {
            models.values.filter { model in
                if let framework = criteria.framework, model.framework != framework {
                    return false
                }
                if let format = criteria.format, model.format != format {
                    return false
                }
                if let maxSize = criteria.maxSize, let downloadSize = model.downloadSize, downloadSize > maxSize {
                    return false
                }
                if let search = criteria.search, !search.isEmpty {
                    let searchLower = search.lowercased()
                    let matches = model.name.lowercased().contains(searchLower)
                        || model.id.lowercased().contains(searchLower)
                        || (model.description?.lowercased().contains(searchLower) ?? false)
                    if !matches { return false }
                }
                return true
            }
        }
    }

    public func updateModel(_ model: ModelInfo) {
        accessQueue.async(flags: .barrier) { self.models[model.id] = model }
    }

    public func removeModel(_ id: String) {
        accessQueue.async(flags: .barrier) { self.models.removeValue(forKey: id) }
    }

    public func addModelFromURL(
        id: String? = nil,
        name: String,
        url: URL,
        framework: InferenceFramework,
        category: ModelCategory? = nil,
        artifactType: ModelArtifactType? = nil,
        estimatedSize: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo {
        let modelId = id ?? generateModelId(from: url)
        let format = detectFormatFromURL(url)
        let resolvedCategory = category ?? ModelCategory.from(framework: framework)

        // Validate format compatibility with framework
        if format != .unknown && !framework.supports(format: format) {
            logger.warning(
                "Model '\(name)' has format '\(format.rawValue)' which may not be supported by \(framework.displayName). " +
                "Supported formats: \(framework.supportedFormats.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let modelInfo = ModelInfo(
            id: modelId,
            name: name,
            category: resolvedCategory,
            format: format,
            framework: framework,
            downloadURL: url,
            localPath: nil,
            artifactType: artifactType,
            downloadSize: nil,
            contextLength: resolvedCategory == .language ? 2048 : nil,
            supportsThinking: supportsThinking,
            description: "User-added model",
            source: .local  // Models added via SDK input are always local source
        )

        registerModel(modelInfo)
        return modelInfo
    }

    // MARK: - Private: Preconfigured Models

    private func loadPreconfiguredModels() async {
        let modelInfoService = ServiceContainer.shared.modelInfoService
        do {
            let storedModels = try await modelInfoService.loadStoredModels()
            logger.info("Loading \(storedModels.count) stored models")
            for model in storedModels {
                registerModel(model)
            }
        } catch {
            logger.error("Failed to load stored models: \(error)")
        }
    }

    // MARK: - Private: Local Model Discovery

    private func discoverLocalModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []
        models.append(contentsOf: await discoverFrameworkModels())
        if let bundleModels = discoverBundleModels() {
            models.append(contentsOf: bundleModels)
        }
        return models
    }

    @MainActor
    private func discoverFrameworkModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []
        let fm = FileManager.default

        guard let modelsURL = try? ModelPathUtils.getModelsDirectory(),
              let frameworkFolders = try? fm.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        for frameworkFolder in frameworkFolders {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: frameworkFolder.path, isDirectory: &isDir), isDir.boolValue,
                  let framework = InferenceFramework.allCases.first(where: { $0.rawValue == frameworkFolder.lastPathComponent }),
                  let modelFolders = try? fm.contentsOfDirectory(at: frameworkFolder, includingPropertiesForKeys: [.isDirectoryKey]) else {
                continue
            }

            for modelFolder in modelFolders {
                var isModelDir: ObjCBool = false
                guard fm.fileExists(atPath: modelFolder.path, isDirectory: &isModelDir), isModelDir.boolValue else { continue }

                let modelId = modelFolder.lastPathComponent

                // Generic detection for models (storage strategies are registered per-module)
                if let modelInfo = detectModelInFolder(modelFolder, framework: framework) {
                    models.append(modelInfo)
                }
            }
        }
        return models
    }

    private func detectModelInFolder(_ folder: URL, framework: InferenceFramework) -> ModelInfo? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }

        let modelExtensions = ["gguf", "onnx", "ort", "bin"]
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard modelExtensions.contains(ext), let format = detectFormatFromExtension(ext) else { continue }

            let fileSize = FileOperationsUtilities.fileSize(at: file) ?? 0
            let modelId = folder.lastPathComponent
            let category = ModelCategory.from(framework: framework)

            return ModelInfo(
                id: modelId,
                name: generateModelName(from: folder),
                category: category,
                format: format,
                framework: framework,
                localPath: file,
                downloadSize: fileSize,
                contextLength: category == .language ? 2048 : nil,
                supportsThinking: false,
                source: .local  // Discovered locally on disk
            )
        }
        return nil
    }

    private func discoverBundleModels() -> [ModelInfo]? {
        var models: [ModelInfo] = []
        let bundle = Bundle.main
        let modelExtensions = ["onnx", "ort", "gguf", "bin"]

        for ext in modelExtensions {
            guard let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil),
                  let format = detectFormatFromExtension(ext),
                  let framework = detectFramework(for: format) else { continue }

            for url in urls {
                let fileSize = FileOperationsUtilities.fileSize(at: url) ?? 0
                let modelId = url.deletingPathExtension().lastPathComponent
                let category = ModelCategory.from(framework: framework)

                models.append(ModelInfo(
                    id: modelId,
                    name: generateModelName(from: url),
                    category: category,
                    format: format,
                    framework: framework,
                    localPath: url,
                    downloadSize: fileSize,
                    contextLength: category == .language ? 2048 : nil,
                    supportsThinking: false,
                    source: .local  // Bundled models are local
                ))
            }
        }
        return models.isEmpty ? nil : models
    }

    // MARK: - Private: Path Resolution

    private func resolveModelPath(in folderURL: URL) -> URL {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ), contents.count == 1, let singleItem = contents.first else {
            return folderURL
        }
        return singleItem
    }

    // MARK: - Private: Format Detection & Helpers

    private func generateModelId(from url: URL) -> String {
        var filename = url.lastPathComponent
        let knownExtensions = ["gz", "bz2", "tar", "zip", "gguf", "onnx", "ort", "bin"]
        while let ext = filename.split(separator: ".").last, knownExtensions.contains(String(ext).lowercased()) {
            filename = String(filename.dropLast(ext.count + 1))
        }
        return filename
    }

    private func generateModelName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func detectFormatFromURL(_ url: URL) -> ModelFormat {
        detectFormatFromExtension(url.pathExtension.lowercased()) ?? .unknown
    }

    private func detectFormatFromExtension(_ ext: String) -> ModelFormat? {
        switch ext {
        case "onnx": return .onnx
        case "ort": return .ort
        case "gguf": return .gguf
        case "bin": return .bin
        default: return nil
        }
    }

    private func detectFramework(for format: ModelFormat) -> InferenceFramework? {
        // Use centralized framework detection from InferenceFramework
        InferenceFramework.framework(for: format)
    }
}
