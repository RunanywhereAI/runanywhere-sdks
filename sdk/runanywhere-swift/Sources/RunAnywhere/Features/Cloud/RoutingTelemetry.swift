//
//  RoutingTelemetry.swift
//  RunAnywhere SDK
//
//  Telemetry events for routing decisions and cloud usage.
//

import Foundation

// MARK: - Routing Event

/// Event emitted when a routing decision is made.
///
/// Subscribe via EventBus to track routing patterns:
/// ```swift
/// EventBus.shared.events(for: .llm)
///     .compactMap { $0 as? RoutingEvent }
///     .sink { event in
///         print("Routed to \(event.executionTarget), confidence: \(event.confidence)")
///     }
/// ```
public struct RoutingEvent: SDKEvent {
    public let id: String = UUID().uuidString
    public let type: String = "routing.decision"
    public let category: EventCategory = .llm
    public let timestamp: Date = Date()
    public let sessionId: String? = nil
    public let destination: EventDestination = .all

    // MARK: - Routing-Specific Properties

    /// The routing mode that was configured
    public let routingMode: RoutingMode

    /// Where inference was actually executed
    public let executionTarget: ExecutionTarget

    /// On-device confidence score (0.0-1.0)
    public let confidence: Float

    /// Whether cloud handoff was triggered
    public let cloudHandoffTriggered: Bool

    /// Reason for handoff
    public let handoffReason: HandoffReason

    /// Cloud provider used (nil if on-device only)
    public let cloudProviderId: String?

    /// Cloud model used (nil if on-device only)
    public let cloudModel: String?

    /// Total latency in milliseconds
    public let latencyMs: Double

    /// Estimated cloud cost in USD (nil for on-device)
    public let estimatedCostUSD: Double?

    // MARK: - SDKEvent

    public var properties: [String: String] {
        var props: [String: String] = [
            "routing_mode": routingMode.rawValue,
            "execution_target": executionTarget.rawValue,
            "confidence": String(format: "%.4f", confidence),
            "cloud_handoff": String(cloudHandoffTriggered),
            "handoff_reason": String(handoffReason.rawValue),
            "latency_ms": String(format: "%.1f", latencyMs),
        ]
        if let id = cloudProviderId { props["cloud_provider_id"] = id }
        if let model = cloudModel { props["cloud_model"] = model }
        if let cost = estimatedCostUSD { props["estimated_cost_usd"] = String(format: "%.6f", cost) }
        return props
    }
}

// MARK: - Cost Event

/// Event emitted when a cloud request incurs cost.
public struct CloudCostEvent: SDKEvent {
    public let id: String = UUID().uuidString
    public let type: String = "cloud.cost"
    public let category: EventCategory = .llm
    public let timestamp: Date = Date()
    public let sessionId: String? = nil
    public let destination: EventDestination = .analyticsOnly

    /// Provider that incurred the cost
    public let providerId: String

    /// Input tokens
    public let inputTokens: Int

    /// Output tokens
    public let outputTokens: Int

    /// Estimated cost in USD
    public let costUSD: Double

    /// Cumulative total after this request
    public let cumulativeTotalUSD: Double

    public var properties: [String: String] {
        [
            "provider_id": providerId,
            "input_tokens": String(inputTokens),
            "output_tokens": String(outputTokens),
            "cost_usd": String(format: "%.6f", costUSD),
            "cumulative_total_usd": String(format: "%.6f", cumulativeTotalUSD),
        ]
    }
}

// MARK: - Provider Failover Event

/// Event emitted when a provider failover occurs.
public struct ProviderFailoverEvent: SDKEvent {
    public let id: String = UUID().uuidString
    public let type: String = "cloud.provider_failover"
    public let category: EventCategory = .llm
    public let timestamp: Date = Date()
    public let sessionId: String? = nil
    public let destination: EventDestination = .all

    /// Provider that failed
    public let failedProviderId: String

    /// Provider that was used as fallback
    public let fallbackProviderId: String?

    /// Error from the failed provider
    public let failureReason: String

    public var properties: [String: String] {
        var props: [String: String] = [
            "failed_provider_id": failedProviderId,
            "failure_reason": failureReason,
        ]
        if let fallback = fallbackProviderId {
            props["fallback_provider_id"] = fallback
        }
        return props
    }
}

// MARK: - Latency Timeout Event

/// Event emitted when a latency timeout triggers cloud fallback.
public struct LatencyTimeoutEvent: SDKEvent {
    public let id: String = UUID().uuidString
    public let type: String = "routing.latency_timeout"
    public let category: EventCategory = .llm
    public let timestamp: Date = Date()
    public let sessionId: String? = nil
    public let destination: EventDestination = .all

    /// Maximum allowed latency (ms)
    public let maxLatencyMs: UInt32

    /// Actual elapsed time before timeout (ms)
    public let actualLatencyMs: Double

    public var properties: [String: String] {
        [
            "max_latency_ms": String(maxLatencyMs),
            "actual_latency_ms": String(format: "%.1f", actualLatencyMs),
        ]
    }
}
