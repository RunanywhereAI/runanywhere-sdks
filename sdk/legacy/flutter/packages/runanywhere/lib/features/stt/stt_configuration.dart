import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';

/// Configuration for the STT component.
///
/// Mirrors the validation contract used by the Swift and Kotlin SDKs so
/// invalid parameters fail in Dart before crossing the FFI boundary.
class STTConfiguration implements ComponentConfiguration {
  final String? modelId;
  final InferenceFramework? preferredFramework;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;
  final bool enableDiarization;
  final List<String> vocabularyList;
  final int maxAlternatives;
  final bool enableTimestamps;

  const STTConfiguration({
    this.modelId,
    this.preferredFramework,
    this.language = 'en-US',
    this.sampleRate = 16000,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.vocabularyList = const <String>[],
    this.maxAlternatives = 1,
    this.enableTimestamps = true,
  });

  @override
  void validate() {
    if (sampleRate <= 0 || sampleRate > 48000) {
      throw SDKError.validationFailed(
        'Sample rate must be between 1 and 48000 Hz',
      );
    }

    if (maxAlternatives <= 0 || maxAlternatives > 10) {
      throw SDKError.validationFailed(
        'Max alternatives must be between 1 and 10',
      );
    }
  }
}
