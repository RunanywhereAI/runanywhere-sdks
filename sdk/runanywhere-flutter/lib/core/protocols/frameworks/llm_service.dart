import '../../../public/models/generation_options.dart';

/// LLM Service Protocol
/// Similar to Swift SDK's LLMService
abstract class LLMService {
  /// Initialize the service with a model path
  Future<void> initialize({required String modelPath});

  /// Generate text synchronously
  Future<String> generate({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  });

  /// Stream generation
  Stream<String> streamGenerate({
    required String prompt,
    required RunAnywhereGenerationOptions options,
  });

  /// Get model memory usage
  Future<int> getModelMemoryUsage();

  /// Set context
  Future<void> setContext(String context);

  /// Clear context
  Future<void> clearContext();
}

