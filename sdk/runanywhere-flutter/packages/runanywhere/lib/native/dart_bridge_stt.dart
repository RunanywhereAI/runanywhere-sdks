/// DartBridge+STT
///
/// STT component bridge - manages C++ STT component lifecycle.
/// Mirrors Swift's CppBridge+STT.swift pattern.
library dart_bridge_stt;

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// STT component bridge for C++ interop.
///
/// Provides thread-safe access to the C++ STT component.
/// Handles model loading, transcription, and streaming.
///
/// Usage:
/// ```dart
/// final stt = DartBridgeSTT.shared;
/// await stt.loadModel('/path/to/model', 'model-id', 'Model Name');
/// final text = await stt.transcribe(audioData);
/// ```
class DartBridgeSTT {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeSTT shared = DartBridgeSTT._();

  DartBridgeSTT._();

  // MARK: - State

  RacHandle? _handle;
  String? _loadedModelId;
  final _logger = SDKLogger('DartBridge.STT');

  // MARK: - Handle Management

  /// Get or create the STT component handle.
  RacHandle getHandle() {
    if (_handle != null) {
      return _handle!;
    }

    try {
      final lib = PlatformLoader.loadCommons();
      final create = lib.lookupFunction<Int32 Function(Pointer<RacHandle>),
          int Function(Pointer<RacHandle>)>('rac_stt_component_create');

      final handlePtr = calloc<RacHandle>();
      try {
        final result = create(handlePtr);

        if (result != RAC_SUCCESS) {
          throw StateError(
            'Failed to create STT component: ${RacResultCode.getMessage(result)}',
          );
        }

        _handle = handlePtr.value;
        _logger.debug('STT component created');
        return _handle!;
      } finally {
        calloc.free(handlePtr);
      }
    } catch (e) {
      _logger.error('Failed to create STT handle: $e');
      rethrow;
    }
  }

  // MARK: - State Queries

  /// Check if a model is loaded.
  bool get isLoaded {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final isLoadedFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_is_loaded');

      return isLoadedFn(_handle!) == RAC_TRUE;
    } catch (e) {
      _logger.debug('isLoaded check failed: $e');
      return false;
    }
  }

  /// Get the currently loaded model ID.
  String? get currentModelId => _loadedModelId;

  /// Check if streaming is supported.
  bool get supportsStreaming {
    if (_handle == null) return false;

    try {
      final lib = PlatformLoader.loadCommons();
      final supportsStreamingFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_supports_streaming');

      return supportsStreamingFn(_handle!) == RAC_TRUE;
    } catch (e) {
      return false;
    }
  }

  // MARK: - Model Lifecycle

  /// Load an STT model.
  ///
  /// [modelPath] - Full path to the model directory.
  /// [modelId] - Unique identifier for the model.
  /// [modelName] - Human-readable name.
  ///
  /// Throws on failure.
  Future<void> loadModel(
    String modelPath,
    String modelId,
    String modelName,
  ) async {
    final handle = getHandle();

    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = modelId.toNativeUtf8();
    final namePtr = modelName.toNativeUtf8();

    try {
      final lib = PlatformLoader.loadCommons();
      final loadModelFn = lib.lookupFunction<
          Int32 Function(
              RacHandle, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(RacHandle, Pointer<Utf8>, Pointer<Utf8>,
              Pointer<Utf8>)>('rac_stt_component_load_model');

      final result = loadModelFn(handle, pathPtr, idPtr, namePtr);

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to load STT model: ${RacResultCode.getMessage(result)}',
        );
      }

      _loadedModelId = modelId;
      _logger.info('STT model loaded: $modelId');
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  /// Unload the current model.
  void unload() {
    if (_handle == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final cleanupFn = lib.lookupFunction<Int32 Function(RacHandle),
          int Function(RacHandle)>('rac_stt_component_cleanup');

      cleanupFn(_handle!);
      _loadedModelId = null;
      _logger.info('STT model unloaded');
    } catch (e) {
      _logger.error('Failed to unload STT model: $e');
    }
  }

  // MARK: - Transcription

  /// Transcribe audio data.
  ///
  /// [audioData] - PCM16 audio data (WAV format expected with 16kHz sample rate).
  /// [sampleRate] - Sample rate of the audio (default: 16000 Hz for Whisper).
  ///
  /// Returns the transcription result.
  /// Runs in a background isolate to prevent UI blocking.
  Future<STTComponentResult> transcribe(
    Uint8List audioData, {
    int sampleRate = 16000,
  }) async {
    final handle = getHandle();

    if (!isLoaded) {
      throw StateError('No STT model loaded. Call loadModel() first.');
    }

    _logger.debug(
        'Transcribing ${audioData.length} bytes at $sampleRate Hz in background isolate...');

    // Run transcription in background isolate
    final result = await Isolate.run(() => _transcribeInIsolate(
          handle.address,
          audioData,
          sampleRate,
        ));

    _logger.info(
        'Transcription complete: ${result.text.length} chars, confidence: ${result.confidence}');

    return result;
  }

  /// Static helper to perform FFI transcription in isolate.
  /// Must be static/top-level for Isolate.run().
  static STTComponentResult _transcribeInIsolate(
    int handleAddress,
    Uint8List audioData,
    int sampleRate,
  ) {
    final lib = PlatformLoader.loadCommons();
    final handle = RacHandle.fromAddress(handleAddress);

    // Allocate native memory
    final dataPtr = calloc<Uint8>(audioData.length);
    final optionsPtr = calloc<RacSttOptionsStruct>();
    final resultPtr = calloc<RacSttResultStruct>();

    try {
      // Copy audio data
      final dataList = dataPtr.asTypedList(audioData.length);
      dataList.setAll(0, audioData);

      // Set up options with correct sample rate
      // Matches Swift's STTOptions setup
      final languagePtr = 'en'.toNativeUtf8();
      optionsPtr.ref.language = languagePtr;
      optionsPtr.ref.detectLanguage = RAC_FALSE;
      optionsPtr.ref.enablePunctuation = RAC_TRUE;
      optionsPtr.ref.enableDiarization = RAC_FALSE;
      optionsPtr.ref.maxSpeakers = 0;
      optionsPtr.ref.enableTimestamps = RAC_TRUE;
      optionsPtr.ref.audioFormat = racAudioFormatWav; // WAV format
      optionsPtr.ref.sampleRate = sampleRate;

      // Get transcribe function
      final transcribeFn = lib.lookupFunction<
          Int32 Function(
            RacHandle,
            Pointer<Void>,
            IntPtr,
            Pointer<RacSttOptionsStruct>,
            Pointer<RacSttResultStruct>,
          ),
          int Function(
            RacHandle,
            Pointer<Void>,
            int,
            Pointer<RacSttOptionsStruct>,
            Pointer<RacSttResultStruct>,
          )>('rac_stt_component_transcribe');

      final status = transcribeFn(
        handle,
        dataPtr.cast<Void>(),
        audioData.length,
        optionsPtr,
        resultPtr,
      );

      // Free the language string
      calloc.free(languagePtr);

      if (status != RAC_SUCCESS) {
        throw StateError(
          'STT transcription failed: ${RacResultCode.getMessage(status)}',
        );
      }

      // Extract result before freeing
      final result = resultPtr.ref;
      final text = result.text != nullptr ? result.text.toDartString() : '';
      final confidence = result.confidence;
      final durationMs = result.durationMs;
      final language =
          result.language != nullptr ? result.language.toDartString() : null;

      return STTComponentResult(
        text: text,
        confidence: confidence,
        durationMs: durationMs,
        language: language,
      );
    } finally {
      calloc.free(dataPtr);
      calloc.free(optionsPtr);
      calloc.free(resultPtr);
    }
  }

  /// Transcribe with streaming.
  ///
  /// Returns a stream of partial transcriptions.
  Stream<STTStreamResult> transcribeStream(Stream<Uint8List> audioStream) {
    // Create async generator for streaming transcription
    return _transcribeStreamImpl(audioStream);
  }

  Stream<STTStreamResult> _transcribeStreamImpl(
    Stream<Uint8List> audioStream,
  ) async* {
    // Accumulate audio and emit partial results
    final buffer = <int>[];

    await for (final chunk in audioStream) {
      buffer.addAll(chunk);

      // Process every ~0.5 seconds of audio (8000 samples at 16kHz)
      if (buffer.length >= 8000) {
        try {
          final result = await transcribe(Uint8List.fromList(buffer));
          yield STTStreamResult(
            text: result.text,
            isFinal: false,
            confidence: result.confidence,
          );
        } catch (e) {
          _logger.debug('Partial transcription failed: $e');
        }
      }
    }

    // Final transcription with all audio
    if (buffer.isNotEmpty) {
      try {
        final result = await transcribe(Uint8List.fromList(buffer));
        yield STTStreamResult(
          text: result.text,
          isFinal: true,
          confidence: result.confidence,
        );
      } catch (e) {
        _logger.error('Final transcription failed: $e');
      }
    }
  }

  // MARK: - Cleanup

  /// Destroy the component and release resources.
  void destroy() {
    if (_handle != null) {
      try {
        final lib = PlatformLoader.loadCommons();
        final destroyFn = lib.lookupFunction<Void Function(RacHandle),
            void Function(RacHandle)>('rac_stt_component_destroy');

        destroyFn(_handle!);
        _handle = null;
        _loadedModelId = null;
        _logger.debug('STT component destroyed');
      } catch (e) {
        _logger.error('Failed to destroy STT component: $e');
      }
    }
  }
}

