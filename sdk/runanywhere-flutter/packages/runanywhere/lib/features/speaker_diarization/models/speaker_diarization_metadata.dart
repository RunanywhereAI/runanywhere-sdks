/// Metadata about the diarization processing
/// Matches iOS SpeakerDiarizationMetadata from Features/SpeakerDiarization/Models/SpeakerDiarizationMetadata.swift
class SpeakerDiarizationMetadata {
  /// Time taken to process the audio
  final double processingTime;

  /// Length of the audio processed
  final double audioLength;

  /// Number of speakers detected
  final int speakerCount;

  /// Method used for diarization ("energy", "ml", "hybrid")
  final String method;

  const SpeakerDiarizationMetadata({
    required this.processingTime,
    required this.audioLength,
    required this.speakerCount,
    required this.method,
  });

  /// Create from map
  factory SpeakerDiarizationMetadata.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationMetadata(
      processingTime: (json['processingTime'] as num).toDouble(),
      audioLength: (json['audioLength'] as num).toDouble(),
      speakerCount: json['speakerCount'] as int,
      method: json['method'] as String,
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'processingTime': processingTime,
        'audioLength': audioLength,
        'speakerCount': speakerCount,
        'method': method,
      };
}
