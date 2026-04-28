import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';

/// Dart-layer validation config for the STT bridge. Not a data-transfer
/// object — proto's [STTConfiguration] from stt_options.pb.dart is the
/// canonical type. This exists only to run pre-FFI validation.
class STTComponentConfig implements ComponentConfiguration {
  final String? modelId;
  final InferenceFramework? preferredFramework;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;
  final bool enableDiarization;
  final List<String> vocabularyList;
  final int maxAlternatives;
  final bool enableTimestamps;

  const STTComponentConfig({
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
      throw SDKException.validationFailed(
        'Sample rate must be between 1 and 48000 Hz',
      );
    }

    if (maxAlternatives <= 0 || maxAlternatives > 10) {
      throw SDKException.validationFailed(
        'Max alternatives must be between 1 and 10',
      );
    }
  }
}
