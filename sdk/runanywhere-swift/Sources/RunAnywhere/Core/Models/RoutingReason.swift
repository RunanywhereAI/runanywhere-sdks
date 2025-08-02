import Foundation

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
