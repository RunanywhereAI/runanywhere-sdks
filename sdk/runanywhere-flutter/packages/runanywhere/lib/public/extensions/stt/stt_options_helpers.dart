// Phase C-prime FLUTTER: Dart-side helpers layered on top of the
// canonical proto types in `stt_options.pb.dart` / `.pbenum.dart`.
// The proto bindings are the source of truth for shape; these
// extensions add idiomatic Dart conveniences (Duration getters for
// Int64-millisecond timestamps, validity checks) without modifying
// the generated files.
//
// The `STTLanguageBcp47.bcp47` getter / `fromBcp47` static factory
// were retired in T6.4 — call sites now use the generated
// `STTLanguageWireString.wireString` extension and the top-level
// `sttLanguageFromWireString` factory in
// `package:runanywhere/generated/convenience/ra_convenience.dart`
// (the BCP-47 codes ARE the wire strings; see idl/stt_options.proto
// `rac_wire_string` annotations on `STTLanguage`).

import 'package:fixnum/fixnum.dart';

import 'package:runanywhere/generated/stt_options.pb.dart';

/// Helpers on the proto [STTConfiguration] message.
extension STTConfigurationHelpers on STTConfiguration {
  /// True when `modelId` is non-empty — the minimum requirement for
  /// the C bridge to load a model.
  bool get isValid => modelId.isNotEmpty;
}

/// Helpers on the proto [WordTimestamp] message — convert the
/// Int64-millisecond fields into idiomatic [Duration]s.
extension WordTimestampHelpers on WordTimestamp {
  /// Word start position as a [Duration].
  Duration get start => Duration(milliseconds: startMs.toInt());

  /// Word end position as a [Duration].
  Duration get end => Duration(milliseconds: endMs.toInt());

  /// Word duration (`end - start`) as a [Duration].
  Duration get duration => end - start;
}

/// Helpers on the proto [TranscriptionMetadata] message — convert the
/// Int64-millisecond fields into idiomatic seconds doubles.
extension TranscriptionMetadataHelpers on TranscriptionMetadata {
  /// Wall-clock processing time in seconds.
  double get processingTimeSeconds => processingTimeMs.toInt() / 1000.0;

  /// Total audio length in seconds.
  double get audioLengthSeconds => audioLengthMs.toInt() / 1000.0;

  /// Real-time factor (`processingTime / audioLength`). Falls back to
  /// the proto-recorded `realTimeFactor` when audio length is zero.
  double get computedRealTimeFactor {
    final audio = audioLengthMs.toInt();
    if (audio <= 0) return realTimeFactor;
    return processingTimeMs.toInt() / audio;
  }
}

/// Convenience constructor wrappers — Int64 ergonomics.
WordTimestamp wordTimestamp({
  required String word,
  required int startMs,
  required int endMs,
  double? confidence,
}) =>
    WordTimestamp(
      word: word,
      startMs: Int64(startMs),
      endMs: Int64(endMs),
      confidence: confidence,
    );
