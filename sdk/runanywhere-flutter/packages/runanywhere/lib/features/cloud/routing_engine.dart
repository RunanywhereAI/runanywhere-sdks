/// Routing Engine
///
/// Orchestrates routing between on-device and cloud inference
/// based on the configured routing policy.
///
/// Mirrors Swift RoutingEngine actor from Features/Cloud/RoutingEngine.swift
///
/// Phase 5 features:
/// - Cost tracking via `CloudCostTracker`
/// - Telemetry events via `EventBus`
/// - Latency-based routing (TTFT timeout)
/// - Provider failover chain
library routing_engine;

import 'dart:async';
import 'dart:math';

import 'package:runanywhere/features/cloud/cloud_cost_tracker.dart';
import 'package:runanywhere/features/cloud/cloud_provider.dart';
import 'package:runanywhere/features/cloud/cloud_provider_manager.dart';
import 'package:runanywhere/features/cloud/cloud_types.dart';
import 'package:runanywhere/features/cloud/provider_failover_chain.dart';
import 'package:runanywhere/features/cloud/routing_telemetry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/runanywhere.dart';
import 'package:runanywhere/public/types/generation_types.dart';

// MARK: - Routing Engine

/// Orchestrates generation routing between on-device (C++) and cloud providers.
///
/// Implements the routing decision logic:
/// - ALWAYS_LOCAL: Call C++ directly (existing path)
/// - ALWAYS_CLOUD: Call CloudProviderManager
/// - HYBRID_AUTO: On-device first, auto-fallback to cloud if confidence is low
/// - HYBRID_MANUAL: On-device first, return handoff signal in result
class RoutingEngine {
  static final RoutingEngine shared = RoutingEngine._();

  RoutingEngine._();

  final SDKLogger _logger = SDKLogger('RoutingEngine');

  /// Default routing policy for all requests
  RoutingPolicy _defaultPolicy = const RoutingPolicy();

  /// Optional failover chain for cloud providers
  ProviderFailoverChain? _failoverChain;

  // MARK: - Configuration

  /// Set the default routing policy
  void setDefaultPolicy(RoutingPolicy policy) {
    _defaultPolicy = policy;
    _logger.debug('Default routing policy set: ${policy.mode.value}');
  }

  /// Get the current default routing policy
  RoutingPolicy get defaultPolicy => _defaultPolicy;

  /// Set the provider failover chain
  void setFailoverChain(ProviderFailoverChain? chain) {
    _failoverChain = chain;
  }

  /// Get the current failover chain
  ProviderFailoverChain? getFailoverChain() => _failoverChain;

  // MARK: - Cost Summary

  /// Get the current cloud cost summary
  CloudCostSummary get cloudCostSummary => CloudCostTracker.shared.summary;

  /// Reset all tracked cloud costs
  void resetCloudCosts() => CloudCostTracker.shared.reset();

  // MARK: - Generation

