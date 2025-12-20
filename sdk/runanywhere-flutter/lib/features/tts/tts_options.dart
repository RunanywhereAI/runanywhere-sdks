import '../../core/models/audio_format.dart';

/// Options for text-to-speech synthesis
/// Matches iOS TTSOptions struct from TTSComponent.swift
class TTSOptions {
  /// Voice to use for synthesis
  final String? voice;

  /// Language for synthesis
  final String language;

  /// Speech rate (0.0 to 2.0, 1.0 is normal)
  final double rate;

  /// Speech pitch (0.0 to 2.0, 1.0 is normal)
  final double pitch;

  /// Speech volume (0.0 to 1.0)
  final double volume;

  /// Audio format for output
  final AudioFormat audioFormat;

  /// Sample rate for output audio
  final int sampleRate;

  /// Whether to use SSML markup
  final bool useSSML;

  TTSOptions({
    this.voice,
    this.language = 'en-US',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcm,
    this.sampleRate = 16000,
    this.useSSML = false,
  });
}
