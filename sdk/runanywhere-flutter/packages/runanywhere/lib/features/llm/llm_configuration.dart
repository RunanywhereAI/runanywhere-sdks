import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';

/// Configuration for the LLM component.
///
/// Mirrors the validation contract used by the Swift and Kotlin SDKs so
/// invalid parameters fail in Dart before crossing the FFI boundary.
class LLMConfiguration implements ComponentConfiguration {
  final String? modelId;
  final InferenceFramework? preferredFramework;
  final int contextLength;
  final double temperature;
  final int maxTokens;
  final String? systemPrompt;
  final bool streamingEnabled;

  const LLMConfiguration({
    this.modelId,
    this.preferredFramework,
    this.contextLength = 2048,
    this.temperature = 0.7,
    this.maxTokens = 100,
    this.systemPrompt,
    this.streamingEnabled = true,
  });

  @override
  void validate() {
    if (contextLength <= 0 || contextLength > 32768) {
      throw SDKError.validationFailed(
        'Context length must be between 1 and 32768',
      );
    }

    if (!temperature.isFinite || temperature < 0 || temperature > 2.0) {
      throw SDKError.validationFailed(
        'Temperature must be between 0 and 2.0',
      );
    }

    if (maxTokens <= 0 || maxTokens > contextLength) {
      throw SDKError.validationFailed(
        'Max tokens must be between 1 and context length',
      );
    }
  }
}
