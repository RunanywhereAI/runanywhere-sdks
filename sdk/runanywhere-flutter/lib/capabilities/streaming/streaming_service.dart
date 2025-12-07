import 'dart:async';
import '../model_loading/model_loading_service.dart';
import '../text_generation/generation_service.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../foundation/error_types/sdk_error.dart';
import '../../../public/runanywhere.dart' show unawaited, RunAnywhereGenerationOptions;
import '../../../core/module_registry.dart' show LLMGenerationOptions;

/// Service for streaming text generation
class StreamingService {
  final GenerationService generationService;
  final ModelLoadingService modelLoadingService;
  final SDKLogger logger = SDKLogger(category: 'StreamingService');

  StreamingService({
    required this.generationService,
    required this.modelLoadingService,
  });

  /// Generate streaming text
  Stream<String> generateStream({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  }) {
    logger.info('🚀 Starting streaming generation');

    final controller = StreamController<String>();

    // Start generation in background
    Future<void> generateInBackground() async {
      try {
        final loadedModel = generationService.getCurrentModel();
        if (loadedModel == null) {
          controller.addError(SDKError.modelNotFound('No model is currently loaded'));
          await controller.close();
          return;
        }

        logger.info('✅ Using loaded model: ${loadedModel.model.name}');

        // Get streaming from service
        final stream = loadedModel.service.generateStream(
          prompt: prompt,
          options: LLMGenerationOptions(
            maxTokens: options.maxTokens,
            temperature: options.temperature,
          ),
        );

        // Forward tokens to controller
        await for (final token in stream) {
          controller.add(token);
        }

        await controller.close();
      } catch (e) {
        logger.error('❌ Streaming generation failed: $e');
        controller.addError(e);
        await controller.close();
      }
    }

    unawaited(generateInBackground());

    return controller.stream;
  }
}
