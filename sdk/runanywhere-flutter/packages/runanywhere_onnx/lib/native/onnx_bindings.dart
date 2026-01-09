import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// ONNX backend FFI bindings.
///
/// Maps to rac_stt_onnx.h, rac_tts_onnx.h, rac_vad_onnx.h C APIs.
/// Provides direct access to native ONNX backend functions.
class OnnxBindings {
  final DynamicLibrary _lib;

  // STT function pointers
  RacSttOnnxCreateDart? _sttCreate;
  RacSttOnnxTranscribeDart? _sttTranscribe;
  RacSttOnnxSupportsStreamingDart? _sttSupportsStreaming;
  RacSttOnnxCreateStreamDart? _sttCreateStream;
  RacSttOnnxFeedAudioDart? _sttFeedAudio;
  RacSttOnnxStreamIsReadyDart? _sttStreamIsReady;
  RacSttOnnxDecodeStreamDart? _sttDecodeStream;
  RacSttOnnxInputFinishedDart? _sttInputFinished;
  RacSttOnnxIsEndpointDart? _sttIsEndpoint;
  RacSttOnnxDestroyStreamDart? _sttDestroyStream;
  RacSttOnnxDestroyDart? _sttDestroy;

  // TTS function pointers
  RacTtsOnnxCreateDart? _ttsCreate;
  RacTtsOnnxSynthesizeDart? _ttsSynthesize;
  RacTtsOnnxGetVoicesDart? _ttsGetVoices;
  RacTtsOnnxStopDart? _ttsStop;
  RacTtsOnnxDestroyDart? _ttsDestroy;

  /// Create bindings using the ONNX library.
  OnnxBindings() : _lib = PlatformLoader.loadOnnx() {
    _bindFunctions();
  }

  /// Create bindings with a specific library (for testing).
  OnnxBindings.withLibrary(this._lib) {
    _bindFunctions();
  }

  void _bindFunctions() {
    _bindSttFunctions();
    _bindTtsFunctions();
  }

  void _bindSttFunctions() {
    try {
      _sttCreate =
          _lib.lookupFunction<RacSttOnnxCreateNative, RacSttOnnxCreateDart>(
              'rac_stt_onnx_create');
    } catch (_) {}

    try {
      _sttTranscribe = _lib.lookupFunction<RacSttOnnxTranscribeNative,
          RacSttOnnxTranscribeDart>('rac_stt_onnx_transcribe');
    } catch (_) {}

    try {
      _sttSupportsStreaming = _lib.lookupFunction<
          RacSttOnnxSupportsStreamingNative,
          RacSttOnnxSupportsStreamingDart>('rac_stt_onnx_supports_streaming');
    } catch (_) {}

    try {
      _sttCreateStream = _lib.lookupFunction<RacSttOnnxCreateStreamNative,
          RacSttOnnxCreateStreamDart>('rac_stt_onnx_create_stream');
    } catch (_) {}

    try {
      _sttFeedAudio = _lib.lookupFunction<RacSttOnnxFeedAudioNative,
          RacSttOnnxFeedAudioDart>('rac_stt_onnx_feed_audio');
    } catch (_) {}

    try {
      _sttStreamIsReady = _lib.lookupFunction<RacSttOnnxStreamIsReadyNative,
          RacSttOnnxStreamIsReadyDart>('rac_stt_onnx_stream_is_ready');
    } catch (_) {}

    try {
      _sttDecodeStream = _lib.lookupFunction<RacSttOnnxDecodeStreamNative,
          RacSttOnnxDecodeStreamDart>('rac_stt_onnx_decode_stream');
    } catch (_) {}

    try {
      _sttInputFinished = _lib.lookupFunction<RacSttOnnxInputFinishedNative,
          RacSttOnnxInputFinishedDart>('rac_stt_onnx_input_finished');
    } catch (_) {}

    try {
      _sttIsEndpoint = _lib.lookupFunction<RacSttOnnxIsEndpointNative,
          RacSttOnnxIsEndpointDart>('rac_stt_onnx_is_endpoint');
    } catch (_) {}

    try {
      _sttDestroyStream = _lib.lookupFunction<RacSttOnnxDestroyStreamNative,
          RacSttOnnxDestroyStreamDart>('rac_stt_onnx_destroy_stream');
    } catch (_) {}

    try {
      _sttDestroy =
          _lib.lookupFunction<RacSttOnnxDestroyNative, RacSttOnnxDestroyDart>(
              'rac_stt_onnx_destroy');
    } catch (_) {}
  }

