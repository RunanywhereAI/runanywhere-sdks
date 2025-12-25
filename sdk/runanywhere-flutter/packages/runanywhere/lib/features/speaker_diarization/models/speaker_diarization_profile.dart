/// Profile of a speaker with statistics
/// Matches iOS SpeakerDiarizationProfile from Features/SpeakerDiarization/Models/SpeakerDiarizationProfile.swift
class SpeakerDiarizationProfile {
  /// Unique identifier for the speaker
  final String id;

  /// Speaker embedding vector
  final List<double>? embedding;

  /// Total speaking time across all segments
  final double totalSpeakingTime;

  /// Number of segments for this speaker
  final int segmentCount;

  /// Optional display name
  final String? name;

  const SpeakerDiarizationProfile({
    required this.id,
    this.embedding,
    required this.totalSpeakingTime,
    required this.segmentCount,
    this.name,
  });

  /// Create from map
  factory SpeakerDiarizationProfile.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationProfile(
      id: json['id'] as String,
      embedding: (json['embedding'] as List?)?.cast<double>(),
      totalSpeakingTime: (json['totalSpeakingTime'] as num).toDouble(),
      segmentCount: json['segmentCount'] as int,
      name: json['name'] as String?,
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'id': id,
        if (embedding != null) 'embedding': embedding,
        'totalSpeakingTime': totalSpeakingTime,
        'segmentCount': segmentCount,
        if (name != null) 'name': name,
      };
}
