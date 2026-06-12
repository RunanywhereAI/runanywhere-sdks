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
}