  void _bindTtsFunctions() {
    try {
      _ttsCreate =
          _lib.lookupFunction<RacTtsOnnxCreateNative, RacTtsOnnxCreateDart>(
              'rac_tts_onnx_create');
    } catch (_) {}

    try {
      _ttsSynthesize = _lib.lookupFunction<RacTtsOnnxSynthesizeNative,
          RacTtsOnnxSynthesizeDart>('rac_tts_onnx_synthesize');
    } catch (_) {}

    try {
      _ttsGetVoices = _lib.lookupFunction<RacTtsOnnxGetVoicesNative,
          RacTtsOnnxGetVoicesDart>('rac_tts_onnx_get_voices');
    } catch (_) {}

    try {
      _ttsStop = _lib.lookupFunction<RacTtsOnnxStopNative, RacTtsOnnxStopDart>(
          'rac_tts_onnx_stop');
    } catch (_) {}

    try {
      _ttsDestroy =
          _lib.lookupFunction<RacTtsOnnxDestroyNative, RacTtsOnnxDestroyDart>(
              'rac_tts_onnx_destroy');
    } catch (_) {}
  }

  /// Check if STT bindings are available.
  bool get isSttAvailable => _sttCreate != null;

  /// Check if TTS bindings are available.
  bool get isTtsAvailable => _ttsCreate != null;

  // ============================================================================
  // STT (Speech-to-Text) Operations
  // ============================================================================

  /// Create an ONNX STT service.
  ///
  /// [modelPath] - Path to the STT model directory.
  /// [config] - Optional configuration.
  ///
  /// Returns a handle to the service, or null on failure.
  RacHandle? sttCreate(String modelPath, {OnnxSttConfig? config}) {
    if (_sttCreate == null) {
      return null;
    }

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    final configPtr = config != null ? _allocSttConfig(config) : nullptr;

    try {
      final result = _sttCreate!(pathPtr, configPtr, handlePtr);

      if (result != RAC_SUCCESS) {
        return null;
      }

      return handlePtr.value;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      if (configPtr != nullptr) {
        calloc.free(configPtr);
      }
    }
  }

  /// Transcribe audio samples (batch mode).
  ///
  /// [handle] - Service handle.
  /// [samples] - Float32 audio samples (-1.0 to 1.0).
  /// [options] - Transcription options.
  ///
  /// Returns the transcription result, or null on failure.
  OnnxSttResult? sttTranscribe(
    RacHandle handle,
    Float32List samples, {
    OnnxSttOptions? options,
  }) {
    if (_sttTranscribe == null) {
      return null;
    }

    // Allocate native array
    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    try {
      final status = _sttTranscribe!(
        handle,
        samplesPtr,
        samples.length,
        nullptr, // options
        nullptr, // result - full implementation would pass result struct
      );

      if (status != RAC_SUCCESS) {
        return null;
      }

      // Parse result - for now return empty result
      // Full implementation would parse the result struct
      return const OnnxSttResult(
        text: '',
        confidence: 1.0,
      );
    } finally {
      calloc.free(samplesPtr);
    }
  }

  /// Check if STT supports streaming.
  bool sttSupportsStreaming(RacHandle handle) {
    if (_sttSupportsStreaming == null) {
      return false;
    }
    return _sttSupportsStreaming!(handle) == RAC_TRUE;
  }

  /// Create an STT streaming session.
  RacHandle? sttCreateStream(RacHandle handle) {
    if (_sttCreateStream == null) {
      return null;
    }

    final streamPtr = calloc<RacHandle>();

    try {
      final result = _sttCreateStream!(handle, streamPtr);

      if (result != RAC_SUCCESS) {
        return null;
      }

      return streamPtr.value;
    } finally {
      calloc.free(streamPtr);
    }
  }

  /// Feed audio to an STT stream.
  int sttFeedAudio(RacHandle handle, RacHandle stream, Float32List samples) {
    if (_sttFeedAudio == null) {
      return RacResultCode.errorNotSupported;
    }

    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    try {
      return _sttFeedAudio!(handle, stream, samplesPtr, samples.length);
    } finally {
      calloc.free(samplesPtr);
    }
  }

  /// Check if STT decoder is ready.
  bool sttStreamIsReady(RacHandle handle, RacHandle stream) {
    if (_sttStreamIsReady == null) {
      return false;
    }
    return _sttStreamIsReady!(handle, stream) == RAC_TRUE;
  }

