import Foundation

/// Dynamic model registry with discovery capabilities
public class DynamicModelRegistry: ModelRegistry {
    public static let shared = DynamicModelRegistry()
    
    private var registeredModels: [String: ModelInfo] = [:]
    private let modelLock = NSLock()
    private let localStorage = ModelLocalStorage()
    private var registeredProviders: [ModelProvider] = []
    private let formatDetector = ModelFormatDetector()
    private let metadataExtractor = MetadataExtractor()
    
    /// Configuration for model discovery
    public struct DiscoveryConfig {
        public var includeLocalModels: Bool = true
        public var includeOnlineModels: Bool = true
        public var modelDirectories: [URL] = []
        public var cacheTimeout: TimeInterval = 3600 // 1 hour
        
        public init() {
            // Add default model directories
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                modelDirectories.append(documentsURL.appendingPathComponent("Models", isDirectory: true))
            }
        }
    }
    
    private var config = DiscoveryConfig()
    private var lastDiscovery: Date?
    private var discoveryCache: [ModelInfo] = []
    
    private init() {
        setupDefaultProviders()
    }
    
    /// Configure the registry
    public func configure(_ config: DiscoveryConfig) {
        self.config = config
    }
    
    /// Register a model provider
    public func registerProvider(_ provider: ModelProvider) {
        registeredProviders.append(provider)
    }
    
    // MARK: - Model Discovery
    
    public func discoverModels() async -> [ModelInfo] {
        // Check cache
        if let lastDiscovery = lastDiscovery,
           Date().timeIntervalSince(lastDiscovery) < config.cacheTimeout {
            return discoveryCache
        }
        
        var allModels: [ModelInfo] = []
        
        // Discover local models
        if config.includeLocalModels {
            let localModels = await discoverLocalModels()
            allModels.append(contentsOf: localModels)
        }
        
        // Discover online models
        if config.includeOnlineModels {
            let onlineModels = await discoverOnlineModels()
            allModels.append(contentsOf: onlineModels)
        }
        
        // Deduplicate by ID
        let uniqueModels = deduplicateModels(allModels)
        
        // Update registry
        await withCheckedContinuation { continuation in
            modelLock.lock()
            for model in uniqueModels {
                registeredModels[model.id] = model
            }
            modelLock.unlock()
            continuation.resume()
        }
        
        // Update cache
        discoveryCache = uniqueModels
        lastDiscovery = Date()
        
        return uniqueModels
    }
    
    private func discoverLocalModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []
        
        for directory in config.modelDirectories {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]
            ) {
                for url in contents {
                    if let model = await detectModel(at: url) {
                        models.append(model)
                    }
                }
            }
        }
        
        // Also check for models in app bundle
        if let bundleModels = discoverBundleModels() {
            models.append(contentsOf: bundleModels)
        }
        
        return models
    }
    
    private func discoverOnlineModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []
        
        // Query each registered provider
        await withTaskGroup(of: [ModelInfo].self) { group in
            for provider in registeredProviders {
                group.addTask {
                    do {
                        return try await provider.listAvailableModels()
                    } catch {
                        print("[ModelRegistry] Failed to query provider \(provider.name): \(error)")
                        return []
                    }
                }
            }
            
            for await providerModels in group {
                models.append(contentsOf: providerModels)
            }
        }
        
        return models
    }
    
    private func detectModel(at url: URL) async -> ModelInfo? {
        // Skip hidden files and directories
        if url.lastPathComponent.hasPrefix(".") {
            return nil
        }
        
        // Detect format
        guard let format = formatDetector.detectFormat(at: url) else {
            return nil
        }
        
        // Skip unknown formats
        if format == .unknown {
            return nil
        }
        
        // Extract metadata
        let metadata = await metadataExtractor.extractMetadata(from: url, format: format)
        
        // Determine compatible frameworks
        let frameworks = detectCompatibleFrameworks(format: format, metadata: metadata)
        
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        
        // Create model info
        let modelId = generateModelId(from: url)
        let modelName = generateModelName(from: url, metadata: metadata)
        
        return ModelInfo(
            id: modelId,
            name: modelName,
            format: format,
            localPath: url,
            estimatedMemory: estimateMemoryUsage(fileSize: fileSize, format: format),
            contextLength: metadata.contextLength ?? 2048,
            downloadSize: fileSize,
            compatibleFrameworks: frameworks,
            preferredFramework: frameworks.first,
            hardwareRequirements: detectHardwareRequirements(format: format, metadata: metadata),
            tokenizerFormat: detectTokenizerFormat(at: url),
            metadata: convertMetadataToDict(metadata)
        )
    }
    
    private func discoverBundleModels() -> [ModelInfo]? {
        var models: [ModelInfo] = []
        
        // Check main bundle for models
        let bundle = Bundle.main
        let modelExtensions = ["mlmodel", "mlmodelc", "mlpackage", "tflite", "onnx", "gguf"]
        
        for ext in modelExtensions {
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    Task {
                        if let model = await detectModel(at: url) {
                            models.append(model)
                        }
                    }
                }
            }
        }
        
        return models.isEmpty ? nil : models
    }
    
    // MARK: - Model Registration
    
    public func registerModel(_ model: ModelInfo) async {
        await withCheckedContinuation { continuation in
            modelLock.lock()
            registeredModels[model.id] = model
            modelLock.unlock()
            continuation.resume()
        }
        
        // Persist to local storage
        await localStorage.saveModel(model)
    }
    
    public func unregisterModel(_ modelId: String) async {
        modelLock.lock()
        registeredModels.removeValue(forKey: modelId)
        modelLock.unlock()
        
        // Remove from local storage
        await localStorage.removeModel(modelId)
    }
    
    public func getModel(_ modelId: String) -> ModelInfo? {
        modelLock.lock()
        defer { modelLock.unlock() }
        
        return registeredModels[modelId]
    }
    
    public func updateModel(_ model: ModelInfo) async {
        await registerModel(model)
    }
    
    // MARK: - Model Filtering
    
    public func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        modelLock.lock()
        let models = Array(registeredModels.values)
        modelLock.unlock()
        
        return models.filter { model in
            // Framework filter
            if let framework = criteria.framework {
                guard model.compatibleFrameworks.contains(framework) else {
                    return false
                }
            }
            
            // Format filter
            if let format = criteria.format {
                guard model.format == format else {
                    return false
                }
            }
            
            // Size filter
            if let maxSize = criteria.maxSize {
                guard model.estimatedMemory <= maxSize else {
                    return false
                }
            }
            
            // Context length filters
            if let minContext = criteria.minContextLength {
                guard model.contextLength >= minContext else {
                    return false
                }
            }
            
            if let maxContext = criteria.maxContextLength {
                guard model.contextLength <= maxContext else {
                    return false
                }
            }
            
            // Neural Engine filter
            if let requiresNE = criteria.requiresNeuralEngine, requiresNE {
                let hasNERequirement = model.hardwareRequirements.contains { req in
                    if case .neuralEngine = req { return true }
                    return false
                }
                guard hasNERequirement else {
                    return false
                }
            }
            
            // Quantization filter
            if let quantization = criteria.quantization {
                guard let modelQuant = model.metadata?["quantization"] as? String,
                      modelQuant.lowercased().contains(quantization.lowercased()) else {
                    return false
                }
            }
            
            // Search filter
            if let search = criteria.search?.lowercased(), !search.isEmpty {
                let searchableText = "\(model.name) \(model.format.rawValue)".lowercased()
                guard searchableText.contains(search) else {
                    return false
                }
            }
            
            return true
        }
    }
    
    // MARK: - Compatibility Detection
    
    private func detectCompatibleFrameworks(format: ModelFormat, metadata: ModelMetadata) -> [LLMFramework] {
        var frameworks: [LLMFramework] = []
        
        switch format {
        case .mlmodel, .mlpackage:
            frameworks.append(.coreML)
            // Swift Transformers can also use Core ML models
            if isSwiftTransformersCompatible(metadata) {
                frameworks.append(.swiftTransformers)
            }
            
        case .tflite:
            frameworks.append(.tfLite)
            
        case .onnx, .ort:
            frameworks.append(.onnx)
            
        case .safetensors:
            // Multiple frameworks can use safetensors
            frameworks.append(.mlx)
            frameworks.append(.swiftTransformers)
            
        case .gguf, .ggml:
            frameworks.append(.llamaCpp)
            
        case .pte:
            frameworks.append(.execuTorch)
            
        case .bin:
            // Depends on accompanying files
            if let modelType = metadata.modelType {
                switch modelType {
                case "gpt2", "bert", "llama":
                    frameworks.append(.swiftTransformers)
                default:
                    break
                }
            }
            
        default:
            break
        }
        
        return frameworks
    }
    
    private func isSwiftTransformersCompatible(_ metadata: ModelMetadata) -> Bool {
        // Check if model has required inputs
        if let inputs = metadata.inputShapes {
            return inputs.keys.contains("input_ids")
        }
        return false
    }
    
    private func detectHardwareRequirements(format: ModelFormat, metadata: ModelMetadata) -> [HardwareRequirement] {
        var requirements: [HardwareRequirement] = []
        
        // Memory requirements
        if let minMemory = metadata.requirements?.minMemory {
            requirements.append(.minMemory(minMemory))
        }
        
        // Accelerator requirements
        switch format {
        case .mlmodel, .mlpackage:
            // Core ML can use Neural Engine
            requirements.append(.neuralEngine)
            
        case .tflite:
            // TFLite can use GPU
            requirements.append(.gpu)
            
        case .mlx:
            // MLX requires Apple Silicon
            requirements.append(.minProcessorGeneration("A17"))
            
        default:
            break
        }
        
        return requirements
    }
    
    private func detectTokenizerFormat(at url: URL) -> TokenizerFormat? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            // Check for tokenizer files
            for file in contents {
                let filename = file.lastPathComponent
                
                if filename == "tokenizer.json" {
                    return .huggingFace
                } else if filename.contains("sentencepiece") {
                    return .sentencePiece
                } else if filename == "vocab.txt" {
                    return .wordPiece
                } else if file.pathExtension == "bpe" {
                    return .bpe
                }
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func setupDefaultProviders() {
        // SDK doesn't include providers by default
        // They should be registered by the app
    }
    
    private func deduplicateModels(_ models: [ModelInfo]) -> [ModelInfo] {
        var seen = Set<String>()
        var unique: [ModelInfo] = []
        
        for model in models {
            if !seen.contains(model.id) {
                seen.insert(model.id)
                unique.append(model)
            }
        }
        
        return unique
    }
    
    private func generateModelId(from url: URL) -> String {
        // Generate a stable ID based on path and name
        let path = url.path
        let data = path.data(using: .utf8)!
        let hash = data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(8)
        
        return "\(url.lastPathComponent)-\(hash)"
    }
    
    private func generateModelName(from url: URL, metadata: ModelMetadata) -> String {
        // Use metadata name if available
        if let name = metadata.description {
            return name
        }
        
        // Otherwise use filename without extension
        return url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
    
    private func estimateMemoryUsage(fileSize: Int64, format: ModelFormat) -> Int64 {
        // Rough estimates based on format
        switch format {
        case .gguf, .ggml:
            // GGUF models are already quantized, memory ≈ file size
            return fileSize
            
        case .mlmodel, .mlpackage:
            // Core ML models can expand in memory
            return Int64(Double(fileSize) * 1.5)
            
        case .tflite:
            // TFLite models are compact
            return fileSize
            
        case .safetensors:
            // Safetensors need to be loaded into memory
            return Int64(Double(fileSize) * 1.2)
            
        default:
            // Conservative estimate
            return Int64(Double(fileSize) * 1.5)
        }
    }
    
    private func convertMetadataToDict(_ metadata: ModelMetadata) -> [String: Any] {
        var dict: [String: Any] = [:]
        
        if let author = metadata.author { dict["author"] = author }
        if let description = metadata.description { dict["description"] = description }
        if let version = metadata.version { dict["version"] = version }
        if let modelType = metadata.modelType { dict["modelType"] = modelType }
        if let architecture = metadata.architecture { dict["architecture"] = architecture }
        if let quantization = metadata.quantization { dict["quantization"] = quantization }
        if let contextLength = metadata.contextLength { dict["contextLength"] = contextLength }
        if let parameterCount = metadata.parameterCount { dict["parameterCount"] = parameterCount }
        
        return dict
    }
}

// MARK: - Model Local Storage

/// Handles local storage of model information
private class ModelLocalStorage {
    private let storageURL: URL
    
    init() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documentsURL.appendingPathComponent("ModelRegistry.plist")
    }
    
    func saveModel(_ model: ModelInfo) async {
        var models = await loadAllModels()
        models[model.id] = model
        await saveAllModels(models)
    }
    
    func removeModel(_ modelId: String) async {
        var models = await loadAllModels()
        models.removeValue(forKey: modelId)
        await saveAllModels(models)
    }
    
    func loadAllModels() async -> [String: ModelInfo] {
        // This would need proper encoding/decoding implementation
        // For now, return empty dictionary
        [:]
    }
    
    func saveAllModels(_ models: [String: ModelInfo]) async {
        // This would need proper encoding/decoding implementation
    }
}
