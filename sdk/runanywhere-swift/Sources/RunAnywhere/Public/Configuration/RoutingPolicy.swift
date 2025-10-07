import Foundation

/// Routing policy determines how requests are routed between device and cloud
public enum RoutingPolicy: String, Codable {
    /// Automatically determine best execution target
    case automatic

    /// Always use on-device execution when possible
    case preferDevice

    /// ONLY use on-device execution - never use cloud
    case deviceOnly

    /// Always use cloud execution
    case preferCloud

    /// Use custom routing rules
    case custom
}
