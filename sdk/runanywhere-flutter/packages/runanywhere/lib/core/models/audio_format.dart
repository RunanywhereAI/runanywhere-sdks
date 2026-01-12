/// Audio format information
/// Matches iOS AudioFormat enum from SharedComponentTypes.swift
enum AudioFormat {
  wav,
  mp3,
  m4a,
  flac,
  pcm,
  opus;

  /// Get the default sample rate for this audio format
  int get sampleRate {
    switch (this) {
      case AudioFormat.wav:
      case AudioFormat.pcm:
      case AudioFormat.flac:
        return 16000;
      case AudioFormat.mp3:
      case AudioFormat.m4a:
        return 44100;
      case AudioFormat.opus:
        return 48000;
    }
  }

  /// Get the string value representation
  String get value {
    switch (this) {
      case AudioFormat.wav:
        return 'wav';
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.m4a:
        return 'm4a';
      case AudioFormat.flac:
        return 'flac';
      case AudioFormat.pcm:
        return 'pcm';
      case AudioFormat.opus:
        return 'opus';
    }
  }
}

/// Audio metadata
class AudioMetadata {
  final int channelCount;
  final int? bitDepth;
  final String? codec;

  AudioMetadata({
    this.channelCount = 1,
    this.bitDepth,
    this.codec,
  });
}
