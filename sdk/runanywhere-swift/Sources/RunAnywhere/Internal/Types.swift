import Foundation

// MARK: - Internal Types

/// Request for inference
internal struct InferenceRequest {
    let id: UUID
    let prompt: String
    let options: GenerationOptions?
    let timestamp: Date
    
    init(prompt: String, options: GenerationOptions? = nil) {
        self.id = UUID()
        self.prompt = prompt
        self.options = options
        self.timestamp = Date()
    }
}

/// Routing decision for a request
internal enum RoutingDecision {
    case onDevice(reason: RoutingReason)
    case cloud(reason: RoutingReason)
    case hybrid(devicePortion: Double, reason: RoutingReason)
    
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
}

/// Reason for routing decision
internal enum RoutingReason {
    case privacySensitive
    case insufficientResources
    case lowComplexity
    case highComplexity
    case policyDriven
    case userPreference
}