/// Result from STT transcription.
class STTComponentResult {
  final String text;
  final double confidence;
  final int durationMs;
  final String? language;

  const STTComponentResult({
    required this.text,
    required this.confidence,
    required this.durationMs,
    this.language,
  });
}

/// Streaming result from STT transcription.
class STTStreamResult {
  final String text;
  final bool isFinal;
  final double confidence;

  const STTStreamResult({
    required this.text,
    required this.isFinal,
    required this.confidence,
  });
}

// =============================================================================
// FFI Structs
// =============================================================================

/// Audio format enum (matches rac_audio_format_enum_t)
const int racAudioFormatPcm = 0;
const int racAudioFormatWav = 1;
const int racAudioFormatMp3 = 2;
const int racAudioFormatOpus = 3;
const int racAudioFormatAac = 4;
const int racAudioFormatFlac = 5;

/// FFI struct for STT options (matches rac_stt_options_t)
final class RacSttOptionsStruct extends Struct {
  /// Language code (e.g., "en")
  external Pointer<Utf8> language;

  /// Whether to auto-detect language
  @Int32()
  external int detectLanguage;

  /// Whether to add punctuation
  @Int32()
  external int enablePunctuation;

  /// Whether to enable speaker diarization
  @Int32()
  external int enableDiarization;

  /// Maximum number of speakers for diarization
  @Int32()
  external int maxSpeakers;

  /// Whether to include word timestamps
  @Int32()
  external int enableTimestamps;

  /// Audio format of input data
  @Int32()
  external int audioFormat;

  /// Sample rate of input audio (default: 16000 Hz)
  @Int32()
  external int sampleRate;
}

/// FFI struct for STT result (matches rac_stt_result_t)
final class RacSttResultStruct extends Struct {
  external Pointer<Utf8> text;

  @Double()
  external double confidence;

  @Int32()
  external int durationMs;

  external Pointer<Utf8> language;
}
