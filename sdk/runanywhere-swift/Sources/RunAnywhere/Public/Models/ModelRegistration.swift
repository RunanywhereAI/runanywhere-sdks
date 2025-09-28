import Foundation

/// Model registration information for custom models during adapter registration
public struct ModelRegistration {
    /// Unique identifier for the model
    public let id: String

    /// Display name for the model
    public let name: String

    /// URL to download the model from (HuggingFace, GitHub, etc.)
    public let url: URL

    /// The framework this model is compatible with
    public let framework: LLMFramework

    /// Model format (auto-detected from URL if nil)
    public let format: ModelFormat?

    /// Estimated memory requirement in bytes (optional)
    public let memoryRequirement: Int64?

    /// Maximum context length (optional)
    public let contextLength: Int?

    /// Additional metadata
    public let metadata: [String: Any]

    /// Public initializer with URL string
    public init(
        url: String,
        framework: LLMFramework,
        id: String? = nil,
        name: String? = nil,
        format: ModelFormat? = nil,
        memoryRequirement: Int64? = nil,
        contextLength: Int? = nil,
        metadata: [String: Any] = [:]
    ) throws {
        guard let modelURL = URL(string: url) else {
            throw SDKError.invalidConfiguration("Invalid model URL: \(url)")
        }

        self.url = modelURL
        self.framework = framework
        self.id = id ?? modelURL.lastPathComponent.replacingOccurrences(of: ".", with: "_")
        self.name = name ?? modelURL.lastPathComponent
        self.format = format ?? ModelFormat.detectFromURL(modelURL)
        self.memoryRequirement = memoryRequirement
        self.contextLength = contextLength
        self.metadata = metadata
    }

    /// Public initializer with URL
    public init(
        url: URL,
        framework: LLMFramework,
        id: String? = nil,
        name: String? = nil,
        format: ModelFormat? = nil,
        memoryRequirement: Int64? = nil,
        contextLength: Int? = nil,
        metadata: [String: Any] = [:]
    ) {
        self.url = url
        self.framework = framework
        self.id = id ?? url.lastPathComponent.replacingOccurrences(of: ".", with: "_")
        self.name = name ?? url.lastPathComponent
        self.format = format ?? ModelFormat.detectFromURL(url)
        self.memoryRequirement = memoryRequirement
        self.contextLength = contextLength
        self.metadata = metadata
    }

    /// Convert to ModelInfo for internal use
    internal func toModelInfo() -> ModelInfo {
        // Determine category based on framework
        let category = ModelCategory.from(framework: framework)

        return ModelInfo(
            id: id,
            name: name,
            category: category,
            format: format ?? .gguf,
            downloadURL: url,
            localPath: nil,
            downloadSize: memoryRequirement,
            memoryRequired: memoryRequirement,
            compatibleFrameworks: [framework],
            preferredFramework: framework,
            contextLength: contextLength,
            supportsThinking: false
        )
    }
}

/// Options for adapter registration
public struct AdapterRegistrationOptions {
    /// Whether to validate models before registration
    public let validateModels: Bool

    /// Whether to auto-download models in development mode
    public let autoDownloadInDev: Bool

    /// Whether to show download progress
    public let showProgress: Bool

    /// Whether to fall back to mock models on failure
    public let fallbackToMockModels: Bool

    /// Download timeout in seconds
    public let downloadTimeout: TimeInterval

    public init(
        validateModels: Bool = true,
        autoDownloadInDev: Bool = false,  // Default to false for lazy loading
        showProgress: Bool = true,
        fallbackToMockModels: Bool = false,
        downloadTimeout: TimeInterval = 300
    ) {
        self.validateModels = validateModels
        self.autoDownloadInDev = autoDownloadInDev
        self.showProgress = showProgress
        self.fallbackToMockModels = fallbackToMockModels
        self.downloadTimeout = downloadTimeout
    }

    /// Default options for development mode
    public static var development: AdapterRegistrationOptions {
        return AdapterRegistrationOptions(
            validateModels: false,
            autoDownloadInDev: false,  // Changed to false for lazy loading
            showProgress: true,
            fallbackToMockModels: true,
            downloadTimeout: 600
        )
    }

    /// Default options for production mode
    public static var production: AdapterRegistrationOptions {
        return AdapterRegistrationOptions(
            validateModels: true,
            autoDownloadInDev: false,
            showProgress: false,
            fallbackToMockModels: false,
            downloadTimeout: 300
        )
    }
}

// Extension to ModelFormat for URL detection
extension ModelFormat {
    /// Detect model format from URL
    static func detectFromURL(_ url: URL) -> ModelFormat? {
        let path = url.path.lowercased()

        if path.contains(".gguf") { return .gguf }
        if path.contains(".ggml") { return .ggml }
        if path.contains(".mlmodel") { return .mlmodel }
        if path.contains(".mlpackage") { return .mlpackage }
        if path.contains(".onnx") { return .onnx }
        if path.contains(".tflite") { return .tflite }
        if path.contains(".mlx") { return .mlx }
        if path.contains(".bin") { return .bin }
        if path.contains(".safetensors") { return .safetensors }
        if path.contains(".pte") { return .pte }
        if path.contains(".weights") { return .weights }
        if path.contains(".checkpoint") || path.contains(".ckpt") { return .checkpoint }

        // Check for common model hosting patterns
        if url.host?.contains("huggingface.co") == true {
            if path.contains("gguf") { return .gguf }
            if path.contains("onnx") { return .onnx }
        }

        return .unknown
    }
}
