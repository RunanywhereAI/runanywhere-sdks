import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';

/// Dart-layer validation config for the LLM bridge. Not a data-transfer
/// object — proto's [LLMConfiguration] from llm_options.pb.dart is the
/// canonical type. This exists only to run pre-FFI validation.
class LLMComponentConfig implements ComponentConfiguration {
  final String? modelId;
  final InferenceFramework? preferredFramework;
  final int contextLength;
  final double temperature;
  final int maxTokens;
  final String? systemPrompt;
  final bool streamingEnabled;

  const LLMComponentConfig({
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
    if (contextLength <= 0) {
      throw SDKException.validationFailed(
        'Context length must be greater than 0',
      );
    }

    if (!temperature.isFinite || temperature < 0 || temperature > 2.0) {
      throw SDKException.validationFailed(
        'Temperature must be between 0 and 2.0',
      );
    }

    if (maxTokens <= 0 || maxTokens > contextLength) {
      throw SDKException.validationFailed(
        'Max tokens must be between 1 and context length',
      );
    }

    // Guard against clearly oversized prompts (chars) — a system prompt larger
    // than the model's context window (in chars) is clearly invalid.
    // Uses ~4 chars per token as a generous char-level bound.
    final prompt = systemPrompt;
    if (prompt != null && prompt.length > contextLength * 4) {
      throw SDKException.validationFailed(
        "systemPrompt length (${prompt.length} chars) exceeds the model's context window",
      );
    }
  }
}
