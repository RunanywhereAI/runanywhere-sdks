import Foundation

/// Protocol for LLM service implementations
public protocol LLMService: AnyObject {
    /// Initialize the service with a model
    /// - Parameter modelPath: Path to the model file
    func initialize(modelPath: String) async throws

    /// Generate text from a prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: Generated text
    func generate(prompt: String, options: GenerationOptions) async throws -> String

    /// Stream generate text from a prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    ///   - onToken: Callback for each generated token
    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws

    /// Clean up resources
    func cleanup() async

    /// Get current memory usage
    /// - Returns: Memory usage in bytes
    func getModelMemoryUsage() async throws -> Int64

    /// Check if the service is ready
    var isReady: Bool { get }

    /// Get model information
    var modelInfo: LoadedModelInfo? { get }

    /// Set generation context
    /// - Parameter context: The context to use
    func setContext(_ context: Context) async

    /// Clear generation context
    func clearContext() async
}

/// Information about a loaded model
public struct LoadedModelInfo {
    public let id: String
    public let name: String
    public let framework: LLMFramework
    public let format: ModelFormat
    public let memoryUsage: Int64
    public let contextLength: Int
    public let loadedAt: Date
    public let configuration: HardwareConfiguration

    public init(
        id: String,
        name: String,
        framework: LLMFramework,
        format: ModelFormat,
        memoryUsage: Int64,
        contextLength: Int,
        loadedAt: Date = Date(),
        configuration: HardwareConfiguration
    ) {
        self.id = id
        self.name = name
        self.framework = framework
        self.format = format
        self.memoryUsage = memoryUsage
        self.contextLength = contextLength
        self.loadedAt = loadedAt
        self.configuration = configuration
    }
}


/// LLM service errors
public enum LLMServiceError: LocalizedError {
    case notInitialized
    case modelNotLoaded
    case generationFailed(String)
    case contextTooLong(Int, Int)
    case unsupportedOperation(String)
    case frameworkError(FrameworkError)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Service not initialized"
        case .modelNotLoaded:
            return "Model not loaded"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .contextTooLong(let current, let max):
            return "Context too long: \(current) tokens (max: \(max))"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .frameworkError(let error):
            return "Framework error: \(error.localizedDescription)"
        }
    }
}

/// Framework-specific errors
public struct FrameworkError: LocalizedError {
    public let framework: LLMFramework
    public let underlying: Error
    public let context: String?

    public init(framework: LLMFramework, underlying: Error, context: String? = nil) {
        self.framework = framework
        self.underlying = underlying
        self.context = context
    }

    public var errorDescription: String? {
        var description = "\(framework.rawValue) error: \(underlying.localizedDescription)"
        if let context = context {
            description += " (\(context))"
        }
        return description
    }
}
