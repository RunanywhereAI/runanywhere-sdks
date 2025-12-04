import 'privacy_mode.dart';
import 'routing_policy.dart';

/// Configuration for routing behavior.
/// Matches iOS RoutingConfiguration from Configuration/RoutingConfiguration.swift
class RoutingConfiguration {
  /// The routing policy to use
  final RoutingPolicy policy;

  /// Whether cloud routing is enabled
  final bool cloudEnabled;

  /// Privacy mode for routing decisions
  final PrivacyMode privacyMode;

  /// Custom routing rules (only used when policy is .custom)
  final Map<String, String> customRules;

  /// Maximum latency threshold for routing decisions (milliseconds)
  final int? maxLatencyThreshold;

  /// Minimum confidence score for on-device execution (0.0 - 1.0)
  final double? minConfidenceScore;

  const RoutingConfiguration({
    this.policy = RoutingPolicy.deviceOnly,
    this.cloudEnabled = false,
    this.privacyMode = PrivacyMode.standard,
    this.customRules = const {},
    this.maxLatencyThreshold,
    this.minConfidenceScore,
  });

  /// Create from JSON map
  factory RoutingConfiguration.fromJson(Map<String, dynamic> json) {
    return RoutingConfiguration(
      policy: RoutingPolicy.fromRawValue(json['policy'] as String? ?? 'device_only') ??
          RoutingPolicy.deviceOnly,
      cloudEnabled: json['cloudEnabled'] as bool? ?? false,
      privacyMode: PrivacyMode.fromRawValue(json['privacyMode'] as String? ?? 'standard') ??
          PrivacyMode.standard,
      customRules: (json['customRules'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      maxLatencyThreshold: json['maxLatencyThreshold'] as int?,
      minConfidenceScore: (json['minConfidenceScore'] as num?)?.toDouble(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'policy': policy.rawValue,
      'cloudEnabled': cloudEnabled,
      'privacyMode': privacyMode.rawValue,
      'customRules': customRules,
      if (maxLatencyThreshold != null) 'maxLatencyThreshold': maxLatencyThreshold,
      if (minConfidenceScore != null) 'minConfidenceScore': minConfidenceScore,
    };
  }

  /// Create a copy with updated fields
  RoutingConfiguration copyWith({
    RoutingPolicy? policy,
    bool? cloudEnabled,
    PrivacyMode? privacyMode,
    Map<String, String>? customRules,
    int? maxLatencyThreshold,
    double? minConfidenceScore,
  }) {
    return RoutingConfiguration(
      policy: policy ?? this.policy,
      cloudEnabled: cloudEnabled ?? this.cloudEnabled,
      privacyMode: privacyMode ?? this.privacyMode,
      customRules: customRules ?? this.customRules,
      maxLatencyThreshold: maxLatencyThreshold ?? this.maxLatencyThreshold,
      minConfidenceScore: minConfidenceScore ?? this.minConfidenceScore,
    );
  }
}
