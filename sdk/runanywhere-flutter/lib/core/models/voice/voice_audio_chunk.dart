import 'dart:typed_data';

/// A chunk of audio data for streaming processing
///
/// Corresponds to iOS SDK's VoiceAudioChunk struct in AudioChunk.swift
class VoiceAudioChunk {
  /// The audio samples as Float32 list (SIMPLIFIED - no more Data conversion)
  final Float32List samples;

  /// Timestamp when this chunk was captured
  final Duration timestamp;

  /// Sample rate of the audio (e.g., 16000 for 16kHz)
  final int sampleRate;

  /// Number of channels (1 for mono, 2 for stereo)
  final int channels;

  /// Sequence number for ordering chunks
  final int sequenceNumber;

  /// Whether this is the final chunk in a stream
  final bool isFinal;

  const VoiceAudioChunk({
    required this.samples,
    required this.timestamp,
    this.sampleRate = 16000,
    this.channels = 1,
    this.sequenceNumber = 0,
    this.isFinal = false,
  });

  /// Create from a List<double> for convenience
  factory VoiceAudioChunk.fromDoubles({
    required List<double> samples,
    required Duration timestamp,
    int sampleRate = 16000,
    int channels = 1,
    int sequenceNumber = 0,
    bool isFinal = false,
  }) {
    return VoiceAudioChunk(
      samples: Float32List.fromList(samples.map((d) => d.toDouble()).toList()),
      timestamp: timestamp,
      sampleRate: sampleRate,
      channels: channels,
      sequenceNumber: sequenceNumber,
      isFinal: isFinal,
    );
  }

  /// Convert Float samples to raw bytes (Uint8List)
  Uint8List get data => samples.buffer.asUint8List();

  /// Duration of this audio chunk in seconds
  Duration get duration {
    final seconds = samples.length / (sampleRate * channels);
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// Number of samples in this chunk
  int get sampleCount => samples.length ~/ channels;

  /// Create a copy with updated values
  VoiceAudioChunk copyWith({
    Float32List? samples,
    Duration? timestamp,
    int? sampleRate,
    int? channels,
    int? sequenceNumber,
    bool? isFinal,
  }) {
    return VoiceAudioChunk(
      samples: samples ?? this.samples,
      timestamp: timestamp ?? this.timestamp,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  @override
  String toString() =>
      'VoiceAudioChunk(samples: ${samples.length}, timestamp: $timestamp, '
      'sampleRate: $sampleRate, channels: $channels, '
      'sequenceNumber: $sequenceNumber, isFinal: $isFinal)';
}