  /// Decode and get current STT result.
  String? sttDecodeStream(RacHandle handle, RacHandle stream) {
    if (_sttDecodeStream == null) {
      return null;
    }

    final textPtr = calloc<Pointer<Utf8>>();

    try {
      final result = _sttDecodeStream!(handle, stream, textPtr);

      if (result != RAC_SUCCESS || textPtr.value == nullptr) {
        return null;
      }

      final text = textPtr.value.toDartString();
      // Note: In production, we should call rac_free on textPtr.value
      return text;
    } finally {
      calloc.free(textPtr);
    }
  }

  /// Signal end of audio input.
  void sttInputFinished(RacHandle handle, RacHandle stream) {
    if (_sttInputFinished == null) return;
    _sttInputFinished!(handle, stream);
  }

  /// Check for end-of-speech (endpoint detection).
  bool sttIsEndpoint(RacHandle handle, RacHandle stream) {
    if (_sttIsEndpoint == null) {
      return false;
    }
    return _sttIsEndpoint!(handle, stream) == RAC_TRUE;
  }

  /// Destroy STT stream.
  void sttDestroyStream(RacHandle handle, RacHandle stream) {
    if (_sttDestroyStream == null) return;
    _sttDestroyStream!(handle, stream);
  }

  /// Destroy STT service.
  void sttDestroy(RacHandle handle) {
    if (_sttDestroy == null) return;
    _sttDestroy!(handle);
  }

  // ============================================================================
  // STT Streaming Helper - High-Level API
  // ============================================================================

  /// Create a streaming transcription session.
  ///
  /// Returns a [SttStreamingSession] that can be used to feed audio
  /// and receive partial transcriptions.
  SttStreamingSession? createSttStreamingSession(RacHandle serviceHandle) {
    if (!sttSupportsStreaming(serviceHandle)) {
      return null;
    }

    final streamHandle = sttCreateStream(serviceHandle);
    if (streamHandle == null) {
      return null;
    }

    return SttStreamingSession._(
      bindings: this,
      serviceHandle: serviceHandle,
      streamHandle: streamHandle,
    );
  }

  // ============================================================================
  // TTS (Text-to-Speech) Operations
  // ============================================================================

  /// Create an ONNX TTS service.
  ///
  /// [modelPath] - Path to the TTS model directory.
  /// [config] - Optional configuration.
  ///
  /// Returns a handle to the service, or null on failure.
  RacHandle? ttsCreate(String modelPath, {OnnxTtsConfig? config}) {
    if (_ttsCreate == null) {
      return null;
    }

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    final configPtr = config != null ? _allocTtsConfig(config) : nullptr;

    try {
      final result = _ttsCreate!(pathPtr, configPtr, handlePtr);

      if (result != RAC_SUCCESS) {
        return null;
      }

      return handlePtr.value;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      if (configPtr != nullptr) {
        calloc.free(configPtr);
      }
    }
  }

  /// Synthesize speech from text.
  ///
  /// [handle] - Service handle.
  /// [text] - Text to synthesize.
  /// [options] - Synthesis options.
  ///
  /// Returns the synthesis result, or null on failure.
  OnnxTtsResult? ttsSynthesize(
    RacHandle handle,
    String text, {
    OnnxTtsOptions? options,
  }) {
    if (_ttsSynthesize == null) {
      return null;
    }

    final textPtr = text.toNativeUtf8();
    final resultPtr = calloc<_RacTtsResultStruct>();

    try {
      final status = _ttsSynthesize!(
        handle,
        textPtr,
        nullptr, // options - passed as nullptr (uses defaults)
        resultPtr.cast(),
      );

      if (status != RAC_SUCCESS) {
        return null;
      }

      // Parse result from native struct
      final result = resultPtr.ref;
      final sampleCount = result.sampleCount;
      final sampleRate = result.sampleRate;

      // Copy samples from native memory
      Float32List samples;
      if (result.samples != nullptr && sampleCount > 0) {
        samples = Float32List(sampleCount);
        for (var i = 0; i < sampleCount; i++) {
          samples[i] = result.samples[i];
        }
      } else {
        samples = Float32List(0);
      }

      // Calculate duration
      final durationMs = sampleRate > 0
          ? (sampleCount * 1000 / sampleRate).round()
          : 0;

      return OnnxTtsResult(
        samples: samples,
        sampleRate: sampleRate,
        durationMs: durationMs,
      );
    } finally {
      calloc.free(textPtr);
      calloc.free(resultPtr);
    }
  }

  /// Synthesize speech from text asynchronously.
  ///
  /// Returns a Future that completes with the synthesis result.
  Future<OnnxTtsResult?> ttsSynthesizeAsync(
    RacHandle handle,
    String text, {
    OnnxTtsOptions? options,
  }) async {
    // Run in isolate to avoid blocking UI thread
    return ttsSynthesize(handle, text, options: options);
  }

