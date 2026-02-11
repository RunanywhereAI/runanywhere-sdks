//
//  CloudTypes.swift
//  RunAnywhere SDK
//
//  Types for cloud provider infrastructure and routing.
//

import CRACommons
import Foundation

// MARK: - Routing Mode

/// Routing mode for inference requests
public enum RoutingMode: String, Sendable, Codable {
    /// Never use cloud - all inference on-device only
    case alwaysLocal = "always_local"

    /// Always use cloud - skip on-device inference
    case alwaysCloud = "always_cloud"

    /// On-device first, auto-fallback to cloud on low confidence
    case hybridAuto = "hybrid_auto"

    /// On-device first, return handoff signal for app to decide
    case hybridManual = "hybrid_manual"
}

// MARK: - Execution Target

/// Where inference was actually executed
public enum ExecutionTarget: String, Sendable, Codable {
    case onDevice = "on_device"
    case cloud = "cloud"
    case hybridFallback = "hybrid_fallback"
}

// MARK: - Handoff Reason

/// Reason why the on-device engine recommended cloud handoff
public enum HandoffReason: Int, Sendable, Codable {
    /// No handoff needed
    case none = 0

    /// First token had low confidence
    case firstTokenLowConfidence = 1

    /// Rolling window showed degrading confidence
    case rollingWindowDegradation = 2
}

// MARK: - Routing Policy

/// Policy controlling how requests are routed between on-device and cloud
public struct RoutingPolicy: Sendable {

    /// Routing mode
    public let mode: RoutingMode

    /// Confidence threshold for cloud handoff (0.0 - 1.0)
    /// Only relevant for hybrid modes.
    public let confidenceThreshold: Float

    /// Max on-device time-to-first-token before cloud fallback (ms).
    /// 0 = no limit.
    public let maxLocalLatencyMs: UInt32

    /// Max cloud cost per request in USD. 0.0 = no cap.
    public let costCapUSD: Float

    /// Whether to prefer streaming for cloud calls
    public let preferStreaming: Bool

    public init(
        mode: RoutingMode = .hybridManual,
        confidenceThreshold: Float = 0.7,
        maxLocalLatencyMs: UInt32 = 0,
        costCapUSD: Float = 0.0,
        preferStreaming: Bool = true
    ) {
        self.mode = mode
        self.confidenceThreshold = confidenceThreshold
        self.maxLocalLatencyMs = maxLocalLatencyMs
        self.costCapUSD = costCapUSD
        self.preferStreaming = preferStreaming
    }

    // MARK: - Convenience Factories

    /// Always run on-device, never use cloud
    public static let localOnly = RoutingPolicy(mode: .alwaysLocal, confidenceThreshold: 0.0)

    /// Always use cloud provider
    public static let cloudOnly = RoutingPolicy(mode: .alwaysCloud, confidenceThreshold: 0.0)

    /// Hybrid mode with automatic cloud fallback
    public static func hybridAuto(confidenceThreshold: Float = 0.7) -> RoutingPolicy {
        RoutingPolicy(mode: .hybridAuto, confidenceThreshold: confidenceThreshold)
    }

    /// Hybrid mode returning handoff signal (app decides)
    public static func hybridManual(confidenceThreshold: Float = 0.7) -> RoutingPolicy {
        RoutingPolicy(mode: .hybridManual, confidenceThreshold: confidenceThreshold)
    }
}

// MARK: - Routing Decision

/// Metadata about how a generation request was routed
public struct RoutingDecision: Sendable {

    /// Where inference was executed
    public let executionTarget: ExecutionTarget

    /// The routing policy that was applied
    public let policy: RoutingPolicy

    /// On-device confidence score (0.0 - 1.0)
    public let onDeviceConfidence: Float

    /// Whether cloud handoff was triggered
    public let cloudHandoffTriggered: Bool

    /// Reason for cloud handoff
    public let handoffReason: HandoffReason

    /// Cloud provider ID used (nil if on-device only)
    public let cloudProviderId: String?

    /// Cloud model used (nil if on-device only)
    public let cloudModel: String?

    public init(
        executionTarget: ExecutionTarget,
        policy: RoutingPolicy,
        onDeviceConfidence: Float = 1.0,
        cloudHandoffTriggered: Bool = false,
        handoffReason: HandoffReason = .none,
        cloudProviderId: String? = nil,
        cloudModel: String? = nil
    ) {
        self.executionTarget = executionTarget
        self.policy = policy
        self.onDeviceConfidence = onDeviceConfidence
        self.cloudHandoffTriggered = cloudHandoffTriggered
        self.handoffReason = handoffReason
        self.cloudProviderId = cloudProviderId
        self.cloudModel = cloudModel
    }
}

// MARK: - Cloud Generation Options

/// Options specific to cloud-based generation
public struct CloudGenerationOptions: Sendable {

    /// Cloud model identifier (e.g., "gpt-4o-mini")
    public let model: String

    /// Maximum tokens to generate
    public let maxTokens: Int

    /// Temperature for sampling
    public let temperature: Float

    /// System prompt
    public let systemPrompt: String?

    /// Messages in chat format (role, content pairs)
    public let messages: [(role: String, content: String)]?

    public init(
        model: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.7,
        systemPrompt: String? = nil,
        messages: [(role: String, content: String)]? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.messages = messages
    }
}

// MARK: - Cloud Generation Result

/// Result from cloud-based generation
public struct CloudGenerationResult: Sendable {

    /// Generated text
    public let text: String

    /// Tokens used (input + output)
    public let inputTokens: Int
    public let outputTokens: Int

    /// Total latency in milliseconds
    public let latencyMs: Double

    /// Provider that handled the request
    public let providerId: String

    /// Model used
    public let model: String

    /// Estimated cost in USD (nil if unknown)
    public let estimatedCostUSD: Double?

    public init(
        text: String,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        latencyMs: Double = 0,
        providerId: String,
        model: String,
        estimatedCostUSD: Double? = nil
    ) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
        self.providerId = providerId
        self.model = model
        self.estimatedCostUSD = estimatedCostUSD
    }
}
