/// DartBridge+TTS
///
/// TTS component bridge - manages C++ TTS component lifecycle.
/// Mirrors Swift's CppBridge+TTS.swift pattern.
library dart_bridge_tts;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// TTS component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ TTS component.
/// Handles voice loading, synthesis, and streaming.
///
/// Usage:
/// ```dart
/// final tts = DartBridgeTTS.shared;
/// await tts.loadVoice('/path/to/voice', 'voice-id', 'Voice Name');
/// final audio = await tts.synthesize('Hello world');
/// ```
class DartBridgeTTS {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeTTS shared = DartBridgeTTS._();

  DartBridgeTTS._();

  // MARK: - State

  RacHandle? _handle;
  String? _loadedVoiceId;
  final _logger = SDKLogger('DartBridge.TTS');

  // MARK: - Handle Management

  /// Get or create the TTS component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final create = lib.lookupFunction<
          Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_tts_component_create');

      final handlePtr = calloc<RacHandle>();
      try {
        final result = create(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create TTS component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('TTS component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create TTS handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a voice is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_is_loaded');

      return isLoadedFn(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded voice ID.
  String? get currentVoiceId => _loadedVoiceId;

  // MARK: - Voice Lifecycle

  /// Load a TTS voice.
  ///
  /// [voicePath] - Full path to the voice model.
  /// [voiceId] - Unique identifier for the voice.
  /// [voiceName] - Human-readable name.
  ///
  /// Throws on failure.
  Future<void> loadVoice(
    String voicePath,
    String voiceId,
    String voiceName,
  ) async {
    final handle = getHandle();

    final pathPtr = voicePath.toNativeUtf8();
    final idPtr = voiceId.toNativeUtf8();
    final namePtr = voiceName.toNativeUtf8();

    try {
      final lib = PlatformLoader.loadCommons();
      final loadVoiceFn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_tts_component_load_voice');

      final result = loadVoiceFn(handle, pathPtr, idPtr, namePtr);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load TTS voice: ${RacResultCode.getMessage(result)}',
        );
      }

      _loadedVoiceId = voiceId;
      _logger.info('TTS voice loaded: $voiceId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  /// Unload the current voice.
  void unload() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cleanupFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_cleanup');

      cleanupFn(_handle!);
      _loadedVoiceId = null;
      _logger.info('TTS voice unloaded');
    } catch (e) {
      _logger.error('Failed to unload TTS voice: $e');
    }
  }

  /// Stop ongoing synthesis.
  void stop() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final stopFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_tts_component_stop');

      stopFn(_handle!);
      _logger.debug('TTS synthesis stopped');
    } catch (e) {
      _logger.error('Failed to stop TTS: $e');
    }
  }

  // MARK: - Synthesis

  /// Synthesize speech from text.
  ///
  /// [text] - Text to synthesize.
  ///
  /// Returns audio data as Float32 samples and sample rate.
  Future<TTSComponentResult> synthesize(String text) async {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No TTS voice loaded. Call loadVoice() first.');
    }

    final textPtr = text.toNativeUtf8();
    final resultPtr = calloc<RacTtsResultStruct>();

    try {
      final lib = PlatformLoader.loadCommons();
      final synthesizeFn = lib.lookupFunction<
          Int32 Function(RacHandle, Pointer<Utf8>, Pointer<RacTtsResultStruct>),
          int Function(RacHandle, Pointer<Utf8>,
              Pointer<RacTtsResultStruct>)>('rac_tts_component_synthesize');

      final status = synthesizeFn(handle, textPtr, resultPtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'TTS synthesis failed: ${RacResultCode.getMessage(status)}',
        );
      }

      final result = resultPtr.ref;

      // Copy audio samples
      final numSamples = result.numSamples;
      Float32List samples;
      if (numSamples > 0 && result.audioSamples != nullptr) {
        samples = result.audioSamples.asTypedList(numSamples);
        // Make a copy since the native memory will be freed
        samples = Float32List.fromList(samples);
      } else {
        samples = Float32List(0);
      }

      return TTSComponentResult(
        samples: samples,
        sampleRate: result.sampleRate,
        durationMs: result.durationMs,
      );
    } finally {
      calloc.free(textPtr);
      // Note: Audio samples should be freed by caller if allocated by C++
      calloc.free(resultPtr);
    }
  }

  /// Synthesize with streaming.
  ///
  /// Returns a stream of audio chunks.
  Stream<TTSStreamResult> synthesizeStream(String text) async* {
    // For now, generate all audio and emit in chunks
    final result = await synthesize(text);

    // Emit in ~100ms chunks
    final samplesPerChunk = (result.sampleRate * 0.1).round();
    var offset = 0;

    while (offset < result.samples.length) {
      final end = (offset + samplesPerChunk).clamp(0, result.samples.length);
      final chunk = result.samples.sublist(offset, end);

      yield TTSStreamResult(
        samples: chunk,
        sampleRate: result.sampleRate,
        isFinal: end >= result.samples.length,
      );

      offset = end;
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(RacHandle),
            void Function(RacHandle)>('rac_tts_component_destroy');

        destroyFn(_handle!);
        _handle = null;
        _loadedVoiceId = null;
        _logger.debug('TTS component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy TTS component: $e');
      }
    }
  }
}

/// Result from TTS synthesis.
class TTSComponentResult {
  final Float32List samples;
  final int sampleRate;
  final int durationMs;

  const TTSComponentResult({
    required this.samples,
    required this.sampleRate,
    required this.durationMs,
  });

  /// Duration in seconds.
  double get durationSeconds => durationMs / 1000.0;
}

/// Streaming result from TTS synthesis.
class TTSStreamResult {
  final Float32List samples;
  final int sampleRate;
  final bool isFinal;

  const TTSStreamResult({
    required this.samples,
    required this.sampleRate,
    required this.isFinal,
  });
}

/// FFI struct for TTS result (matches rac_tts_result_t)
final class RacTtsResultStruct extends Struct {
  external Pointer<Float> audioSamples;

  @IntPtr()
  external int numSamples;

  @Int32()
  external int sampleRate;

  @Int32()
  external int durationMs;
}
