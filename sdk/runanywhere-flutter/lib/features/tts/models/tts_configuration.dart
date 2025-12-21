import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/core/protocols/component/component_configuration.dart';

/// Configuration for TTS component
/// Matches iOS TTSConfiguration from Features/TTS/Models/TTSConfiguration.swift
class TTSConfiguration implements ComponentConfiguration {
  /// Model ID for the TTS model
  final String? modelId;

  /// Voice to use for synthesis
  final String voice;

  /// Language code (e.g., 'en-US')
  final String language;

  /// Speaking rate (0.5 - 2.0, default 1.0)
  final double speakingRate;

  /// Pitch adjustment (0.5 to 2.0, default 1.0)
  final double pitch;

  /// Volume (0.0 - 1.0, default 1.0)
  final double volume;

  /// Audio format for output
  final AudioFormat audioFormat;

  /// Sample rate for output audio
  final int sampleRate;

  /// Whether to use neural voice
  final bool useNeuralVoice;

  /// Whether to enable SSML parsing
  final bool enableSSML;

  /// Whether to enable caching
  final bool enableCaching;

  const TTSConfiguration({
    this.modelId,
    this.voice = 'system',
    this.language = 'en-US',
    this.speakingRate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcm,
    this.sampleRate = 22050,
    this.useNeuralVoice = true,
    this.enableSSML = false,
    this.enableCaching = true,
  });

  @override
  void validate() {
    if (speakingRate < 0.5 || speakingRate > 2.0) {
      throw ArgumentError('Speaking rate must be between 0.5 and 2.0');
    }
    if (pitch < 0.5 || pitch > 2.0) {
      throw ArgumentError('Pitch must be between 0.5 and 2.0');
    }
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError('Volume must be between 0.0 and 1.0');
    }
  }

  /// Create a copy with modified values
  TTSConfiguration copyWith({
    String? modelId,
    String? voice,
    String? language,
    double? speakingRate,
    double? pitch,
    double? volume,
    AudioFormat? audioFormat,
    int? sampleRate,
    bool? useNeuralVoice,
    bool? enableSSML,
    bool? enableCaching,
  }) {
    return TTSConfiguration(
      modelId: modelId ?? this.modelId,
      voice: voice ?? this.voice,
      language: language ?? this.language,
      speakingRate: speakingRate ?? this.speakingRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      audioFormat: audioFormat ?? this.audioFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      useNeuralVoice: useNeuralVoice ?? this.useNeuralVoice,
      enableSSML: enableSSML ?? this.enableSSML,
      enableCaching: enableCaching ?? this.enableCaching,
    );
  }
}
