// Phase C-prime FLUTTER: Dart-side helpers layered on top of the
// canonical proto types in `stt_options.pb.dart` / `.pbenum.dart`.
// The proto bindings are the source of truth for shape; these
// extensions add idiomatic Dart conveniences (BCP-47 language strings,
// `Duration` getters for Int64-millisecond timestamps, default-config
// factories, validity checks) without modifying the generated files.

import 'package:fixnum/fixnum.dart';

import 'package:runanywhere/generated/stt_options.pb.dart';
import 'package:runanywhere/generated/stt_options.pbenum.dart';

/// Map a proto [STTLanguage] enum to a BCP-47 string ("en", "es", ...).
extension STTLanguageBcp47 on STTLanguage {
  /// BCP-47 / ISO-639-1 language code. `null` for `UNSPECIFIED` / `AUTO`.
  String? get bcp47 {
    switch (this) {
      case STTLanguage.STT_LANGUAGE_EN:
        return 'en';
      case STTLanguage.STT_LANGUAGE_ES:
        return 'es';
      case STTLanguage.STT_LANGUAGE_FR:
        return 'fr';
      case STTLanguage.STT_LANGUAGE_DE:
        return 'de';
      case STTLanguage.STT_LANGUAGE_ZH:
        return 'zh';
      case STTLanguage.STT_LANGUAGE_JA:
        return 'ja';
      case STTLanguage.STT_LANGUAGE_KO:
        return 'ko';
      case STTLanguage.STT_LANGUAGE_IT:
        return 'it';
      case STTLanguage.STT_LANGUAGE_PT:
        return 'pt';
      case STTLanguage.STT_LANGUAGE_AR:
        return 'ar';
      case STTLanguage.STT_LANGUAGE_RU:
        return 'ru';
      case STTLanguage.STT_LANGUAGE_HI:
        return 'hi';
      default:
        return null;
    }
  }

  /// Parse a BCP-47 / ISO-639-1 string into an [STTLanguage]. Falls
  /// back to [STT_LANGUAGE_AUTO] for empty / unknown input.
  static STTLanguage fromBcp47(String? code) {
    if (code == null || code.isEmpty) return STTLanguage.STT_LANGUAGE_AUTO;
    switch (code.toLowerCase().split('-').first) {
      case 'en':
        return STTLanguage.STT_LANGUAGE_EN;
      case 'es':
        return STTLanguage.STT_LANGUAGE_ES;
      case 'fr':
        return STTLanguage.STT_LANGUAGE_FR;
      case 'de':
        return STTLanguage.STT_LANGUAGE_DE;
      case 'zh':
        return STTLanguage.STT_LANGUAGE_ZH;
      case 'ja':
        return STTLanguage.STT_LANGUAGE_JA;
      case 'ko':
        return STTLanguage.STT_LANGUAGE_KO;
      case 'it':
        return STTLanguage.STT_LANGUAGE_IT;
      case 'pt':
        return STTLanguage.STT_LANGUAGE_PT;
      case 'ar':
        return STTLanguage.STT_LANGUAGE_AR;
      case 'ru':
        return STTLanguage.STT_LANGUAGE_RU;
      case 'hi':
        return STTLanguage.STT_LANGUAGE_HI;
      default:
        return STTLanguage.STT_LANGUAGE_AUTO;
    }
  }
}

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
