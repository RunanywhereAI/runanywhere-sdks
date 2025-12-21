import 'dart:async';

import 'package:runanywhere/capabilities/analytics/analytics_service.dart';
import 'package:runanywhere/capabilities/model_loading/model_loading_service.dart';
import 'package:runanywhere/capabilities/model_loading/models/loaded_model.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/runanywhere.dart';

/// Main service for text generation
/// Matches iOS GenerationService (routing handled internally, not as external service)
class GenerationService {
  final ModelLoadingService modelLoadingService;
  final SDKLogger logger = SDKLogger(category: 'GenerationService');

  // Current loaded model
  LoadedModel? _currentLoadedModel;

  GenerationService({
    required this.modelLoadingService,
  });

  /// Set the current loaded model for generation
  void setCurrentModel(LoadedModel? model) {
    _currentLoadedModel = model;
  }

  /// Get the current loaded model
  LoadedModel? getCurrentModel() {
    return _currentLoadedModel;
  }

  /// Get the LLM service from the current loaded model
  /// Matches iOS pattern for accessing llmCapability.supportsStreaming
  LLMService? get llmService {
    return _currentLoadedModel?.service;
  }

  // Cancel flag for ongoing generation
  bool _isCancelled = false;

  /// Whether generation was cancelled
  bool get isCancelled => _isCancelled;

  /// Cancel the current text generation
  /// Matches iOS RunAnywhere.cancelGeneration()
  void cancel() {
    _isCancelled = true;
    logger.info('⏹️ Generation cancelled');
  }

  /// Generate text using the loaded model
  Future<GenerationResult> generate({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  }) async {
    logger.info('🚀 Starting text generation');

    // Use the current loaded model
    if (_currentLoadedModel == null) {
      logger.error('❌ No model is currently loaded');
      throw SDKError.modelNotFound('No model is currently loaded');
    }

    final loadedModel = _currentLoadedModel!;
    logger.info('✅ Using loaded model: ${loadedModel.model.name}');

    final startTime = DateTime.now();

    try {
      // Generate text using the actual loaded model's service
      final generatedText = await loadedModel.service.generate(
        prompt: prompt,
        options: LLMGenerationOptions(
          maxTokens: options.maxTokens,
          temperature: options.temperature,
        ),
      );

      logger.info(
          '✅ Got response from service: ${generatedText.text.substring(0, generatedText.text.length > 100 ? 100 : generatedText.text.length)}...');

      // Calculate metrics
      final latency = DateTime.now().difference(startTime).inMilliseconds;

      // Estimate token count (simple approximation: ~4 chars per token)
      final estimatedTokens = (generatedText.text.length / 4).round();
      final tokensPerSecond = estimatedTokens / (latency / 1000.0);

      final result = GenerationResult(
        text: generatedText.text,
        tokensUsed: estimatedTokens,
        latencyMs: latency,
        savedAmount: 0, // TODO: Calculate based on routing decision
        performanceMetrics: PerformanceMetrics(
          timeToFirstTokenMs: latency,
          tokensPerSecond: tokensPerSecond,
          inferenceTimeMs: latency,
          peakMemoryUsage: 0,
        ),
      );

      // Submit analytics (non-blocking)
      unawaited(
          ServiceContainer.shared.analyticsService.submitGenerationAnalytics(
        generationId: DateTime.now().millisecondsSinceEpoch.toString(),
        modelId: loadedModel.model.id,
        performanceMetrics: result.performanceMetrics,
        inputTokens: (prompt.length / 4).round(),
        outputTokens: estimatedTokens,
        success: true,
        executionTarget: 'on_device',
      ));

      return result;
    } catch (e) {
      logger.error('❌ Generation failed with error: $e');

      // Enhanced error handling
      if (e.toString().toLowerCase().contains('timeout') ||
          e.toString().toLowerCase().contains('timed out')) {
        throw SDKError.timeout(
          'Text generation timed out. The model may be too large for this device or the prompt too complex. Try using a smaller model or simpler prompt.',
        );
      }

      // Re-throw the original error with additional context
      throw SDKError.generationFailed('On-device generation failed: $e');
    }
  }
}

/// Generation result
/// Matches iOS LLMGenerationResult from Features/LLM/Models/LLMGenerationResult.swift
class GenerationResult {
  /// Generated text (with thinking content removed if extracted)
  final String text;

  /// Thinking/reasoning content extracted from the response
  /// Only populated if the model supports thinking mode and returned thinking tokens
  final String? thinkingContent;

  /// Number of tokens used (output tokens)
  final int tokensUsed;

  /// Total latency in milliseconds
  final int latencyMs;

  /// Cost savings from on-device vs cloud execution
  final double savedAmount;

  /// Detailed performance metrics
  final PerformanceMetrics performanceMetrics;

  /// Structured output validation result (if structured output was requested)
  final StructuredOutputValidation? structuredOutputValidation;

  /// Number of tokens used for thinking/reasoning (if model supports thinking mode)
  final int? thinkingTokens;

  /// Number of tokens in the actual response content (excluding thinking)
  final int? responseTokens;

  GenerationResult({
    required this.text,
    this.thinkingContent,
    required this.tokensUsed,
    required this.latencyMs,
    this.savedAmount = 0,
    required this.performanceMetrics,
    this.structuredOutputValidation,
    this.thinkingTokens,
    this.responseTokens,
  });
}

/// Structured output validation result
/// Matches iOS StructuredOutputValidation from StructuredOutputHandler.swift
class StructuredOutputValidation {
  /// Whether the structured output is valid
  final bool isValid;

  /// Whether the output contains JSON
  final bool containsJSON;

  /// Error message if validation failed
  final String? error;

  StructuredOutputValidation({
    required this.isValid,
    required this.containsJSON,
    this.error,
  });
}

/// Generation options
class RunAnywhereGenerationOptions {
  final int maxTokens;
  final double temperature;
  final bool stream;

  RunAnywhereGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.7,
    this.stream = true,
  });
}
