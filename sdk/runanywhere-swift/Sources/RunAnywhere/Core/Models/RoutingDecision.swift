import Foundation

/// Routing decision for a request
public enum RoutingDecision {
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