  /// Generate text with routing awareness.
  ///
  /// Routes between on-device and cloud based on the provided policy.
  Future<RoutedGenerationResult> generate({
    required String prompt,
    LLMGenerationOptions? options,
    RoutingPolicy? routingPolicy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    final policy = routingPolicy ?? _defaultPolicy;
    final startTime = DateTime.now();

    final RoutedGenerationResult result;

    switch (policy.mode) {
      case RoutingMode.alwaysCloud:
        result = await _generateCloud(
          prompt: prompt,
          options: options,
          policy: policy,
          cloudProviderId: cloudProviderId,
          cloudModel: cloudModel,
        );

      case RoutingMode.alwaysLocal:
        result = await _generateLocal(
          prompt: prompt,
          options: options,
          policy: policy,
        );

      case RoutingMode.hybridAuto:
        result = await _generateHybridAuto(
          prompt: prompt,
          options: options,
          policy: policy,
          cloudProviderId: cloudProviderId,
          cloudModel: cloudModel,
        );

      case RoutingMode.hybridManual:
        result = await _generateLocal(
          prompt: prompt,
          options: options,
          policy: policy,
        );
    }

    // Emit routing telemetry
    final latencyMs =
        DateTime.now().difference(startTime).inMicroseconds / 1000.0;
    _emitRoutingTelemetry(decision: result.routingDecision, latencyMs: latencyMs);

    return result;
  }

  /// Generate text with streaming and routing awareness.
  Future<RoutedStreamingResult> generateStream({
    required String prompt,
    LLMGenerationOptions? options,
    RoutingPolicy? routingPolicy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    final policy = routingPolicy ?? _defaultPolicy;

    switch (policy.mode) {
      case RoutingMode.alwaysCloud:
        return _generateStreamCloud(
          prompt: prompt,
          options: options,
          policy: policy,
          cloudProviderId: cloudProviderId,
          cloudModel: cloudModel,
        );

      case RoutingMode.alwaysLocal:
        final streamResult =
            await RunAnywhere.generateStream(prompt, options: options);
        final decision = RoutingDecision(
          executionTarget: ExecutionTarget.onDevice,
          policy: policy,
        );
        return RoutedStreamingResult(
          streamingResult: streamResult,
          routingDecision: decision,
        );

      case RoutingMode.hybridAuto:
        return _generateStreamHybridAuto(
          prompt: prompt,
          options: options,
          policy: policy,
          cloudProviderId: cloudProviderId,
          cloudModel: cloudModel,
        );

      case RoutingMode.hybridManual:
        final streamResult =
            await RunAnywhere.generateStream(prompt, options: options);
        final decision = RoutingDecision(
          executionTarget: ExecutionTarget.onDevice,
          policy: policy,
        );
        return RoutedStreamingResult(
          streamingResult: streamResult,
          routingDecision: decision,
        );
    }
  }

  // MARK: - Private: Local Generation

  Future<RoutedGenerationResult> _generateLocal({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
  }) async {
    // Build options with confidence threshold
    final effectiveOptions =
        _optionsWithConfidence(options, policy.confidenceThreshold);

    final result =
        await RunAnywhere.generate(prompt, options: effectiveOptions);

    final decision = RoutingDecision(
      executionTarget: ExecutionTarget.onDevice,
      policy: policy,
      onDeviceConfidence: result.confidence ?? 1.0,
      cloudHandoffTriggered: result.cloudHandoff ?? false,
      handoffReason: result.handoffReason != null
          ? HandoffReason.fromCode(result.handoffReason!)
          : HandoffReason.none,
    );

    return RoutedGenerationResult(
      generationResult: result,
      routingDecision: decision,
    );
  }

  // MARK: - Private: Cloud Generation

  Future<RoutedGenerationResult> _generateCloud({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    final cloudOpts = CloudGenerationOptions(
      model: cloudModel ?? 'gpt-4o-mini',
      maxTokens: options?.maxTokens ?? 1024,
      temperature: options?.temperature ?? 0.7,
      systemPrompt: options?.systemPrompt,
    );

    // Enforce cost cap before making the request
    if (policy.costCapUSD > 0) {
      final summary = CloudCostTracker.shared.summary;
      if (summary.totalCostUSD >= policy.costCapUSD) {
        throw CloudProviderException.budgetExceeded(
          currentUSD: summary.totalCostUSD,
          capUSD: policy.costCapUSD,
        );
      }
    }

    final CloudGenerationResult cloudResult;

    // Try failover chain first if available, else direct provider
    if (_failoverChain != null) {
      cloudResult = await _failoverChain!.generate(prompt, cloudOpts);
    } else {
      final CloudProvider provider;
      if (cloudProviderId != null) {
        provider = CloudProviderManager.shared.get(cloudProviderId);
      } else {
        provider = CloudProviderManager.shared.getDefault();
      }
      cloudResult = await provider.generate(prompt, cloudOpts);
    }

    // Track cost
    final cost = cloudResult.estimatedCostUSD;
    if (cost != null) {
      CloudCostTracker.shared.recordRequest(
        providerId: cloudResult.providerId,
        inputTokens: cloudResult.inputTokens,
        outputTokens: cloudResult.outputTokens,
        costUSD: cost,
      );

      // Emit cost event
      final cumulative = CloudCostTracker.shared.summary.totalCostUSD;
      EventBus.shared.publish(CloudCostTelemetryEvent(
        providerId: cloudResult.providerId,
        inputTokens: cloudResult.inputTokens,
        outputTokens: cloudResult.outputTokens,
        costUSD: cost,
        cumulativeTotalUSD: cumulative,
      ));
    }

    final decision = RoutingDecision(
      executionTarget: ExecutionTarget.cloud,
      policy: policy,
      cloudProviderId: cloudResult.providerId,
      cloudModel: cloudOpts.model,
    );

    final llmResult = LLMGenerationResult(
      text: cloudResult.text,
      inputTokens: cloudResult.inputTokens,
      tokensUsed: cloudResult.outputTokens,
      modelUsed: cloudOpts.model,
      latencyMs: cloudResult.latencyMs,
      framework: 'cloud',
      tokensPerSecond: cloudResult.latencyMs > 0
          ? cloudResult.outputTokens / (cloudResult.latencyMs / 1000.0)
          : 0,
    );

    return RoutedGenerationResult(
      generationResult: llmResult,
      routingDecision: decision,
    );
  }

  // MARK: - Private: Hybrid Auto Generation

  Future<RoutedGenerationResult> _generateHybridAuto({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    // Latency-based routing: race local generation against timeout
    if (policy.maxLocalLatencyMs > 0) {
      final localResult = await _generateLocalWithTimeout(
        prompt: prompt,
        options: options,
        policy: policy,
        timeoutMs: policy.maxLocalLatencyMs,
      );

      if (localResult != null) {
        // Local completed within timeout
        if (!localResult.routingDecision.cloudHandoffTriggered) {
          return localResult;
        }
        // Local completed but recommends handoff - fall through to cloud
      } else {
        // Timeout exceeded - emit event and fall back to cloud
        EventBus.shared.publish(LatencyTimeoutTelemetryEvent(
          maxLatencyMs: policy.maxLocalLatencyMs,
          actualLatencyMs: policy.maxLocalLatencyMs.toDouble(),
        ));
      }
    } else {
      // No timeout: try on-device first with confidence tracking
      final localResult = await _generateLocal(
        prompt: prompt,
        options: options,
        policy: policy,
      );

      // If on-device was confident enough, return it
      if (!localResult.routingDecision.cloudHandoffTriggered) {
        return localResult;
      }

      _logger.info(
        'Cloud handoff triggered (confidence: '
        '${localResult.routingDecision.onDeviceConfidence.toStringAsFixed(2)}, '
        'reason: ${localResult.routingDecision.handoffReason})',
      );
    }

    // Fall back to cloud
    final cloudResult = await _generateCloud(
      prompt: prompt,
      options: options,
      policy: policy,
      cloudProviderId: cloudProviderId,
      cloudModel: cloudModel,
    );

    // Mark as hybrid fallback
    final decision = RoutingDecision(
      executionTarget: ExecutionTarget.hybridFallback,
      policy: policy,
      onDeviceConfidence: 0.0,
      cloudHandoffTriggered: true,
      handoffReason: policy.maxLocalLatencyMs > 0
          ? HandoffReason.firstTokenLowConfidence
          : HandoffReason.rollingWindowDegradation,
      cloudProviderId: cloudResult.routingDecision.cloudProviderId,
      cloudModel: cloudResult.routingDecision.cloudModel,
    );

    return RoutedGenerationResult(
      generationResult: cloudResult.generationResult,
      routingDecision: decision,
    );
  }

  // MARK: - Private: Local Generation with Timeout

  /// Run local generation with a timeout. Returns null if timeout is exceeded.
  Future<RoutedGenerationResult?> _generateLocalWithTimeout({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
    required int timeoutMs,
  }) async {
    final effectiveOptions =
        _optionsWithConfidence(options, policy.confidenceThreshold);

    final completer = Completer<RoutedGenerationResult?>();

    // Task 1: Local generation
    unawaited((() async {
      try {
        final result =
            await RunAnywhere.generate(prompt, options: effectiveOptions);
        final decision = RoutingDecision(
          executionTarget: ExecutionTarget.onDevice,
          policy: policy,
          onDeviceConfidence: result.confidence ?? 1.0,
          cloudHandoffTriggered: result.cloudHandoff ?? false,
          handoffReason: result.handoffReason != null
              ? HandoffReason.fromCode(result.handoffReason!)
              : HandoffReason.none,
        );
        if (!completer.isCompleted) {
          completer.complete(RoutedGenerationResult(
            generationResult: result,
            routingDecision: decision,
          ));
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    })());

    // Task 2: Timeout
    unawaited(Future<void>.delayed(Duration(milliseconds: timeoutMs)).then((_) {
      if (!completer.isCompleted) {
        completer.complete(null); // Timeout reached
      }
    }));

    return completer.future;
  }

  // MARK: - Private: Cloud Streaming

  Future<RoutedStreamingResult> _generateStreamCloud({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    // Enforce cost cap
    if (policy.costCapUSD > 0) {
      final summary = CloudCostTracker.shared.summary;
      if (summary.totalCostUSD >= policy.costCapUSD) {
        throw CloudProviderException.budgetExceeded(
          currentUSD: summary.totalCostUSD,
          capUSD: policy.costCapUSD,
        );
      }
    }

    final cloudOpts = CloudGenerationOptions(
      model: cloudModel ?? 'gpt-4o-mini',
      maxTokens: options?.maxTokens ?? 1024,
      temperature: options?.temperature ?? 0.7,
      systemPrompt: options?.systemPrompt,
    );

    final Stream<String> cloudStream;

    // Try failover chain first
    if (_failoverChain != null) {
      cloudStream = _failoverChain!.generateStream(prompt, cloudOpts);
    } else {
      final CloudProvider provider;
      if (cloudProviderId != null) {
        provider = CloudProviderManager.shared.get(cloudProviderId);
      } else {
        provider = CloudProviderManager.shared.getDefault();
      }
      cloudStream = provider.generateStream(prompt, cloudOpts);
    }

    final modelId = cloudOpts.model;
    final provId = cloudProviderId ?? 'default';

    // Wrap cloud stream into LLMStreamingResult
    final controller = StreamController<String>.broadcast();
    final allTokens = <String>[];

    final subscription = cloudStream.listen(
      (token) {
        allTokens.add(token);
        if (!controller.isClosed) {
          controller.add(token);
        }
      },
      onError: (Object error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    final resultFuture = controller.stream.toList().then((_) {
      return LLMGenerationResult(
        text: allTokens.join(),
        inputTokens: 0,
        tokensUsed: max(1, allTokens.join().length ~/ 4),
        modelUsed: modelId,
        latencyMs: 0,
        framework: 'cloud',
        tokensPerSecond: 0,
      );
    });

    final streamResult = LLMStreamingResult(
      stream: controller.stream,
      result: resultFuture,
      cancel: () {
        subscription.cancel();
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    final decision = RoutingDecision(
      executionTarget: ExecutionTarget.cloud,
      policy: policy,
      cloudProviderId: provId,
      cloudModel: modelId,
    );

    return RoutedStreamingResult(
      streamingResult: streamResult,
      routingDecision: decision,
    );
  }

  // MARK: - Private: Hybrid Auto Streaming

  Future<RoutedStreamingResult> _generateStreamHybridAuto({
    required String prompt,
    LLMGenerationOptions? options,
    required RoutingPolicy policy,
    String? cloudProviderId,
    String? cloudModel,
  }) async {
    // For streaming hybrid, start with on-device and monitor confidence.
    // If handoff is needed, the C++ layer will stop generation and signal.
    final streamResult =
        await RunAnywhere.generateStream(prompt, options: options);
    final decision = RoutingDecision(
      executionTarget: ExecutionTarget.onDevice,
      policy: policy,
    );
    return RoutedStreamingResult(
      streamingResult: streamResult,
      routingDecision: decision,
    );
  }

  // MARK: - Telemetry

  void _emitRoutingTelemetry({
    required RoutingDecision decision,
    required double latencyMs,
    double? estimatedCostUSD,
  }) {
    EventBus.shared.publish(RoutingTelemetryEvent(
      routingMode: decision.policy.mode,
      executionTarget: decision.executionTarget,
      confidence: decision.onDeviceConfidence,
      cloudHandoffTriggered: decision.cloudHandoffTriggered,
      handoffReason: decision.handoffReason,
      cloudProviderId: decision.cloudProviderId,
      cloudModel: decision.cloudModel,
      latencyMs: latencyMs,
      estimatedCostUSD: estimatedCostUSD,
    ));
  }

  // MARK: - Helpers

  LLMGenerationOptions _optionsWithConfidence(
    LLMGenerationOptions? options,
    double threshold,
  ) {
    final opts = options ?? const LLMGenerationOptions();
    // Return options with confidence threshold set.
    // The threshold is passed to C++ via rac_llm_options_t.confidence_threshold.
    return LLMGenerationOptions(
      maxTokens: opts.maxTokens,
      temperature: opts.temperature,
      topP: opts.topP,
      stopSequences: opts.stopSequences,
      streamingEnabled: opts.streamingEnabled,
      preferredFramework: opts.preferredFramework,
      systemPrompt: opts.systemPrompt,
      confidenceThreshold: threshold,
    );
  }
}

// MARK: - Routed Results

/// Generation result enriched with routing metadata.
///
/// Matches Swift RoutedGenerationResult struct.
class RoutedGenerationResult {
  /// The generation result
  final LLMGenerationResult generationResult;

  /// How the request was routed
  final RoutingDecision routingDecision;

  const RoutedGenerationResult({
    required this.generationResult,
    required this.routingDecision,
  });

  @override
  String toString() =>
      'RoutedGenerationResult(target: ${routingDecision.executionTarget.value}, '
      'text: "${generationResult.text.substring(0, generationResult.text.length.clamp(0, 50))}...")';
}

/// Streaming result enriched with routing metadata.
///
/// Matches Swift RoutedStreamingResult struct.
class RoutedStreamingResult {
  /// The streaming result
  final LLMStreamingResult streamingResult;

  /// How the request was routed
  final RoutingDecision routingDecision;

  const RoutedStreamingResult({
    required this.streamingResult,
    required this.routingDecision,
  });
}
