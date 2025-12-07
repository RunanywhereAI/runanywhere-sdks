import '../../core/protocols/component/component_configuration.dart';

/// Input for Voice Activity Detection
class VADInput implements ComponentInput {
  /// Audio buffer to process (16-bit PCM samples)
  final List<int>? buffer;

  /// Audio samples (Float32 format, alternative to buffer)
  final List<double>? audioSamples;

  /// Optional override for energy threshold
  final double? energyThresholdOverride;

  const VADInput.fromBuffer(
    this.buffer, {
    this.energyThresholdOverride,
  }) : audioSamples = null;

  const VADInput.fromSamples(
    this.audioSamples, {
    this.energyThresholdOverride,
  }) : buffer = null;

  @override
  void validate() {
    if (buffer == null && audioSamples == null) {
      throw ArgumentError(
        'VADInput must contain either buffer or audioSamples',
      );
    }
    if (energyThresholdOverride != null) {
      if (energyThresholdOverride! < 0 || energyThresholdOverride! > 1.0) {
        throw ArgumentError(
          'Energy threshold override must be between 0 and 1.0',
        );
      }
    }
  }
}

/// Output from Voice Activity Detection
class VADOutput implements ComponentOutput {
  /// Whether speech is detected
  final bool isSpeechDetected;

  /// Audio energy level
  final double energyLevel;

  /// Timestamp of this detection
  @override
  final DateTime timestamp;

  VADOutput({
    required this.isSpeechDetected,
    required this.energyLevel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