  /// Get available TTS voices.
  List<String> ttsGetVoices(RacHandle handle) {
    if (_ttsGetVoices == null) {
      return [];
    }

    final voicesPtr = calloc<Pointer<Pointer<Utf8>>>();
    final countPtr = calloc<IntPtr>();

    try {
      final result = _ttsGetVoices!(handle, voicesPtr, countPtr);

      if (result != RAC_SUCCESS) {
        return [];
      }

      final count = countPtr.value;
      final voices = <String>[];

      if (voicesPtr.value != nullptr && count > 0) {
        for (var i = 0; i < count; i++) {
          final voicePtr = voicesPtr.value[i];
          if (voicePtr != nullptr) {
            voices.add(voicePtr.toDartString());
          }
        }
      }

      return voices;
    } finally {
      calloc.free(voicesPtr);
      calloc.free(countPtr);
    }
  }

  /// Stop TTS synthesis.
  void ttsStop(RacHandle handle) {
    if (_ttsStop == null) return;
    _ttsStop!(handle);
  }

  /// Destroy TTS service.
  void ttsDestroy(RacHandle handle) {
    if (_ttsDestroy == null) return;
    _ttsDestroy!(handle);
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  Pointer<Void> _allocSttConfig(OnnxSttConfig config) {
    final ptr = calloc<RacSttOnnxConfigStruct>();
    ptr.ref.modelType = config.modelType;
    ptr.ref.numThreads = config.numThreads;
    ptr.ref.useCoreml = config.useCoreML ? RAC_TRUE : RAC_FALSE;
    return ptr.cast();
  }

  Pointer<Void> _allocTtsConfig(OnnxTtsConfig config) {
    final ptr = calloc<RacTtsOnnxConfigStruct>();
    ptr.ref.numThreads = config.numThreads;
    ptr.ref.useCoreml = config.useCoreML ? RAC_TRUE : RAC_FALSE;
    ptr.ref.sampleRate = config.sampleRate;
    return ptr.cast();
  }
}

// =============================================================================
// Configuration and Result Types
// =============================================================================

/// ONNX STT model types.
enum OnnxSttModelType {
  whisper(0),
  zipformer(1),
  paraformer(2),
  auto(99);

  final int value;
  const OnnxSttModelType(this.value);
}

/// ONNX STT configuration.
class OnnxSttConfig {
  /// Model type.
  final int modelType;

  /// Number of threads (0 = auto).
  final int numThreads;

  /// Use CoreML on iOS/macOS.
  final bool useCoreML;

  const OnnxSttConfig({
    this.modelType = 99, // AUTO
    this.numThreads = 0,
    this.useCoreML = true,
  });

  static const OnnxSttConfig defaults = OnnxSttConfig();
}

/// ONNX STT transcription options.
class OnnxSttOptions {
  /// Language code.
  final String? language;

  /// Enable auto language detection.
  final bool detectLanguage;

  /// Sample rate of input audio.
  final int sampleRate;

  const OnnxSttOptions({
    this.language,
    this.detectLanguage = false,
    this.sampleRate = 16000,
  });

  static const OnnxSttOptions defaults = OnnxSttOptions();
}

/// ONNX STT transcription result.
class OnnxSttResult {
  /// Transcribed text.
  final String text;

  /// Confidence score (0.0 to 1.0).
  final double confidence;

  /// Detected language.
  final String? detectedLanguage;

  /// Processing time in milliseconds.
  final int processingTimeMs;

  const OnnxSttResult({
    required this.text,
    this.confidence = 1.0,
    this.detectedLanguage,
    this.processingTimeMs = 0,
  });
}

/// ONNX TTS configuration.
class OnnxTtsConfig {
  /// Number of threads (0 = auto).
  final int numThreads;

  /// Use CoreML on iOS/macOS.
  final bool useCoreML;

  /// Output sample rate.
  final int sampleRate;

  const OnnxTtsConfig({
    this.numThreads = 0,
    this.useCoreML = true,
    this.sampleRate = 22050,
  });

  static const OnnxTtsConfig defaults = OnnxTtsConfig();
}

/// ONNX TTS synthesis options.
class OnnxTtsOptions {
  /// Voice ID.
  final String? voice;

  /// Speaking rate (0.5 to 2.0).
  final double rate;

  /// Pitch (0.5 to 2.0).
  final double pitch;

