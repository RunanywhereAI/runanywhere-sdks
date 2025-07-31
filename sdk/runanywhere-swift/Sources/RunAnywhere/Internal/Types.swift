import Foundation

// MARK: - Model Types

/// Information about a model
public struct ModelInfo {
    public let id: String
    public let name: String
    public let format: ModelFormat
    public let downloadURL: URL?
    public var localPath: URL?
    public let estimatedMemory: Int64
    public let contextLength: Int
    public let downloadSize: Int64?
    public let checksum: String?
    public let compatibleFrameworks: [LLMFramework]
    public let preferredFramework: LLMFramework?
    public let hardwareRequirements: [HardwareRequirement]
    public let tokenizerFormat: TokenizerFormat?
    public let metadata: [String: Any]?
    public let alternativeDownloadURLs: [URL]?
    
    public init(
        id: String,
        name: String,
        format: ModelFormat,
        downloadURL: URL? = nil,
        localPath: URL? = nil,
        estimatedMemory: Int64 = 1_000_000_000, // 1GB default
        contextLength: Int = 2048,
        downloadSize: Int64? = nil,
        checksum: String? = nil,
        compatibleFrameworks: [LLMFramework] = [],
        preferredFramework: LLMFramework? = nil,
        hardwareRequirements: [HardwareRequirement] = [],
        tokenizerFormat: TokenizerFormat? = nil,
        metadata: [String: Any]? = nil,
        alternativeDownloadURLs: [URL]? = nil
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.downloadURL = downloadURL
        self.localPath = localPath
        self.estimatedMemory = estimatedMemory
        self.contextLength = contextLength
        self.downloadSize = downloadSize
        self.checksum = checksum
        self.compatibleFrameworks = compatibleFrameworks
        self.preferredFramework = preferredFramework
        self.hardwareRequirements = hardwareRequirements
        self.tokenizerFormat = tokenizerFormat
        self.metadata = metadata
        self.alternativeDownloadURLs = alternativeDownloadURLs
    }
}


/// Resource availability information
public struct ResourceAvailability {
    public let memoryAvailable: Int64
    public let storageAvailable: Int64
    public let acceleratorsAvailable: [HardwareAcceleration]
    public let thermalState: ProcessInfo.ThermalState
    public let batteryLevel: Float?
    public let isLowPowerMode: Bool
    
    public init(
        memoryAvailable: Int64,
        storageAvailable: Int64,
        acceleratorsAvailable: [HardwareAcceleration],
        thermalState: ProcessInfo.ThermalState,
        batteryLevel: Float? = nil,
        isLowPowerMode: Bool = false
    ) {
        self.memoryAvailable = memoryAvailable
        self.storageAvailable = storageAvailable
        self.acceleratorsAvailable = acceleratorsAvailable
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
    }
    
    public func canLoad(model: ModelInfo) -> (canLoad: Bool, reason: String?) {
        // Check memory
        if model.estimatedMemory > memoryAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .memory)
            let available = ByteCountFormatter.string(fromByteCount: memoryAvailable, countStyle: .memory)
            return (false, "Insufficient memory: need \(needed), have \(available)")
        }
        
        // Check storage
        if let downloadSize = model.downloadSize, downloadSize > storageAvailable {
            let needed = ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: storageAvailable, countStyle: .file)
            return (false, "Insufficient storage: need \(needed), have \(available)")
        }
        
        // Check thermal state
        if thermalState == .critical {
            return (false, "Device is too hot, please wait for it to cool down")
        }
        
        // Check battery in low power mode
        if isLowPowerMode && batteryLevel != nil && batteryLevel! < 0.2 {
            return (false, "Battery too low for model loading in Low Power Mode")
        }
        
        return (true, nil)
    }
}

// MARK: - Internal Types

/// Request for inference
internal struct InferenceRequest {
    let id: UUID
    let prompt: String
    let options: GenerationOptions?
    let timestamp: Date
    let estimatedTokens: Int?
    let priority: RequestPriority
    
    init(
        prompt: String,
        options: GenerationOptions? = nil,
        estimatedTokens: Int? = nil,
        priority: RequestPriority = .normal
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.options = options
        self.timestamp = Date()
        self.estimatedTokens = estimatedTokens
        self.priority = priority
    }
}

/// Request priority
internal enum RequestPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: RequestPriority, rhs: RequestPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Routing decision for a request
internal enum RoutingDecision {
    case onDevice(framework: LLMFramework?, reason: RoutingReason)
    case cloud(provider: String?, reason: RoutingReason)
    case hybrid(devicePortion: Double, framework: LLMFramework?, reason: RoutingReason)
    
    var executionTarget: ExecutionTarget {
        switch self {
        case .onDevice:
            return .onDevice
        case .cloud:
            return .cloud
        case .hybrid:
            return .hybrid
        }
    }
    
    /// Get the selected framework if on-device
    var selectedFramework: LLMFramework? {
        switch self {
        case .onDevice(let framework, _):
            return framework
        case .hybrid(_, let framework, _):
            return framework
        case .cloud:
            return nil
        }
    }
}

/// Reason for routing decision
internal enum RoutingReason {
    case privacySensitive
    case insufficientResources(String)
    case lowComplexity
    case highComplexity
    case policyDriven(RoutingPolicy)
    case userPreference(ExecutionTarget)
    case frameworkUnavailable(LLMFramework)
    case costOptimization(savedAmount: Double)
    case latencyOptimization(expectedMs: TimeInterval)
    case modelNotAvailable
    
    /// Human-readable description
    var description: String {
        switch self {
        case .privacySensitive:
            return "Privacy-sensitive content detected"
        case .insufficientResources(let resource):
            return "Insufficient \(resource)"
        case .lowComplexity:
            return "Low complexity task suitable for device"
        case .highComplexity:
            return "High complexity task requiring cloud"
        case .policyDriven(let policy):
            return "Policy-driven decision: \(policy.rawValue)"
        case .userPreference(let target):
            return "User preference: \(target.rawValue)"
        case .frameworkUnavailable(let framework):
            return "\(framework.rawValue) not available"
        case .costOptimization(let saved):
            return "Cost optimization: saving $\(String(format: "%.2f", saved))"
        case .latencyOptimization(let ms):
            return "Latency optimization: \(Int(ms))ms expected"
        case .modelNotAvailable:
            return "Model not available on device"
        }
    }
}

/// Routing context for decision making
internal struct RoutingContext {
    let request: InferenceRequest
    let availableModels: [ModelInfo]
    let resourceAvailability: ResourceAvailability
    let configuration: Configuration
    let costEstimates: CostEstimates?
    
    struct CostEstimates {
        let onDeviceCost: Double
        let cloudCost: Double
        let hybridCost: Double
    }
}

/// Model selection result
internal struct ModelSelection {
    let model: ModelInfo
    let framework: LLMFramework
    let adapter: FrameworkAdapter?
    let fallbackOptions: [ModelSelection]?
    
    init(
        model: ModelInfo,
        framework: LLMFramework,
        adapter: FrameworkAdapter? = nil,
        fallbackOptions: [ModelSelection]? = nil
    ) {
        self.model = model
        self.framework = framework
        self.adapter = adapter
        self.fallbackOptions = fallbackOptions
    }
}
