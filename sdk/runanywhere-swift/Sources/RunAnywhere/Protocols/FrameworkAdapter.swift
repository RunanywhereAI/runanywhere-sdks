import Foundation

/// Supported LLM frameworks
public enum LLMFramework: String, CaseIterable {
    case coreML = "CoreML"
    case tensorFlowLite = "TFLite"
    case mlx = "MLX"
    case swiftTransformers = "SwiftTransformers"
    case onnx = "ONNX"
    case execuTorch = "ExecuTorch"
    case llamaCpp = "LlamaCpp"
    case foundationModels = "FoundationModels"
    case picoLLM = "PicoLLM"
    case mlc = "MLC"
}

/// Model formats supported
public enum ModelFormat: String, CaseIterable {
    case mlmodel = "mlmodel"
    case mlpackage = "mlpackage"
    case tflite = "tflite"
    case onnx = "onnx"
    case ort = "ort"
    case safetensors = "safetensors"
    case gguf = "gguf"
    case ggml = "ggml"
    case pte = "pte"
    case bin = "bin"
    case weights = "weights"
    case checkpoint = "checkpoint"
}

/// Hardware acceleration options
public enum HardwareAcceleration: String, CaseIterable {
    case cpu = "CPU"
    case gpu = "GPU"
    case neuralEngine = "NeuralEngine"
    case metal = "Metal"
    case coreML = "CoreML"
    case auto = "Auto"
}

/// Hardware configuration for framework adapters
public struct HardwareConfiguration {
    public var primaryAccelerator: HardwareAcceleration = .auto
    public var fallbackAccelerator: HardwareAcceleration? = .cpu
    public var memoryMode: MemoryMode = .balanced
    public var threadCount: Int = ProcessInfo.processInfo.processorCount
    public var useQuantization: Bool = false
    public var quantizationBits: Int = 8
    
    public enum MemoryMode {
        case conservative
        case balanced
        case aggressive
    }
    
    public init(
        primaryAccelerator: HardwareAcceleration = .auto,
        fallbackAccelerator: HardwareAcceleration? = .cpu,
        memoryMode: MemoryMode = .balanced,
        threadCount: Int = ProcessInfo.processInfo.processorCount,
        useQuantization: Bool = false,
        quantizationBits: Int = 8
    ) {
        self.primaryAccelerator = primaryAccelerator
        self.fallbackAccelerator = fallbackAccelerator
        self.memoryMode = memoryMode
        self.threadCount = threadCount
        self.useQuantization = useQuantization
        self.quantizationBits = quantizationBits
    }
}

/// Protocol for framework-specific adapters
public protocol FrameworkAdapter {
    /// The framework this adapter handles
    var framework: LLMFramework { get }
    
    /// Supported model formats
    var supportedFormats: [ModelFormat] { get }
    
    /// Check if this adapter can handle a specific model
    /// - Parameter model: The model information
    /// - Returns: Whether this adapter can handle the model
    func canHandle(model: ModelInfo) -> Bool
    
    /// Create a service instance for this framework
    /// - Returns: An LLMService implementation
    func createService() -> LLMService
    
    /// Configure the adapter with hardware settings
    /// - Parameter hardware: Hardware configuration
    func configure(with hardware: HardwareConfiguration) async
    
    /// Estimate memory usage for a model
    /// - Parameter model: The model to estimate
    /// - Returns: Estimated memory in bytes
    func estimateMemoryUsage(for model: ModelInfo) -> Int64
    
    /// Get optimal hardware configuration for a model
    /// - Parameter model: The model to configure for
    /// - Returns: Optimal hardware configuration
    func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration
}

/// Model information structure
public struct ModelInfo {
    public let id: String
    public let name: String
    public let format: ModelFormat
    public var localPath: URL?
    public let downloadURL: URL?
    public let alternativeDownloadURLs: [URL]?
    public let checksum: String?
    public let downloadSize: Int64?
    public let estimatedMemory: Int64
    public let contextLength: Int
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?
    public let hardwareRequirements: [HardwareRequirement]
    public let metadata: ModelMetadata?
    public let tokenizerFormat: TokenizerFormat?
    
    public init(
        id: String,
        name: String,
        format: ModelFormat,
        localPath: URL? = nil,
        downloadURL: URL? = nil,
        alternativeDownloadURLs: [URL]? = nil,
        checksum: String? = nil,
        downloadSize: Int64? = nil,
        estimatedMemory: Int64,
        contextLength: Int = 2048,
        compatibleFrameworks: [LLMFramework],
        preferredFramework: LLMFramework? = nil,
        hardwareRequirements: [HardwareRequirement] = [],
        metadata: ModelMetadata? = nil,
        tokenizerFormat: TokenizerFormat? = nil
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.localPath = localPath
        self.downloadURL = downloadURL
        self.alternativeDownloadURLs = alternativeDownloadURLs
        self.checksum = checksum
        self.downloadSize = downloadSize
        self.estimatedMemory = estimatedMemory
        self.contextLength = contextLength
        self.compatibleFrameworks = compatibleFrameworks
        self.preferredFramework = preferredFramework
        self.hardwareRequirements = hardwareRequirements
        self.metadata = metadata
        self.tokenizerFormat = tokenizerFormat
    }
}

/// Hardware requirements for models
public enum HardwareRequirement {
    case minimumMemory(Int64)
    case minimumCompute(String)
    case requiresNeuralEngine
    case requiresGPU
    case minimumOSVersion(String)
    case specificChip(String)
}

/// Model metadata
public struct ModelMetadata {
    public var author: String?
    public var description: String?
    public var version: String?
    public var modelType: String?
    public var architecture: String?
    public var quantization: String?
    public var formatVersion: String?
    public var inputShapes: [String: [Int]]?
    public var outputShapes: [String: [Int]]?
    public var contextLength: Int?
    public var embeddingDimension: Int?
    public var layerCount: Int?
    public var parameterCount: Int64?
    public var tensorCount: Int?
    public var requirements: ModelRequirements?
    
    public init() {}
}

/// Model requirements structure
public struct ModelRequirements {
    public let minimumMemory: Int64
    public let recommendedMemory: Int64
    public let minimumStorage: Int64
    public let supportedAccelerators: [HardwareAcceleration]
    public let minimumOSVersion: OperatingSystemVersion?
    
    public init(
        minimumMemory: Int64,
        recommendedMemory: Int64,
        minimumStorage: Int64,
        supportedAccelerators: [HardwareAcceleration],
        minimumOSVersion: OperatingSystemVersion? = nil
    ) {
        self.minimumMemory = minimumMemory
        self.recommendedMemory = recommendedMemory
        self.minimumStorage = minimumStorage
        self.supportedAccelerators = supportedAccelerators
        self.minimumOSVersion = minimumOSVersion
    }
}