/// Audio format information.
///
/// GAP 01 Phase 4: this Dart enum remains the public surface; the
/// `toProto()` / `fromProto()` extension bridges the IDL-generated
/// `package:runanywhere/generated/model_types.pbenum.dart :: AudioFormat`
/// to prevent drift between platform SDKs.
///
/// Matches iOS AudioFormat enum from SharedComponentTypes.swift.
library audio_format;

import 'package:runanywhere/generated/model_types.pbenum.dart' as pb;

enum AudioFormat {
  wav,
  mp3,
  m4a,
  flac,
  pcm,
  opus;

  /// Get the default sample rate for this audio format.
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

  /// Get the string value representation.
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

  /// Convert to the IDL-generated Wire enum. Drift-preventing bijection.
  pb.AudioFormat toProto() {
    switch (this) {
      case AudioFormat.wav:
        return pb.AudioFormat.AUDIO_FORMAT_WAV;
      case AudioFormat.mp3:
        return pb.AudioFormat.AUDIO_FORMAT_MP3;
      case AudioFormat.m4a:
        return pb.AudioFormat.AUDIO_FORMAT_M4A;
      case AudioFormat.flac:
        return pb.AudioFormat.AUDIO_FORMAT_FLAC;
      case AudioFormat.pcm:
        return pb.AudioFormat.AUDIO_FORMAT_PCM;
      case AudioFormat.opus:
        return pb.AudioFormat.AUDIO_FORMAT_OPUS;
    }
  }

  /// Decode from the IDL-generated Wire enum. Unsupported cases → null.
  static AudioFormat? fromProto(pb.AudioFormat proto) {
    if (proto == pb.AudioFormat.AUDIO_FORMAT_WAV) return AudioFormat.wav;
    if (proto == pb.AudioFormat.AUDIO_FORMAT_MP3) return AudioFormat.mp3;
    if (proto == pb.AudioFormat.AUDIO_FORMAT_M4A) return AudioFormat.m4a;
    if (proto == pb.AudioFormat.AUDIO_FORMAT_FLAC) return AudioFormat.flac;
    if (proto == pb.AudioFormat.AUDIO_FORMAT_PCM) return AudioFormat.pcm;
    if (proto == pb.AudioFormat.AUDIO_FORMAT_OPUS) return AudioFormat.opus;
    // AAC / OGG / PCM_S16LE / UNSPECIFIED fall through
    return null;
  }
}

/// Audio metadata.
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
