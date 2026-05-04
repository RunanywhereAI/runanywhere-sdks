// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_wakeword.dart — P2 feature B11 wake word capability.
//
// Mirrors Swift's `RunAnywhere+WakeWord.swift` extension. Public surface:
//   load(modelPath)
//   detect(audio)
//   unload()
//
// The native `rac_wake_word_*` C ABI exists in runanywhere-commons but
// is currently stubbed (returns RAC_ERROR_FEATURE_NOT_AVAILABLE) and
// no Dart FFI thunks have been generated for it yet. Until the native
// pipeline is wired, `load` and `detect` throw
// `SDKException.featureNotAvailable(...)`; `unload` is a no-op so
// teardown stays robust. Once commons and `NativeFunctions` expose the
// wake-word symbols, swap the bodies to forward to them.

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_state.dart';

/// Wake-word detection capability surface.
///
/// Access via `RunAnywhereSDK.instance.wakeWord`. Mirrors Swift's
/// `RunAnywhere.wakeWord` extension and Kotlin's
/// `RunAnywhere.loadWakeWordModel / detectWakeWord / unloadWakeWordModel`.
class RunAnywhereWakeWord {
  RunAnywhereWakeWord._();

  static final RunAnywhereWakeWord _instance = RunAnywhereWakeWord._();

  /// Shared singleton — matches every other capability surface.
  static RunAnywhereWakeWord get shared => _instance;

  final _logger = SDKLogger('RunAnywhere.WakeWord');

  /// True once [load] has successfully loaded a wake-word model.
  bool get isLoaded => _loadedModelPath != null;

  String? _loadedModelPath;

  // ---------------------------------------------------------------------
  // Lifecycle — canonical load / detect / unload triple.
  // ---------------------------------------------------------------------

  /// Load a wake-word model from disk.
  ///
  /// Mirrors Swift's `RunAnywhere.wakeWord.load(modelPath:)`.
  ///
  /// [modelPath] is an absolute path to a wake-word model blob
  /// (Porcupine / OpenWakeWord / pv-keyword).
  Future<void> load({required String modelPath}) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    _logger.warning(
      'load($modelPath): wake-word not wired in commons '
      '(rac_wake_word_* is stubbed)',
    );
    throw SDKException.featureNotAvailable('wake-word detection');
  }

  /// Run wake-word detection over a PCM buffer.
  ///
  /// Mirrors Swift's `RunAnywhere.wakeWord.detect(audio:)`. [audio]
  /// contains raw PCM bytes; native commons expects 16 kHz mono
  /// `float` samples but the public facade accepts `Uint8List` so
  /// call sites do not need to depend on the FFI layout.
  Future<bool> detect({required Uint8List audio}) async {
    if (!SdkState.shared.isInitialized) {
      throw SDKException.notInitialized();
    }
    _logger.warning(
      'detect(${audio.length} bytes): wake-word not wired in commons',
    );
    throw SDKException.featureNotAvailable('wake-word detection');
  }

  /// Unload the currently loaded wake-word model. Safe to call when
  /// no model is loaded — matches the `rac_wake_word_destroy`
  /// NULL-safe contract.
  ///
  /// Mirrors Swift's `RunAnywhere.wakeWord.unload()`.
  Future<void> unload() async {
    if (!SdkState.shared.isInitialized) return;
    _loadedModelPath = null;
    _logger.debug('unload: no-op (wake-word not wired in commons)');
  }
}