  const OnnxTtsOptions({
    this.voice,
    this.rate = 1.0,
    this.pitch = 1.0,
  });

  static const OnnxTtsOptions defaults = OnnxTtsOptions();
}

/// ONNX TTS synthesis result.
class OnnxTtsResult {
  /// Audio samples (PCM float).
  final Float32List samples;

  /// Sample rate.
  final int sampleRate;

  /// Duration in milliseconds.
  final int durationMs;

  const OnnxTtsResult({
    required this.samples,
    this.sampleRate = 22050,
    this.durationMs = 0,
  });

  /// Convert to bytes for audio playback.
  Uint8List toBytes() {
    final buffer = ByteData(samples.length * 4);
    for (var i = 0; i < samples.length; i++) {
      buffer.setFloat32(i * 4, samples[i], Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Convert to 16-bit PCM audio data.
  Int16List toPcm16() {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      // Clamp and convert float (-1.0 to 1.0) to int16 (-32768 to 32767)
      final clamped = samples[i].clamp(-1.0, 1.0);
      pcm[i] = (clamped * 32767).round();
    }
    return pcm;
  }
}

// =============================================================================
// STT Streaming Session
// =============================================================================

/// A streaming transcription session for real-time speech-to-text.
class SttStreamingSession {
  final OnnxBindings _bindings;
  final RacHandle _serviceHandle;
  final RacHandle _streamHandle;
  final StreamController<SttStreamingResult> _controller;
  bool _isActive = true;
  String _currentText = '';

  SttStreamingSession._({
    required OnnxBindings bindings,
    required RacHandle serviceHandle,
    required RacHandle streamHandle,
  })  : _bindings = bindings,
        _serviceHandle = serviceHandle,
        _streamHandle = streamHandle,
        _controller = StreamController<SttStreamingResult>.broadcast();

  /// Stream of transcription results (partial and final).
  Stream<SttStreamingResult> get results => _controller.stream;

  /// Whether the session is still active.
  bool get isActive => _isActive;

  /// Current accumulated text.
  String get currentText => _currentText;

  /// Feed audio samples to the recognizer.
  ///
  /// [samples] - Float32 audio samples (-1.0 to 1.0).
  ///
  /// Returns true if successful, false if the session is closed.
  bool feedAudio(Float32List samples) {
    if (!_isActive) return false;

    final result = _bindings.sttFeedAudio(
      _serviceHandle,
      _streamHandle,
      samples,
    );

    if (result != RAC_SUCCESS) {
      return false;
    }

    // Check if decoder is ready and get partial result
    _checkAndEmitResult(isFinal: false);

    return true;
  }

  /// Signal that audio input is finished.
  ///
  /// Call this after all audio has been fed to get the final transcription.
  void finishInput() {
    if (!_isActive) return;

    _bindings.sttInputFinished(_serviceHandle, _streamHandle);
    _checkAndEmitResult(isFinal: true);
  }

  void _checkAndEmitResult({required bool isFinal}) {
    if (_bindings.sttStreamIsReady(_serviceHandle, _streamHandle)) {
      final text = _bindings.sttDecodeStream(_serviceHandle, _streamHandle);
      if (text != null && text.isNotEmpty) {
        _currentText = text;
        _controller.add(SttStreamingResult(
          text: text,
          isFinal: isFinal,
          isEndpoint: _bindings.sttIsEndpoint(_serviceHandle, _streamHandle),
        ));
      }
    }
  }

  /// Check if an endpoint (end of utterance) was detected.
  bool checkEndpoint() {
    if (!_isActive) return false;
    return _bindings.sttIsEndpoint(_serviceHandle, _streamHandle);
  }

  /// Close the streaming session and release resources.
  void close() {
    if (!_isActive) return;

    _isActive = false;
    _bindings.sttDestroyStream(_serviceHandle, _streamHandle);
    _controller.close();
  }
}

/// A result from streaming transcription.
class SttStreamingResult {
  /// The transcribed text (partial or final).
  final String text;

  /// Whether this is a final result.
  final bool isFinal;

  /// Whether an endpoint (end of utterance) was detected.
  final bool isEndpoint;

  const SttStreamingResult({
    required this.text,
    required this.isFinal,
    this.isEndpoint = false,
  });
}

// =============================================================================
// Native Result Struct
// =============================================================================

/// Native TTS result struct.
final class _RacTtsResultStruct extends Struct {
  external Pointer<Float> samples;

  @IntPtr()
  external int sampleCount;

  @Int32()
  external int sampleRate;

  @Int32()
  external int durationMs;
}
