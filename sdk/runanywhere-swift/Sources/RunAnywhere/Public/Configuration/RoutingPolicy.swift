import Foundation

/// Routing policy determines how requests are routed between device and cloud
public enum RoutingPolicy: String, Codable {
    /// Automatically determine best execution target
    case automatic

    /// Always use on-device execution when possible
    case preferDevice

    /// Always use cloud execution
    case preferCloud

    /// Use custom routing rules
    case custom
}
