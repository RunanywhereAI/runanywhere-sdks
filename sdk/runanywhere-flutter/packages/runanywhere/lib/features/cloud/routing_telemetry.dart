/// Routing Telemetry
///
/// Telemetry events for routing decisions and cloud usage.
/// Mirrors Swift RoutingTelemetry.swift from Features/Cloud/RoutingTelemetry.swift
library routing_telemetry;

import 'package:runanywhere/features/cloud/cloud_types.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

// MARK: - Routing Event

/// Event emitted when a routing decision is made.
///
/// Subscribe via EventBus to track routing patterns:
/// ```dart
/// EventBus.shared.allEvents
///     .where((e) => e is RoutingTelemetryEvent)
///     .cast<RoutingTelemetryEvent>()
///     .listen((event) {
///       print('Routed to ${event.executionTarget}, confidence: ${event.confidence}');
///     });
/// ```
///
/// Matches Swift RoutingEvent struct.
class RoutingTelemetryEvent with SDKEventDefaults {
  @override
  String get type => 'routing.decision';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  EventDestination get destination => EventDestination.all;

  // MARK: - Routing-Specific Properties

  /// The routing mode that was configured
  final RoutingMode routingMode;

  /// Where inference was actually executed
  final ExecutionTarget executionTarget;

  /// On-device confidence score (0.0-1.0)
  final double confidence;

  /// Whether cloud handoff was triggered
  final bool cloudHandoffTriggered;

  /// Reason for handoff
  final HandoffReason handoffReason;

  /// Cloud provider used (null if on-device only)
  final String? cloudProviderId;

  /// Cloud model used (null if on-device only)
  final String? cloudModel;

  /// Total latency in milliseconds
  final double latencyMs;

  /// Estimated cloud cost in USD (null for on-device)
  final double? estimatedCostUSD;

  RoutingTelemetryEvent({
    required this.routingMode,
    required this.executionTarget,
    required this.confidence,
    required this.cloudHandoffTriggered,
    required this.handoffReason,
    this.cloudProviderId,
    this.cloudModel,
    required this.latencyMs,
    this.estimatedCostUSD,
  });

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'routing_mode': routingMode.value,
      'execution_target': executionTarget.value,
      'confidence': confidence.toStringAsFixed(4),
      'cloud_handoff': cloudHandoffTriggered.toString(),
      'handoff_reason': handoffReason.code.toString(),
      'latency_ms': latencyMs.toStringAsFixed(1),
    };
    if (cloudProviderId != null) {
      props['cloud_provider_id'] = cloudProviderId!;
    }
    if (cloudModel != null) {
      props['cloud_model'] = cloudModel!;
    }
    if (estimatedCostUSD != null) {
      props['estimated_cost_usd'] = estimatedCostUSD!.toStringAsFixed(6);
    }
    return props;
  }
}

// MARK: - Cost Event

/// Event emitted when a cloud request incurs cost.
///
/// Matches Swift CloudCostEvent struct.
class CloudCostTelemetryEvent with SDKEventDefaults {
  @override
  String get type => 'cloud.cost';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  /// Provider that incurred the cost
  final String providerId;

  /// Input tokens
  final int inputTokens;

  /// Output tokens
  final int outputTokens;

  /// Estimated cost in USD
  final double costUSD;

  /// Cumulative total after this request
  final double cumulativeTotalUSD;

  CloudCostTelemetryEvent({
    required this.providerId,
    required this.inputTokens,
    required this.outputTokens,
    required this.costUSD,
    required this.cumulativeTotalUSD,
  });

  @override
  Map<String, String> get properties => {
        'provider_id': providerId,
        'input_tokens': inputTokens.toString(),
        'output_tokens': outputTokens.toString(),
        'cost_usd': costUSD.toStringAsFixed(6),
        'cumulative_total_usd': cumulativeTotalUSD.toStringAsFixed(6),
      };
}

// MARK: - Provider Failover Event

/// Event emitted when a provider failover occurs.
///
/// Matches Swift ProviderFailoverEvent struct.
class ProviderFailoverTelemetryEvent with SDKEventDefaults {
  @override
  String get type => 'cloud.provider_failover';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  EventDestination get destination => EventDestination.all;

  /// Provider that failed
  final String failedProviderId;

  /// Provider that was used as fallback
  final String? fallbackProviderId;

  /// Error from the failed provider
  final String failureReason;

  ProviderFailoverTelemetryEvent({
    required this.failedProviderId,
    this.fallbackProviderId,
    required this.failureReason,
  });

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'failed_provider_id': failedProviderId,
      'failure_reason': failureReason,
    };
    if (fallbackProviderId != null) {
      props['fallback_provider_id'] = fallbackProviderId!;
    }
    return props;
  }
}

// MARK: - Latency Timeout Event

/// Event emitted when a latency timeout triggers cloud fallback.
///
/// Matches Swift LatencyTimeoutEvent struct.
class LatencyTimeoutTelemetryEvent with SDKEventDefaults {
  @override
  String get type => 'routing.latency_timeout';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  EventDestination get destination => EventDestination.all;

  /// Maximum allowed latency (ms)
  final int maxLatencyMs;

  /// Actual elapsed time before timeout (ms)
  final double actualLatencyMs;

  LatencyTimeoutTelemetryEvent({
    required this.maxLatencyMs,
    required this.actualLatencyMs,
  });

  @override
  Map<String, String> get properties => {
        'max_latency_ms': maxLatencyMs.toString(),
        'actual_latency_ms': actualLatencyMs.toStringAsFixed(1),
      };
}
