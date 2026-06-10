// SPDX-License-Identifier: Apache-2.0
//
// audio_convert.dart — public PCM conversion helpers.
//
// Mirrors Swift `RAAudioConvert.swift` (and the commons
// `rac_audio_pcm16_to_float32` inline routine) so callers feeding raw Int16
// microphone PCM into `RunAnywhere.detectVoiceActivity(...)` /
// `transcribe(...)` do not need to reimplement the divide-by-32768.0
// normalisation, matching the canonical commons audio normalisation contract.
//
// Swift exposes these as static functions on the `RunAnywhere` enum. Dart has
// no static extensions on free enums, so — exactly like `RunAnywhereLogging` —
// the helpers live on a dedicated `RunAnywhereAudioConvert` class.

import 'dart:typed_data';

/// Public PCM conversion helpers. One-to-one parity with Swift's
/// `extension RunAnywhere` in `RAAudioConvert.swift`.
abstract final class RunAnywhereAudioConvert {
  const RunAnywhereAudioConvert._();

  /// Convert a buffer of Int16 PCM samples to Float32 samples in the range
  /// `[-1.0, 1.0]`. Matches Swift `RunAnywhere.pcm16ToFloat32(_:)` and commons
  /// `rac_audio_pcm16_to_float32` (divides each sample by `32768.0`).
  ///
  /// [int16Bytes] holds raw Int16 PCM samples (little-endian, as captured by
  /// platform recorders). The bit pattern is preserved verbatim. Returns the
  /// Float32 samples encoded little-endian; the byte layout matches what
  /// `RunAnywhere.detectVoiceActivity(...)` and the STT/VAD streaming APIs
  /// accept as input.
  static Float32List pcm16ToFloat32(Uint8List int16Bytes) {
    final samples = pcm16ToFloat32Samples(int16Bytes);
    if (samples.isEmpty) return Float32List(0);
    return Float32List.fromList(samples);
  }

  /// Convenience overload that returns the normalised samples as a
  /// `List<double>` when callers want to inspect samples directly without going
  /// through the SDK's bytes-based audio surface. Matches Swift
  /// `RunAnywhere.pcm16ToFloat32Samples(_:)`.
  static List<double> pcm16ToFloat32Samples(Uint8List int16Bytes) {
    final int16Count = int16Bytes.lengthInBytes ~/ 2;
    if (int16Count == 0) return const <double>[];
    final view = ByteData.sublistView(int16Bytes);
    return List<double>.generate(
      int16Count,
      (i) => view.getInt16(i * 2, Endian.little) / 32768.0,
    );
  }

  /// Wrap raw 16-bit mono PCM samples in a canonical 44-byte WAV (RIFF)
  /// container: `RIFF` + `fmt ` (16-byte PCM chunk, format tag 1, 1 channel)
  /// + `data`. Matches Swift `RunAnywhere.pcm16ToWav(_:sampleRate:)`
  /// (`RAAudioConvert.swift:67`).
  ///
  /// Use this when a consumer needs a self-describing audio container rather
  /// than headerless PCM — e.g. cloud STT providers that upload the bytes as
  /// an `audio/wav` file part.
  ///
  /// [int16Bytes] holds raw Int16 mono PCM samples (little-endian); the
  /// sample bytes are copied verbatim after the header. [sampleRate] is the
  /// capture sample rate in Hz (e.g. 16000).
  static Uint8List pcm16ToWav(Uint8List int16Bytes, {required int sampleRate}) {
    const pcmFormatTag = 1;
    const channels = 1;
    const bitsPerSample = 16;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final byteRate = sampleRate * blockAlign;
    const fmtChunkSize = 16;
    final dataLength = int16Bytes.length;

    final wav = Uint8List(44 + dataLength);
    final view = ByteData.sublistView(wav);
    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        view.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    view.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    view.setUint32(16, fmtChunkSize, Endian.little);
    view.setUint16(20, pcmFormatTag, Endian.little);
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    view.setUint32(40, dataLength, Endian.little);
    wav.setAll(44, int16Bytes);
    return wav;
  }
}
