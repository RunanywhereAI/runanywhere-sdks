/// DartBridge+TTS
///
/// TTS component bridge - manages C++ TTS component lifecycle.
/// Mirrors Swift's CppBridge+TTS.swift pattern.
library dart_bridge_tts;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/features/tts/tts_configuration.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_functions.dart';
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
      final handlePtr = calloc<RacHandle>();
      try {
        final result = NativeFunctions.ttsCreate(handlePtr);

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
      return NativeFunctions.ttsIsLoaded(_handle!) == RAC_TRUE;
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
      final result = NativeFunctions.ttsLoadVoice(handle, pathPtr, idPtr, namePtr);

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
      NativeFunctions.ttsCleanup(_handle!);
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
      NativeFunctions.ttsStop(_handle!);
      _logger.debug('TTS synthesis stopped');
    } catch (e) {
      _logger.error('Failed to stop TTS: $e');
    }
  }

  // MARK: - Synthesis

  /// Synthesize speech from text.
  ///
  /// [text] - Text to synthesize.
  /// [rate] - Speech rate (0.5 to 2.0, 1.0 is normal).
  /// [pitch] - Speech pitch (0.5 to 2.0, 1.0 is normal).
  /// [volume] - Speech volume (0.0 to 1.0).
  /// [language] - BCP-47 language tag (default "en-US").
  /// [audioFormat] - Output audio format constant (default PCM).
  /// [sampleRate] - Output sample rate (default 22050).
  /// [useSsml] - Whether the input is SSML (default false).
  /// [voiceId] - Override the loaded voice (rarely needed; default null).
  ///
  /// Returns audio data and metadata.
  /// Runs in a background isolate to prevent UI blocking.
  Future<TTSComponentResult> synthesize(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    String language = 'en-US',
    int audioFormat = racAudioFormatPcm,
    int sampleRate = 22050,
    bool useSsml = false,
    String? voiceId,
  }) async {
    TTSComponentConfig(
      speakingRate: rate,
      pitch: pitch,
      volume: volume,
    ).validate();

    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No TTS voice loaded. Call loadVoice() first.');
    }

    _logger.debug(
        'Synthesizing "${text.substring(0, text.length.clamp(0, 50))}..." in background isolate');

    // Run synthesis in background isolate
    final result = await Isolate.run(() => _synthesizeInIsolate(
          handle.address,
          text,
          rate,
          pitch,
          volume,
          language,
          audioFormat,
          sampleRate,
          useSsml,
          voiceId,
        ));

    _logger.info(
        'Synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz, ${result.durationMs}ms');

    return result;
  }

  /// Static helper to perform FFI synthesis in isolate.
  /// Must be static/top-level for Isolate.run().
  static TTSComponentResult _synthesizeInIsolate(
    int handleAddress,
    String text,
    double rate,
    double pitch,
    double volume,
    String language,
    int audioFormat,
    int sampleRate,
    bool useSsml,
    String? voiceId,
  ) {
    final lib = PlatformLoader.loadCommons();
    final handle = RacHandle.fromAddress(handleAddress);

    // Allocate native memory
    final textPtr = text.toNativeUtf8();
    final optionsPtr = calloc<RacTtsOptionsStruct>();
    final resultPtr = calloc<RacTtsResultStruct>();
    final voicePtr = voiceId?.toNativeUtf8();

    try {
      // Set up options (matches Swift's TTSOptions wire shape).
      final languagePtr = language.toNativeUtf8();
      optionsPtr.ref.voice = voicePtr ?? nullptr;
      optionsPtr.ref.language = languagePtr;
      optionsPtr.ref.rate = rate;
      optionsPtr.ref.pitch = pitch;
      optionsPtr.ref.volume = volume;
      optionsPtr.ref.audioFormat = audioFormat;
      optionsPtr.ref.sampleRate = sampleRate;
      optionsPtr.ref.useSsml = useSsml ? RAC_TRUE : RAC_FALSE;

      // Get synthesize function
      final synthesizeFn = lib.lookupFunction<
          Int32 Function(
            RacHandle,
            Pointer<Utf8>,
            Pointer<RacTtsOptionsStruct>,
            Pointer<RacTtsResultStruct>,
          ),
          int Function(
            RacHandle,
            Pointer<Utf8>,
            Pointer<RacTtsOptionsStruct>,
            Pointer<RacTtsResultStruct>,
          )>('rac_tts_component_synthesize');

      final status = synthesizeFn(
        handle,
        textPtr,
        optionsPtr,
        resultPtr,
      );

      // Free the language string
      calloc.free(languagePtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'TTS synthesis failed: ${RacResultCode.getMessage(status)}',
        );
      }

      // Extract result before freeing
      final result = resultPtr.ref;
      final audioSize = result.audioSize;
      final outputSampleRate = result.sampleRate;
      final durationMs = result.durationMs;

      // Convert audio data to Float32List
      // The audio data is PCM float samples
      Float32List samples;
      if (audioSize > 0 && result.audioData != nullptr) {
        // Audio size is in bytes, each float is 4 bytes
        final numSamples = audioSize ~/ 4;
        final floatPtr = result.audioData.cast<Float>();
        // `Float32List.fromList` performs an element-by-element copy out of
        // the native buffer so the returned list is owned by the Dart heap.
        samples = Float32List.fromList(floatPtr.asTypedList(numSamples));
      } else {
        samples = Float32List(0);
      }

      // B-FL-12-002: the C ABI is "callee allocates audio_data via malloc(),
      // caller MUST free via rac_tts_result_free()" (see rac_tts_service.h
      // line 115). Skipping this leaks ~1 MiB per synthesis and — combined
      // with the Cleaner-thread sweep that runs on the libc heap — eventually
      // trips Scudo's corrupted-chunk-header detector inside
      // BinderProxy_destroy / Binder_destroy on the ReferenceQueueDaemon
      // thread, killing the process via SIGABRT. Calling
      // rac_tts_result_free after the copy returns the buffer to libc through
      // the same allocator that produced it (Sherpa malloc -> libc free) and
      // matches the contract every other binding (Swift / Kotlin / RN) honors.
      try {
        final freeFn = lib.lookupFunction<
            Void Function(Pointer<RacTtsResultStruct>),
            void Function(Pointer<RacTtsResultStruct>)>('rac_tts_result_free');
        freeFn(resultPtr);
      } catch (_) {
        // If the symbol isn't exported on this build, fall back silently —
        // we still surface the synthesized samples to the caller.
      }

      return TTSComponentResult(
        samples: samples,
        sampleRate: outputSampleRate,
        durationMs: durationMs,
      );
    } finally {
      calloc.free(textPtr);
      calloc.free(optionsPtr);
      calloc.free(resultPtr);
      if (voicePtr != null) {
        calloc.free(voicePtr);
      }
    }
  }

  /// Synthesize with streaming.
  ///
  /// Returns a stream of audio chunks. Until the underlying C bridge
  /// supports per-chunk callbacks, this fans out the synchronous
  /// result in ~100 ms slices.
  Stream<TTSStreamResult> synthesizeStream(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    String language = 'en-US',
    int audioFormat = racAudioFormatPcm,
    int sampleRate = 22050,
    bool useSsml = false,
    String? voiceId,
  }) async* {
    final result = await synthesize(
      text,
      rate: rate,
      pitch: pitch,
      volume: volume,
      language: language,
      audioFormat: audioFormat,
      sampleRate: sampleRate,
      useSsml: useSsml,
      voiceId: voiceId,
    );

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
        NativeFunctions.ttsDestroy(_handle!);
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

// =============================================================================
// FFI Structs
// =============================================================================

/// Audio format constants (matches rac_audio_format_enum_t)
const int racAudioFormatPcm = 0;
const int racAudioFormatWav = 1;

/// FFI struct for TTS options (matches rac_tts_options_t)
final class RacTtsOptionsStruct extends Struct {
  /// Voice to use for synthesis (can be NULL for default)
  external Pointer<Utf8> voice;

  /// Language for synthesis (BCP-47 format, e.g., "en-US")
  external Pointer<Utf8> language;

  /// Speech rate (0.0 to 2.0, 1.0 is normal)
  @Float()
  external double rate;

  /// Speech pitch (0.0 to 2.0, 1.0 is normal)
  @Float()
  external double pitch;

  /// Speech volume (0.0 to 1.0)
  @Float()
  external double volume;

  /// Audio format for output
  @Int32()
  external int audioFormat;

  /// Sample rate for output audio in Hz
  @Int32()
  external int sampleRate;

  /// Whether to use SSML markup
  @Int32()
  external int useSsml;
}

/// FFI struct for TTS result (matches rac_tts_result_t)
final class RacTtsResultStruct extends Struct {
  /// Audio data (PCM float samples)
  external Pointer<Void> audioData;

  /// Size of audio data in bytes
  @IntPtr()
  external int audioSize;

  /// Audio format
  @Int32()
  external int audioFormat;

  /// Sample rate
  @Int32()
  external int sampleRate;

  /// Duration in milliseconds
  @Int64()
  external int durationMs;

  /// Processing time in milliseconds
  @Int64()
  external int processingTimeMs;
}
