import Foundation

/// Configuration for routing behavior
public struct RoutingConfiguration: Codable, Sendable {
    /// The routing policy to use
    public var policy: RoutingPolicy

    /// Whether cloud routing is enabled
    public var cloudEnabled: Bool

    /// Privacy mode for routing decisions
    public var privacyMode: PrivacyMode

    /// Custom routing rules (only used when policy is .custom)
    /// Note: Using a dictionary of strings for Sendable conformance
    public var customRules: [String: String]

    /// Maximum latency threshold for routing decisions (milliseconds)
    public var maxLatencyThreshold: Int?

    /// Minimum confidence score for on-device execution (0.0 - 1.0)
    public var minConfidenceScore: Double?

    public init(
        policy: RoutingPolicy = .deviceOnly,
        cloudEnabled: Bool = false,
        privacyMode: PrivacyMode = .standard,
        customRules: [String: String] = [:],
        maxLatencyThreshold: Int? = nil,
        minConfidenceScore: Double? = nil
    ) {
        self.policy = policy
        self.cloudEnabled = cloudEnabled
        self.privacyMode = privacyMode
        self.customRules = customRules
        self.maxLatencyThreshold = maxLatencyThreshold
        self.minConfidenceScore = minConfidenceScore
    }

    // Custom encoding/decoding to handle [String: Any]
    private enum CodingKeys: String, CodingKey {
        case policy, cloudEnabled, privacyMode, customRules
        case maxLatencyThreshold, minConfidenceScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        policy = try container.decode(RoutingPolicy.self, forKey: .policy)
        cloudEnabled = try container.decode(Bool.self, forKey: .cloudEnabled)
        privacyMode = try container.decode(PrivacyMode.self, forKey: .privacyMode)
        maxLatencyThreshold = try container.decodeIfPresent(Int.self, forKey: .maxLatencyThreshold)
        minConfidenceScore = try container.decodeIfPresent(Double.self, forKey: .minConfidenceScore)

        // Handle custom rules as JSON string dictionary
        customRules = try container.decodeIfPresent([String: String].self, forKey: .customRules) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(policy, forKey: .policy)
        try container.encode(cloudEnabled, forKey: .cloudEnabled)
        try container.encode(privacyMode, forKey: .privacyMode)
        try container.encodeIfPresent(maxLatencyThreshold, forKey: .maxLatencyThreshold)
        try container.encodeIfPresent(minConfidenceScore, forKey: .minConfidenceScore)

        // Handle custom rules as JSON string dictionary
        try container.encodeIfPresent(customRules, forKey: .customRules)
    }
}
