import 'dart:typed_data';

/// Audio chunk for voice agent processing
/// Matches iOS VoiceAudioChunk from Features/VoiceAgent/Models/VoiceAudioChunk.swift
class VoiceAudioChunk {
  /// Raw audio data
  final Uint8List data;

  /// Sample rate of the audio
  final int sampleRate;

  /// Number of channels
  final int channels;

  /// Timestamp of this chunk (seconds from start)
  final double timestamp;

  /// Duration of this chunk (seconds)
  final double duration;

  const VoiceAudioChunk({
    required this.data,
    this.sampleRate = 16000,
    this.channels = 1,
    this.timestamp = 0.0,
    this.duration = 0.0,
  });

  /// Calculate duration from data length if not provided
  double get calculatedDuration {
    if (duration > 0) return duration;
    // Assuming 16-bit PCM audio
    final samples = data.length ~/ 2;
    return samples / sampleRate;
  }

  /// Create from raw PCM data
  factory VoiceAudioChunk.fromPCM(
    Uint8List data, {
    int sampleRate = 16000,
    int channels = 1,
    double timestamp = 0.0,
  }) {
    final samples = data.length ~/ 2;
    final duration = samples / sampleRate;
    return VoiceAudioChunk(
      data: data,
      sampleRate: sampleRate,
      channels: channels,
      timestamp: timestamp,
      duration: duration,
    );
  }
}
