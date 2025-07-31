import Foundation

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