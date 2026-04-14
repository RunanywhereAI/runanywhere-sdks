import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';

/// Configuration for TTS synthesis.
class TTSConfiguration implements ComponentConfiguration {
  final String voice;
  final String language;
  final double speakingRate;
  final double pitch;
  final double volume;
  final String audioFormat;

  const TTSConfiguration({
    this.voice = 'system',
    this.language = 'en-US',
    this.speakingRate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = 'pcm',
  });

  @override
  void validate() {
    if (!speakingRate.isFinite || speakingRate < 0.5 || speakingRate > 2.0) {
      throw SDKError.validationFailed(
        'Speaking rate must be between 0.5 and 2.0',
      );
    }

    if (!pitch.isFinite || pitch < 0.5 || pitch > 2.0) {
      throw SDKError.validationFailed(
        'Pitch must be between 0.5 and 2.0',
      );
    }

    if (!volume.isFinite || volume < 0.0 || volume > 1.0) {
      throw SDKError.validationFailed(
        'Volume must be between 0.0 and 1.0',
      );
    }
  }
}
