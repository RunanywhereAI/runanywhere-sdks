import 'dart:async';

import 'package:runanywhere/capabilities/model_loading/model_loading_service.dart';
import 'package:runanywhere/capabilities/text_generation/generation_service.dart'
    show GenerationService, RunAnywhereGenerationOptions;
import 'package:runanywhere/core/module_registry.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/features/llm/models/llm_streaming_result.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/analytics/services/generation_analytics_service.dart';

/// Service for streaming text generation
/// Matches iOS streaming pattern with TTFT tracking via StreamingMetricsCollector
class StreamingService {
  final GenerationService generationService;
  final ModelLoadingService modelLoadingService;
  final SDKLogger logger = SDKLogger(category: 'StreamingService');

  /// Analytics service for TTFT and metrics tracking
  GenerationAnalyticsService? _analyticsService;

  StreamingService({
    required this.generationService,
    required this.modelLoadingService,
    GenerationAnalyticsService? analyticsService,
  }) : _analyticsService = analyticsService;

  /// Set analytics service (for dependency injection)
  void setAnalyticsService(GenerationAnalyticsService service) {
    _analyticsService = service;
  }

  /// Generate streaming text
  /// Returns a simple Stream<String> for backward compatibility
  Stream<String> generateStream({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  }) {
    logger.info('🚀 Starting streaming generation');

    final controller = StreamController<String>.broadcast();

    // Start generation in background with metrics tracking
    Future<void> generateInBackground() async {
      final loadedModel = generationService.getCurrentModel();
      if (loadedModel == null) {
        controller
            .addError(SDKError.modelNotFound('No model is currently loaded'));
        await controller.close();
        return;
      }

      final modelId = loadedModel.model.id;
      logger.info('✅ Using loaded model: ${loadedModel.model.name}');

      // Create metrics collector for TTFT tracking (matches iOS pattern)
      final analyticsService =
          _analyticsService ?? GenerationAnalyticsService();
      final generationId = analyticsService.startStreamingGeneration(
        modelId: modelId,
        framework: loadedModel.model.preferredFramework?.rawValue,
      );

      final collector = StreamingMetricsCollector(
        modelId: modelId,
        generationId: generationId,
        analyticsService: analyticsService,
        framework: loadedModel.model.preferredFramework?.rawValue,
        promptLength: prompt.length,
      );

      try {
        collector.markStart();

        // Get streaming from service
        final stream = loadedModel.service.generateStream(
          prompt: prompt,
          options: LLMGenerationOptions(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
          ),
        );

        // Forward tokens to controller with TTFT tracking
        await for (final token in stream) {
          collector.recordToken(token);
          controller.add(token);
        }

        collector.markComplete();
        await controller.close();
      } catch (e) {
        logger.error('❌ Streaming generation failed: $e');
        collector.markFailed(e);
        controller.addError(e);
        await controller.close();
      }
    }

    unawaited(generateInBackground());

    return controller.stream;
  }

  /// Generate streaming text with metrics result
  /// Returns LLMStreamingResult with both stream AND final result (iOS parity)
  /// Matches iOS `generateStream()` returning `LLMStreamingResult`
  LLMStreamingResult generateStreamWithMetrics({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  }) {
    logger.info('🚀 Starting streaming generation with metrics');

    final controller = StreamController<String>.broadcast();
    final resultCompleter = Completer<LLMGenerationResult>();

    // Start generation in background with metrics tracking
    Future<void> generateInBackground() async {
      final loadedModel = generationService.getCurrentModel();
      if (loadedModel == null) {
        final error = SDKError.modelNotFound('No model is currently loaded');
        controller.addError(error);
        resultCompleter.completeError(error);
        await controller.close();
        return;
      }

      final modelId = loadedModel.model.id;
      logger.info('✅ Using loaded model: ${loadedModel.model.name}');

      // Create metrics collector for TTFT tracking (matches iOS pattern)
      final analyticsService =
          _analyticsService ?? GenerationAnalyticsService();
      final generationId = analyticsService.startStreamingGeneration(
        modelId: modelId,
        framework: loadedModel.model.preferredFramework?.rawValue,
      );

      final collector = StreamingMetricsCollector(
        modelId: modelId,
        generationId: generationId,
        analyticsService: analyticsService,
        framework: loadedModel.model.preferredFramework?.rawValue,
        promptLength: prompt.length,
      );

      try {
        collector.markStart();

        // Get streaming from service
        final stream = loadedModel.service.generateStream(
          prompt: prompt,
          options: LLMGenerationOptions(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
          ),
        );

        // Forward tokens to controller with TTFT tracking
        await for (final token in stream) {
          collector.recordToken(token);
          controller.add(token);
        }

        collector.markComplete();
        await controller.close();

        // Complete with final result containing metrics
        final result = await collector.waitForResult();
        resultCompleter.complete(result);
      } catch (e) {
        logger.error('❌ Streaming generation failed: $e');
        collector.markFailed(e);
        controller.addError(e);
        resultCompleter.completeError(e);
        await controller.close();
      }
    }

    unawaited(generateInBackground());

    return LLMStreamingResult(
      stream: controller.stream,
      result: resultCompleter.future,
    );
  }
}
