/// Cloud Types
///
/// Types for cloud provider infrastructure and routing.
/// Mirrors Swift CloudTypes.swift from Public/Extensions/Cloud/CloudTypes.swift
library cloud_types;

// MARK: - Routing Mode

/// Routing mode for inference requests
enum RoutingMode {
  /// Never use cloud - all inference on-device only
  alwaysLocal('always_local'),

  /// Always use cloud - skip on-device inference
  alwaysCloud('always_cloud'),

  /// On-device first, auto-fallback to cloud on low confidence
  hybridAuto('hybrid_auto'),

  /// On-device first, return handoff signal for app to decide
  hybridManual('hybrid_manual');

  const RoutingMode(this.value);
  final String value;
}

// MARK: - Execution Target

/// Where inference was actually executed
enum ExecutionTarget {
  onDevice('on_device'),
  cloud('cloud'),
  hybridFallback('hybrid_fallback');

  const ExecutionTarget(this.value);
  final String value;
}

// MARK: - Handoff Reason

/// Reason why the on-device engine recommended cloud handoff
enum HandoffReason {
  /// No handoff needed
  none(0),

  /// First token had low confidence
  firstTokenLowConfidence(1),

  /// Rolling window showed degrading confidence
  rollingWindowDegradation(2);

  const HandoffReason(this.code);
  final int code;

  /// Look up a HandoffReason by its integer code.
  /// Returns [HandoffReason.none] if the code is unknown.
  static HandoffReason fromCode(int code) {
    return HandoffReason.values.firstWhere(
      (r) => r.code == code,
      orElse: () => HandoffReason.none,
    );
  }
}

// MARK: - Routing Policy

/// Policy controlling how requests are routed between on-device and cloud.
///
/// Matches Swift RoutingPolicy struct.
class RoutingPolicy {
  /// Routing mode
  final RoutingMode mode;

  /// Confidence threshold for cloud handoff (0.0 - 1.0).
  /// Only relevant for hybrid modes.
  final double confidenceThreshold;

  /// Max on-device time-to-first-token before cloud fallback (ms).
  /// 0 = no limit.
  final int maxLocalLatencyMs;

  /// Max cloud cost per request in USD. 0.0 = no cap.
  final double costCapUSD;

  /// Whether to prefer streaming for cloud calls
  final bool preferStreaming;

  const RoutingPolicy({
    this.mode = RoutingMode.hybridManual,
    this.confidenceThreshold = 0.7,
    this.maxLocalLatencyMs = 0,
    this.costCapUSD = 0.0,
    this.preferStreaming = true,
  });

  // MARK: - Convenience Factories

  /// Always run on-device, never use cloud
  static const localOnly = RoutingPolicy(
    mode: RoutingMode.alwaysLocal,
    confidenceThreshold: 0.0,
  );

  /// Always use cloud provider
  static const cloudOnly = RoutingPolicy(
    mode: RoutingMode.alwaysCloud,
    confidenceThreshold: 0.0,
  );

  /// Hybrid mode with automatic cloud fallback
  static RoutingPolicy hybridAuto({double confidenceThreshold = 0.7}) =>
      RoutingPolicy(
        mode: RoutingMode.hybridAuto,
        confidenceThreshold: confidenceThreshold,
      );

  /// Hybrid mode returning handoff signal (app decides)
  static RoutingPolicy hybridManual({double confidenceThreshold = 0.7}) =>
      RoutingPolicy(
        mode: RoutingMode.hybridManual,
        confidenceThreshold: confidenceThreshold,
      );

  @override
  String toString() =>
      'RoutingPolicy(mode: ${mode.value}, threshold: $confidenceThreshold)';
}

// MARK: - Routing Decision

/// Metadata about how a generation request was routed.
///
/// Matches Swift RoutingDecision struct.
class RoutingDecision {
  /// Where inference was executed
  final ExecutionTarget executionTarget;

  /// The routing policy that was applied
  final RoutingPolicy policy;

  /// On-device confidence score (0.0 - 1.0)
  final double onDeviceConfidence;

  /// Whether cloud handoff was triggered
  final bool cloudHandoffTriggered;

  /// Reason for cloud handoff
  final HandoffReason handoffReason;

  /// Cloud provider ID used (null if on-device only)
  final String? cloudProviderId;

  /// Cloud model used (null if on-device only)
  final String? cloudModel;

  const RoutingDecision({
    required this.executionTarget,
    required this.policy,
    this.onDeviceConfidence = 1.0,
    this.cloudHandoffTriggered = false,
    this.handoffReason = HandoffReason.none,
    this.cloudProviderId,
    this.cloudModel,
  });

  @override
  String toString() =>
      'RoutingDecision(target: ${executionTarget.value}, '
      'confidence: $onDeviceConfidence, '
      'handoff: $cloudHandoffTriggered)';
}

// MARK: - Cloud Generation Options

/// Options specific to cloud-based generation.
///
/// Matches Swift CloudGenerationOptions struct.
class CloudGenerationOptions {
  /// Cloud model identifier (e.g., "gpt-4o-mini")
  final String model;

  /// Maximum tokens to generate
  final int maxTokens;

  /// Temperature for sampling
  final double temperature;

  /// System prompt
  final String? systemPrompt;

  /// Messages in chat format (role, content pairs)
  final List<ChatMessage>? messages;

  const CloudGenerationOptions({
    required this.model,
    this.maxTokens = 1024,
    this.temperature = 0.7,
    this.systemPrompt,
    this.messages,
  });
}

/// A single chat message (role + content pair).
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

// MARK: - Cloud Generation Result

/// Result from cloud-based generation.
///
/// Matches Swift CloudGenerationResult struct.
class CloudGenerationResult {
  /// Generated text
  final String text;

  /// Tokens used (input)
  final int inputTokens;

  /// Tokens used (output)
  final int outputTokens;

  /// Total latency in milliseconds
  final double latencyMs;

  /// Provider that handled the request
  final String providerId;

  /// Model used
  final String model;

  /// Estimated cost in USD (null if unknown)
  final double? estimatedCostUSD;

  const CloudGenerationResult({
    required this.text,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.latencyMs = 0,
    required this.providerId,
    required this.model,
    this.estimatedCostUSD,
  });

  @override
  String toString() =>
      'CloudGenerationResult(provider: $providerId, model: $model, '
      'tokens: $outputTokens, latency: ${latencyMs.toStringAsFixed(1)}ms)';
}
