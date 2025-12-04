import '../../core/module_registry.dart' show ModuleRegistry, STTService;
import '../../foundation/logging/sdk_logger.dart';

/// Voice capability service
class VoiceCapabilityService {
  final SDKLogger logger = SDKLogger(category: 'VoiceCapabilityService');

  /// Find voice service for a specific model
  Future<STTService?> findVoiceService({required String modelId}) async {
    final provider = ModuleRegistry.shared.sttProvider(modelId: modelId);
    if (provider == null) {
      logger.warning('No STT provider available for model: $modelId');
      return null;
    }

    try {
      // Create STT configuration
      final config = STTConfiguration(
        modelId: modelId,
        language: 'en',
        sampleRate: 16000,
      );

      // Create service via provider
      final service = await provider.createSTTService(config);
      return service;
    } catch (e) {
      logger.error('Failed to create STT service: $e');
      return null;
    }
  }
}

// Placeholder STT configuration
class STTConfiguration {
  final String? modelId;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;

  STTConfiguration({
    this.modelId,
    this.language = 'en',
    this.sampleRate = 16000,
    this.enablePunctuation = true,
  });
}
