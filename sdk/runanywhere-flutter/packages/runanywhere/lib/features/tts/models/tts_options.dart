import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';

/// Options for text-to-speech synthesis
/// These options can be passed to individual synthesis calls to override
/// the default configuration settings.
/// Matches iOS TTSOptions from Features/TTS/Models/TTSOptions.swift
class TTSOptions {
  /// Voice to use for synthesis (nil uses default)
  final String? voice;

  /// Language for synthesis (BCP-47 format, e.g., "en-US")
  final String language;

  /// Speech rate (0.5 to 2.0, 1.0 is normal)
  final double rate;

  /// Speech pitch (0.5 to 2.0, 1.0 is normal)
  final double pitch;

  /// Speech volume (0.0 to 1.0)
  final double volume;

  /// Audio format for output
  final AudioFormat audioFormat;

  /// Sample rate for output audio in Hz
  final int sampleRate;

  /// Whether to use SSML markup
  final bool useSSML;

  const TTSOptions({
    this.voice,
    this.language = 'en-US',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcm,
    this.sampleRate = 16000,
    this.useSSML = false,
  });

  /// Create options from TTSConfiguration
  factory TTSOptions.fromConfiguration(TTSConfiguration configuration) {
    return TTSOptions(
      voice: configuration.voice,
      language: configuration.language,
      rate: configuration.speakingRate,
      pitch: configuration.pitch,
      volume: configuration.volume,
      audioFormat: configuration.audioFormat,
      sampleRate: configuration.audioFormat == AudioFormat.pcm ? 16000 : 44100,
      useSSML: configuration.enableSSML,
    );
  }

  /// Default options
  static const TTSOptions defaultOptions = TTSOptions();

  /// Create a copy with modified values
  TTSOptions copyWith({
    String? voice,
    String? language,
    double? rate,
    double? pitch,
    double? volume,
    AudioFormat? audioFormat,
    int? sampleRate,
    bool? useSSML,
  }) {
    return TTSOptions(
      voice: voice ?? this.voice,
      language: language ?? this.language,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      audioFormat: audioFormat ?? this.audioFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      useSSML: useSSML ?? this.useSSML,
    );
  }
}
