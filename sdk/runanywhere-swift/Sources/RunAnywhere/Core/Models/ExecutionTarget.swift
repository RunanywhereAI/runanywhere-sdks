import Foundation

/// Execution target for model inference
public enum ExecutionTarget: String, Codable, Sendable {
    /// Execute on device
    case onDevice

    /// Execute in the cloud
    case cloud

    /// Hybrid execution (partial on-device, partial cloud)
    case hybrid
}
