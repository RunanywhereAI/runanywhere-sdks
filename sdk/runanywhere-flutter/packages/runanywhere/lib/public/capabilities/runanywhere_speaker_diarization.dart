// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_speaker_diarization.dart — Speaker Diarization (B12, §8)
// capability surface. Mirrors Swift `RunAnywhere+SpeakerDiarization.swift`
// and Kotlin `RunAnywhere+SpeakerDiarization.kt`.
//
// The C ABI for speaker diarization exists in runanywhere-commons
// (`rac_speaker_diarization_init / _process / _destroy`) but is
// currently a stub returning `RAC_ERROR_FEATURE_NOT_AVAILABLE`. There is
// also no `dart_bridge_speaker_diarization.dart` yet. Until both land:
//   • `loadModel` throws `SDKException.featureNotAvailable`
//   • `diarize` logs a warning and returns an empty segment list
//   • `unload` is a no-op
//
// TODO(diarization): add `lib/native/dart_bridge_speaker_diarization.dart`
// that wraps the three `rac_speaker_diarization_*` FFI calls, then replace
// the bodies here with real calls. Public signatures stay the same.
//
// §15 type-discipline: no `dart:ffi` types escape this capability — it's
// entirely Dart-typed.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';

/// One speaker segment returned by [RunAnywhereSpeakerDiarization.diarize].
///
/// Represents a contiguous span of audio attributed to a single speaker.
class SpeakerSegment {
  /// Zero-based speaker index. Stable within a single session.
  final int speaker;

  /// Segment start time in milliseconds from the start of the audio.
  final int startMs;

  /// Segment end time in milliseconds from the start of the audio.
  final int endMs;

  const SpeakerSegment({
    required this.speaker,
    required this.startMs,
    required this.endMs,
  });

  @override
  String toString() =>
      'SpeakerSegment(speaker=$speaker, startMs=$startMs, endMs=$endMs)';
}

/// Speaker Diarization capability surface.
///
/// Access via `RunAnywhereSDK.instance.speakerDiarization`. Mirrors Swift's
/// `RunAnywhere.diarize(audio:)` / `loadDiarizationModel(_:)` / etc.
class RunAnywhereSpeakerDiarization {
  RunAnywhereSpeakerDiarization._();

  static final RunAnywhereSpeakerDiarization _instance =
      RunAnywhereSpeakerDiarization._();

  static RunAnywhereSpeakerDiarization get shared => _instance;

  final _logger = SDKLogger('RunAnywhere.SpeakerDiarization');

  bool _loaded = false;

  /// True once a diarization model has been successfully loaded.
  bool get isLoaded => _loaded;

  /// Load the speaker-diarization model at [modelPath].
  ///
  /// Throws [SDKException.featureNotAvailable] while the native
  /// implementation is still a stub in runanywhere-commons.
  Future<void> loadModel(String modelPath) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    _logger.warning(
      'loadModel: feature not yet available in commons (stub). modelPath=$modelPath',
    );
    throw SDKException.featureNotAvailable(
      'SpeakerDiarization: rac_speaker_diarization_init',
    );
  }

  /// Run speaker diarization on a buffer of PCM audio.
  ///
  /// [audio] is IEEE-754 single-precision PCM samples, little-endian
  /// (4 bytes per sample, 16 kHz mono).
  ///
  /// Returns segments ordered by [SpeakerSegment.startMs]. Returns an
  /// empty list when the native feature is not yet available (a warning
  /// is logged so the absence is diagnosable).
  Future<List<SpeakerSegment>> diarize(Uint8List audio) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    _logger.warning(
      'diarize: feature not yet available in commons (stub). '
      'Returning empty segments. audioBytes=${audio.length}',
    );
    return const <SpeakerSegment>[];
  }

  /// Release the diarization session and its native resources.
  ///
  /// No-op while the feature is stubbed.
  Future<void> unload() async {
    _logger.debug('unload: no-op (feature stubbed)');
    _loaded = false;
  }
}
