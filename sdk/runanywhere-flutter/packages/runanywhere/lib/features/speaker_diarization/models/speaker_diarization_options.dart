/// Options for speaker diarization processing
/// Matches iOS SpeakerDiarizationOptions from Features/SpeakerDiarization/Models/SpeakerDiarizationOptions.swift
class SpeakerDiarizationOptions {
  /// Expected number of speakers (if known)
  final int? expectedSpeakers;

  /// Whether to enable real-time processing
  final bool realTimeMode;

  /// Minimum segment duration in seconds
  final double minSegmentDuration;

  /// Whether to merge adjacent segments from the same speaker
  final bool mergeAdjacentSegments;

  /// Gap duration threshold for merging (seconds)
  final double mergeGapThreshold;

  const SpeakerDiarizationOptions({
    this.expectedSpeakers,
    this.realTimeMode = false,
    this.minSegmentDuration = 0.5,
    this.mergeAdjacentSegments = true,
    this.mergeGapThreshold = 0.3,
  });

  /// Create default options
  factory SpeakerDiarizationOptions.defaults() {
    return const SpeakerDiarizationOptions();
  }

  /// Create options for real-time processing
  factory SpeakerDiarizationOptions.realTime() {
    return const SpeakerDiarizationOptions(
      realTimeMode: true,
      minSegmentDuration: 0.3,
    );
  }
}
