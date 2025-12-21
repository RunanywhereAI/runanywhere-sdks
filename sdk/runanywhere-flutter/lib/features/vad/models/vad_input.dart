import 'dart:typed_data';

/// Input for Voice Activity Detection processing
/// Matches iOS VADInput from Features/VAD/Models/VADInput.swift
class VADInput {
  /// Audio buffer to process (mutually exclusive with audioSamples)
  final Uint8List? buffer;

  /// Audio samples as float array (mutually exclusive with buffer)
  final List<double>? audioSamples;

  /// Optional override for energy threshold
  final double? energyThresholdOverride;

  /// Initialize with audio buffer
  VADInput.fromBuffer(Uint8List buffer)
      : buffer = buffer,
        audioSamples = null,
        energyThresholdOverride = null;

  /// Initialize with audio samples
  VADInput.fromSamples(List<double> samples, {double? energyThresholdOverride})
      : buffer = null,
        audioSamples = samples,
        energyThresholdOverride = energyThresholdOverride;

  /// Private constructor
  VADInput._({
    this.buffer,
    this.audioSamples,
    this.energyThresholdOverride,
  });

  /// Validate the input
  void validate() {
    // Must have either buffer or audioSamples
    if (buffer == null && audioSamples == null) {
      throw VADInputError.invalidInput(
        'VADInput must contain either buffer or audioSamples',
      );
    }

    // Both cannot be provided
    if (buffer != null && audioSamples != null) {
      throw VADInputError.invalidInput(
        'VADInput cannot contain both buffer and audioSamples',
      );
    }

    // Validate threshold override if provided
    if (energyThresholdOverride != null) {
      if (energyThresholdOverride! < 0 || energyThresholdOverride! > 1.0) {
        throw VADInputError.invalidInput(
          'Energy threshold override must be between 0 and 1.0',
        );
      }
    }

    // Validate audio samples are not empty
    if (audioSamples != null && audioSamples!.isEmpty) {
      throw VADInputError.emptyAudioBuffer();
    }

    // Validate buffer is not empty
    if (buffer != null && buffer!.isEmpty) {
      throw VADInputError.emptyAudioBuffer();
    }
  }
}

/// VAD input validation errors
class VADInputError implements Exception {
  final String message;

  VADInputError(this.message);

  factory VADInputError.invalidInput(String reason) {
    return VADInputError('Invalid input: $reason');
  }

  factory VADInputError.emptyAudioBuffer() {
    return VADInputError('Audio buffer is empty');
  }

  @override
  String toString() => 'VADInputError: $message';
}
