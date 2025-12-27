/// Input for speaker diarization processing
/// Matches iOS SpeakerDiarizationInput from Features/SpeakerDiarization/Models/SpeakerDiarizationInput.swift
class SpeakerDiarizationInput {
  /// Audio samples to process
  final List<double> samples;

  /// Sample rate of the audio
  final int sampleRate;

  /// Optional timestamp for this segment
  final double? timestamp;

  const SpeakerDiarizationInput({
    required this.samples,
    this.sampleRate = 16000,
    this.timestamp,
  });

  /// Validate the input
  void validate() {
    if (samples.isEmpty) {
      throw ArgumentError('Audio samples cannot be empty');
    }
    if (sampleRate <= 0) {
      throw ArgumentError('Sample rate must be positive');
    }
  }
}
