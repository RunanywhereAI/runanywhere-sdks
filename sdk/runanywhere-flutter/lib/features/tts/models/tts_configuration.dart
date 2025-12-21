import '../../../core/protocols/component/component_configuration.dart';

/// Configuration for TTS component
/// Matches iOS TTSConfiguration from Features/TTS/Models/TTSConfiguration.swift
class TTSConfiguration implements ComponentConfiguration {
  /// Model ID for the TTS model
  @override
  final String? modelId;

  /// Voice to use for synthesis
  final String? voice;

  /// Speaking rate (0.5 - 2.0, default 1.0)
  final double rate;

  /// Pitch adjustment (-1.0 to 1.0, default 0.0)
  final double pitch;

  /// Volume (0.0 - 1.0, default 1.0)
  final double volume;

  /// Language code (e.g., 'en-US')
  final String language;

  /// Sample rate for output audio
  final int sampleRate;

  /// Whether to enable caching
  final bool enableCaching;

  const TTSConfiguration({
    this.modelId,
    this.voice,
    this.rate = 1.0,
    this.pitch = 0.0,
    this.volume = 1.0,
    this.language = 'en-US',
    this.sampleRate = 22050,
    this.enableCaching = true,
  });

  @override
  void validate() {
    if (rate < 0.5 || rate > 2.0) {
      throw ArgumentError('Rate must be between 0.5 and 2.0');
    }
    if (pitch < -1.0 || pitch > 1.0) {
      throw ArgumentError('Pitch must be between -1.0 and 1.0');
    }
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError('Volume must be between 0.0 and 1.0');
    }
  }

  /// Create a copy with modified values
  TTSConfiguration copyWith({
    String? modelId,
    String? voice,
    double? rate,
    double? pitch,
    double? volume,
    String? language,
    int? sampleRate,
    bool? enableCaching,
  }) {
    return TTSConfiguration(
      modelId: modelId ?? this.modelId,
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      language: language ?? this.language,
      sampleRate: sampleRate ?? this.sampleRate,
      enableCaching: enableCaching ?? this.enableCaching,
    );
  }
}
