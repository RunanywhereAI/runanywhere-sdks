import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Wrapper around the RunAnywhere native C API.
///
/// This class provides a Dart-friendly interface to the native backend,
/// handling memory management and type conversions.
///
/// Usage:
/// ```dart
/// final backend = NativeBackend();
/// backend.create('onnx');
/// backend.loadSttModel('/path/to/model', modelType: 'whisper');
/// final result = backend.transcribe(audioSamples);
/// backend.dispose();
/// ```
class NativeBackend {
  final DynamicLibrary _lib;
  RaBackendHandle? _handle;
  String? _backendName;

  // Cached function lookups - Backend lifecycle
  late final RaGetAvailableBackendsDart _getAvailableBackends;
  late final RaCreateBackendDart _createBackend;
  late final RaInitializeDart _initialize;
  late final RaIsInitializedDart _isInitialized;
  late final RaDestroyDart _destroy;
  late final RaGetBackendInfoDart _getBackendInfo;
  late final RaSupportsCapabilityDart _supportsCapability;
  late final RaGetDeviceDart _getDevice;
  late final RaGetMemoryUsageDart _getMemoryUsage;

  // Memory management
  late final RaFreeStringDart _freeString;
  late final RaFreeAudioDart _freeAudio;
  late final RaFreeEmbeddingDart _freeEmbedding;

  // Utility
  late final RaGetLastErrorDart _getLastError;
  late final RaGetVersionDart _getVersion;
  late final RaExtractArchiveDart _extractArchive;

  // STT functions
  late final RaSttLoadModelDart _sttLoadModel;
  late final RaSttIsModelLoadedDart _sttIsModelLoaded;
  late final RaSttUnloadModelDart _sttUnloadModel;
  late final RaSttTranscribeDart _sttTranscribe;
  late final RaSttSupportsStreamingDart _sttSupportsStreaming;
  late final RaSttCreateStreamDart _sttCreateStream;
  late final RaSttFeedAudioDart _sttFeedAudio;
  late final RaSttIsReadyDart _sttIsReady;
  late final RaSttDecodeDart _sttDecode;
  late final RaSttIsEndpointDart _sttIsEndpoint;
  late final RaSttInputFinishedDart _sttInputFinished;
  late final RaSttResetStreamDart _sttResetStream;
  late final RaSttDestroyStreamDart _sttDestroyStream;
  late final RaSttCancelDart _sttCancel;

  // TTS functions
  late final RaTtsLoadModelDart _ttsLoadModel;
  late final RaTtsIsModelLoadedDart _ttsIsModelLoaded;
  late final RaTtsUnloadModelDart _ttsUnloadModel;
  late final RaTtsSynthesizeDart _ttsSynthesize;
  late final RaTtsSupportsStreamingDart _ttsSupportsStreaming;
  late final RaTtsGetVoicesDart _ttsGetVoices;
  late final RaTtsCancelDart _ttsCancel;

  // LLM functions
  late final RaTextLoadModelDart _textLoadModel;
  late final RaTextIsModelLoadedDart _textIsModelLoaded;
  late final RaTextUnloadModelDart _textUnloadModel;
  late final RaTextGenerateDart _textGenerate;
  late final RaTextCancelDart _textCancel;

  // VAD functions
  late final RaVadLoadModelDart _vadLoadModel;
  late final RaVadIsModelLoadedDart _vadIsModelLoaded;
  late final RaVadUnloadModelDart _vadUnloadModel;
  late final RaVadProcessDart _vadProcess;
  late final RaVadCreateStreamDart _vadCreateStream;
  late final RaVadDestroyStreamDart _vadDestroyStream;
  late final RaVadResetDart _vadReset;

  // Embeddings functions
  late final RaEmbedLoadModelDart _embedLoadModel;
  late final RaEmbedIsModelLoadedDart _embedIsModelLoaded;
  late final RaEmbedTextDart _embedText;
  late final RaEmbedGetDimensionsDart _embedGetDimensions;

  NativeBackend._(this._lib) {
    _bindFunctions();
  }

  /// Create a new native backend instance.
  ///
  /// This loads the native library for the current platform.
  /// Throws if the library cannot be loaded.
  factory NativeBackend() {
    final lib = PlatformLoader.load();
    return NativeBackend._(lib);
  }

  /// Try to create a native backend, returning null if it fails.
  static NativeBackend? tryCreate() {
    try {
      return NativeBackend();
    } catch (_) {
      return null;
    }
  }

  void _bindFunctions() {
    // Backend lifecycle
    _getAvailableBackends = _lib.lookupFunction<RaGetAvailableBackendsNative,
        RaGetAvailableBackendsDart>('ra_get_available_backends');
    _createBackend =
        _lib.lookupFunction<RaCreateBackendNative, RaCreateBackendDart>(
            'ra_create_backend');
    _initialize = _lib
        .lookupFunction<RaInitializeNative, RaInitializeDart>('ra_initialize');
    _isInitialized =
        _lib.lookupFunction<RaIsInitializedNative, RaIsInitializedDart>(
            'ra_is_initialized');
    _destroy =
        _lib.lookupFunction<RaDestroyNative, RaDestroyDart>('ra_destroy');
    _getBackendInfo =
        _lib.lookupFunction<RaGetBackendInfoNative, RaGetBackendInfoDart>(
            'ra_get_backend_info');
    _supportsCapability = _lib.lookupFunction<RaSupportsCapabilityNative,
        RaSupportsCapabilityDart>('ra_supports_capability');
    _getDevice = _lib
        .lookupFunction<RaGetDeviceNative, RaGetDeviceDart>('ra_get_device');
    _getMemoryUsage =
        _lib.lookupFunction<RaGetMemoryUsageNative, RaGetMemoryUsageDart>(
            'ra_get_memory_usage');

    // Memory management
    _freeString = _lib
        .lookupFunction<RaFreeStringNative, RaFreeStringDart>('ra_free_string');
    _freeAudio = _lib
        .lookupFunction<RaFreeAudioNative, RaFreeAudioDart>('ra_free_audio');
    _freeEmbedding =
        _lib.lookupFunction<RaFreeEmbeddingNative, RaFreeEmbeddingDart>(
            'ra_free_embedding');

    // Utility
    _getLastError =
        _lib.lookupFunction<RaGetLastErrorNative, RaGetLastErrorDart>(
            'ra_get_last_error');
    _getVersion = _lib
        .lookupFunction<RaGetVersionNative, RaGetVersionDart>('ra_get_version');
    _extractArchive =
        _lib.lookupFunction<RaExtractArchiveNative, RaExtractArchiveDart>(
            'ra_extract_archive');

    // STT
    _sttLoadModel =
        _lib.lookupFunction<RaSttLoadModelNative, RaSttLoadModelDart>(
            'ra_stt_load_model');
    _sttIsModelLoaded =
        _lib.lookupFunction<RaSttIsModelLoadedNative, RaSttIsModelLoadedDart>(
            'ra_stt_is_model_loaded');
    _sttUnloadModel =
        _lib.lookupFunction<RaSttUnloadModelNative, RaSttUnloadModelDart>(
            'ra_stt_unload_model');
    _sttTranscribe =
        _lib.lookupFunction<RaSttTranscribeNative, RaSttTranscribeDart>(
            'ra_stt_transcribe');
    _sttSupportsStreaming = _lib.lookupFunction<RaSttSupportsStreamingNative,
        RaSttSupportsStreamingDart>('ra_stt_supports_streaming');
    _sttCreateStream =
        _lib.lookupFunction<RaSttCreateStreamNative, RaSttCreateStreamDart>(
            'ra_stt_create_stream');
    _sttFeedAudio =
        _lib.lookupFunction<RaSttFeedAudioNative, RaSttFeedAudioDart>(
            'ra_stt_feed_audio');
    _sttIsReady = _lib.lookupFunction<RaSttIsReadyNative, RaSttIsReadyDart>(
        'ra_stt_is_ready');
    _sttDecode = _lib
        .lookupFunction<RaSttDecodeNative, RaSttDecodeDart>('ra_stt_decode');
    _sttIsEndpoint =
        _lib.lookupFunction<RaSttIsEndpointNative, RaSttIsEndpointDart>(
            'ra_stt_is_endpoint');
    _sttInputFinished =
        _lib.lookupFunction<RaSttInputFinishedNative, RaSttInputFinishedDart>(
            'ra_stt_input_finished');
    _sttResetStream =
        _lib.lookupFunction<RaSttResetStreamNative, RaSttResetStreamDart>(
            'ra_stt_reset_stream');
    _sttDestroyStream =
        _lib.lookupFunction<RaSttDestroyStreamNative, RaSttDestroyStreamDart>(
            'ra_stt_destroy_stream');
    _sttCancel = _lib
        .lookupFunction<RaSttCancelNative, RaSttCancelDart>('ra_stt_cancel');

    // TTS
    _ttsLoadModel =
        _lib.lookupFunction<RaTtsLoadModelNative, RaTtsLoadModelDart>(
            'ra_tts_load_model');
    _ttsIsModelLoaded =
        _lib.lookupFunction<RaTtsIsModelLoadedNative, RaTtsIsModelLoadedDart>(
            'ra_tts_is_model_loaded');
    _ttsUnloadModel =
        _lib.lookupFunction<RaTtsUnloadModelNative, RaTtsUnloadModelDart>(
            'ra_tts_unload_model');
    _ttsSynthesize =
        _lib.lookupFunction<RaTtsSynthesizeNative, RaTtsSynthesizeDart>(
            'ra_tts_synthesize');
    _ttsSupportsStreaming = _lib.lookupFunction<RaTtsSupportsStreamingNative,
        RaTtsSupportsStreamingDart>('ra_tts_supports_streaming');
    _ttsGetVoices =
        _lib.lookupFunction<RaTtsGetVoicesNative, RaTtsGetVoicesDart>(
            'ra_tts_get_voices');
    _ttsCancel = _lib
        .lookupFunction<RaTtsCancelNative, RaTtsCancelDart>('ra_tts_cancel');

    // LLM
    _textLoadModel =
        _lib.lookupFunction<RaTextLoadModelNative, RaTextLoadModelDart>(
            'ra_text_load_model');
    _textIsModelLoaded =
        _lib.lookupFunction<RaTextIsModelLoadedNative, RaTextIsModelLoadedDart>(
            'ra_text_is_model_loaded');
    _textUnloadModel =
        _lib.lookupFunction<RaTextUnloadModelNative, RaTextUnloadModelDart>(
            'ra_text_unload_model');
    _textGenerate =
        _lib.lookupFunction<RaTextGenerateNative, RaTextGenerateDart>(
            'ra_text_generate');
    _textCancel = _lib
        .lookupFunction<RaTextCancelNative, RaTextCancelDart>('ra_text_cancel');

    // VAD
    _vadLoadModel =
        _lib.lookupFunction<RaVadLoadModelNative, RaVadLoadModelDart>(
            'ra_vad_load_model');
    _vadIsModelLoaded =
        _lib.lookupFunction<RaVadIsModelLoadedNative, RaVadIsModelLoadedDart>(
            'ra_vad_is_model_loaded');
    _vadUnloadModel =
        _lib.lookupFunction<RaVadUnloadModelNative, RaVadUnloadModelDart>(
            'ra_vad_unload_model');
    _vadProcess = _lib
        .lookupFunction<RaVadProcessNative, RaVadProcessDart>('ra_vad_process');
    _vadCreateStream =
        _lib.lookupFunction<RaVadCreateStreamNative, RaVadCreateStreamDart>(
            'ra_vad_create_stream');
    _vadDestroyStream =
        _lib.lookupFunction<RaVadDestroyStreamNative, RaVadDestroyStreamDart>(
            'ra_vad_destroy_stream');
    _vadReset =
        _lib.lookupFunction<RaVadResetNative, RaVadResetDart>('ra_vad_reset');

    // Embeddings
    _embedLoadModel =
        _lib.lookupFunction<RaEmbedLoadModelNative, RaEmbedLoadModelDart>(
            'ra_embed_load_model');
    _embedIsModelLoaded = _lib.lookupFunction<RaEmbedIsModelLoadedNative,
        RaEmbedIsModelLoadedDart>('ra_embed_is_model_loaded');
    _embedText = _lib
        .lookupFunction<RaEmbedTextNative, RaEmbedTextDart>('ra_embed_text');
    _embedGetDimensions = _lib.lookupFunction<RaEmbedGetDimensionsNative,
        RaEmbedGetDimensionsDart>('ra_embed_get_dimensions');
  }

  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  /// Get list of available backend names.
  List<String> getAvailableBackends() {
    final countPtr = calloc<Int32>();

    try {
      final backendsPtr = _getAvailableBackends(countPtr);
      final count = countPtr.value;

      if (backendsPtr == nullptr || count == 0) {
        return [];
      }

      final backends = <String>[];
      for (var i = 0; i < count; i++) {
        final strPtr = backendsPtr[i];
        if (strPtr != nullptr) {
          backends.add(strPtr.toDartString());
        }
      }

      return backends;
    } finally {
      calloc.free(countPtr);
    }
  }

  /// Create and initialize a backend.
  ///
  /// [backendName] - Name of the backend ("onnx", "llamacpp", etc.)
  /// [config] - Optional JSON configuration
  void create(String backendName, {Map<String, dynamic>? config}) {
    final namePtr = backendName.toNativeUtf8();

    try {
      _handle = _createBackend(namePtr);

      if (_handle == nullptr) {
        throw NativeBackendException(
          'Failed to create backend: $backendName. ${_getError()}',
        );
      }

      _backendName = backendName;

      final configJson = config != null ? jsonEncode(config) : null;
      final configPtr = configJson?.toNativeUtf8() ?? nullptr;

      try {
        final result = _initialize(_handle!, configPtr);

        if (result != RaResultCode.success) {
          throw NativeBackendException(
            'Failed to initialize backend: ${_getError()}',
            code: result,
          );
        }
      } finally {
        if (configPtr != nullptr) {
          calloc.free(configPtr);
        }
      }
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Check if the backend is initialized.
  bool get isInitialized => _handle != null && _isInitialized(_handle!);

  /// Get the backend name.
  String? get backendName => _backendName;

  /// Get backend info as a map.
  Map<String, dynamic> getBackendInfo() {
    _ensureInitialized();

    final ptr = _getBackendInfo(_handle!);
    if (ptr == nullptr) return {};

    try {
      return jsonDecode(ptr.toDartString()) as Map<String, dynamic>;
    } finally {
      _freeString(ptr);
    }
  }

  /// Check if the backend supports a specific capability.
  bool supportsCapability(int capability) {
    _ensureInitialized();
    return _supportsCapability(_handle!, capability);
  }

  /// Get the device type being used.
  int getDevice() {
    _ensureInitialized();
    return _getDevice(_handle!);
  }

  /// Get memory usage in bytes.
  int getMemoryUsage() {
    _ensureInitialized();
    return _getMemoryUsage(_handle!);
  }

  /// Destroy the backend and release resources.
  void dispose() {
    if (_handle != null) {
      _destroy(_handle!);
      _handle = null;
      _backendName = null;
    }
  }

  // ============================================================================
  // STT (Speech-to-Text)
  // ============================================================================

  /// Load an STT model.
  void loadSttModel(
    String modelPath, {
    String modelType = 'whisper',
    Map<String, dynamic>? config,
  }) {
    _ensureInitialized();

    final pathPtr = modelPath.toNativeUtf8();
    final typePtr = modelType.toNativeUtf8();
    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final result = _sttLoadModel(_handle!, pathPtr, typePtr, configPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to load STT model: ${_getError()}',
          code: result,
        );
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(typePtr);
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Check if an STT model is loaded.
  bool get isSttModelLoaded {
    if (_handle == null) return false;
    return _sttIsModelLoaded(_handle!);
  }

  /// Unload the STT model.
  void unloadSttModel() {
    _ensureInitialized();
    _sttUnloadModel(_handle!);
  }

  /// Check if STT supports streaming.
  bool get sttSupportsStreaming {
    if (_handle == null) return false;
    return _sttSupportsStreaming(_handle!);
  }

  /// Transcribe audio samples (batch mode).
  ///
  /// [samples] - Float32 audio samples (-1.0 to 1.0)
  /// [sampleRate] - Sample rate in Hz (typically 16000)
  /// [language] - Language code (e.g., "en", "es") or null for auto-detect
  ///
  /// Returns a map with transcription result.
  Map<String, dynamic> transcribe(
    Float32List samples, {
    int sampleRate = 16000,
    String? language,
  }) {
    _ensureInitialized();

    // Allocate native array
    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    final langPtr = language?.toNativeUtf8() ?? nullptr;
    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      final status = _sttTranscribe(
        _handle!,
        samplesPtr,
        samples.length,
        sampleRate,
        langPtr,
        resultPtr,
      );

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'Transcription failed: ${_getError()}',
          code: status,
        );
      }

      if (resultPtr.value == nullptr) {
        return {'text': '', 'confidence': 1.0};
      }

      final resultJson = resultPtr.value.toDartString();
      _freeString(resultPtr.value);

      return jsonDecode(resultJson) as Map<String, dynamic>;
    } finally {
      calloc.free(samplesPtr);
      if (langPtr != nullptr) calloc.free(langPtr);
      calloc.free(resultPtr);
    }
  }

  /// Create an STT streaming session.
  RaStreamHandle createSttStream({Map<String, dynamic>? config}) {
    _ensureInitialized();

    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final stream = _sttCreateStream(_handle!, configPtr);
      if (stream == nullptr) {
        throw NativeBackendException(
            'Failed to create STT stream: ${_getError()}');
      }
      return stream;
    } finally {
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Feed audio to an STT stream.
  void feedSttAudio(
    RaStreamHandle stream,
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    _ensureInitialized();

    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    try {
      final status = _sttFeedAudio(
        _handle!,
        stream,
        samplesPtr,
        samples.length,
        sampleRate,
      );

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to feed audio: ${_getError()}',
          code: status,
        );
      }
    } finally {
      calloc.free(samplesPtr);
    }
  }

  /// Check if STT decoder is ready.
  bool isSttReady(RaStreamHandle stream) {
    _ensureInitialized();
    return _sttIsReady(_handle!, stream);
  }

  /// Decode and get current STT result.
  Map<String, dynamic>? decodeStt(RaStreamHandle stream) {
    _ensureInitialized();

    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      final status = _sttDecode(_handle!, stream, resultPtr);

      if (status != RaResultCode.success) {
        return null;
      }

      if (resultPtr.value == nullptr) {
        return null;
      }

      final resultJson = resultPtr.value.toDartString();
      _freeString(resultPtr.value);

      return jsonDecode(resultJson) as Map<String, dynamic>;
    } finally {
      calloc.free(resultPtr);
    }
  }

  /// Check for end-of-speech (endpoint detection).
  bool isSttEndpoint(RaStreamHandle stream) {
    _ensureInitialized();
    return _sttIsEndpoint(_handle!, stream);
  }

  /// Signal end of audio input.
  void sttInputFinished(RaStreamHandle stream) {
    _ensureInitialized();
    _sttInputFinished(_handle!, stream);
  }

  /// Reset stream for new utterance.
  void resetSttStream(RaStreamHandle stream) {
    _ensureInitialized();
    _sttResetStream(_handle!, stream);
  }

  /// Destroy STT stream.
  void destroySttStream(RaStreamHandle stream) {
    if (_handle != null) {
      _sttDestroyStream(_handle!, stream);
    }
  }

  /// Cancel ongoing transcription.
  void cancelStt() {
    if (_handle != null) {
      _sttCancel(_handle!);
    }
  }

  // ============================================================================
  // TTS (Text-to-Speech)
  // ============================================================================

  /// Load a TTS model.
  void loadTtsModel(
    String modelPath, {
    String modelType = 'vits',
    Map<String, dynamic>? config,
  }) {
    _ensureInitialized();

    final pathPtr = modelPath.toNativeUtf8();
    final typePtr = modelType.toNativeUtf8();
    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final result = _ttsLoadModel(_handle!, pathPtr, typePtr, configPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to load TTS model: ${_getError()}',
          code: result,
        );
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(typePtr);
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Check if a TTS model is loaded.
  bool get isTtsModelLoaded {
    if (_handle == null) return false;
    return _ttsIsModelLoaded(_handle!);
  }

  /// Unload the TTS model.
  void unloadTtsModel() {
    _ensureInitialized();
    _ttsUnloadModel(_handle!);
  }

  /// Check if TTS supports streaming.
  bool get ttsSupportsStreaming {
    if (_handle == null) return false;
    return _ttsSupportsStreaming(_handle!);
  }

  /// Synthesize speech from text.
  ///
  /// Returns a map with:
  /// - 'samples': Float32List of audio samples
  /// - 'sampleRate': int sample rate
  Map<String, dynamic> synthesize(
    String text, {
    String? voiceId,
    double speed = 1.0,
    double pitch = 0.0,
  }) {
    _ensureInitialized();

    final textPtr = text.toNativeUtf8();
    final voicePtr = voiceId?.toNativeUtf8() ?? nullptr;
    final samplesPtr = calloc<Pointer<Float>>();
    final numSamplesPtr = calloc<IntPtr>();
    final sampleRatePtr = calloc<Int32>();

    try {
      final status = _ttsSynthesize(
        _handle!,
        textPtr,
        voicePtr,
        speed,
        pitch,
        samplesPtr,
        numSamplesPtr,
        sampleRatePtr,
      );

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'TTS synthesis failed: ${_getError()}',
          code: status,
        );
      }

      final numSamples = numSamplesPtr.value;
      final sampleRate = sampleRatePtr.value;

      if (samplesPtr.value == nullptr || numSamples == 0) {
        return {'samples': Float32List(0), 'sampleRate': sampleRate};
      }

      // Copy to Dart-managed memory
      final samples = Float32List.fromList(
        samplesPtr.value.asTypedList(numSamples),
      );

      // Free C-allocated audio
      _freeAudio(samplesPtr.value);

      return {
        'samples': samples,
        'sampleRate': sampleRate,
      };
    } finally {
      calloc.free(textPtr);
      if (voicePtr != nullptr) calloc.free(voicePtr);
      calloc.free(samplesPtr);
      calloc.free(numSamplesPtr);
      calloc.free(sampleRatePtr);
    }
  }

  /// Get available TTS voices.
  /// Returns a list of voice IDs extracted from the native backend.
  List<String> getTtsVoices() {
    _ensureInitialized();

    final ptr = _ttsGetVoices(_handle!);
    if (ptr == nullptr) return [];

    try {
      final json = ptr.toDartString();
      final decoded = jsonDecode(json);
      if (decoded is List) {
        // Handle both string lists and object lists
        return decoded.map((item) {
          if (item is String) {
            return item;
          } else if (item is Map<String, dynamic>) {
            // Extract voice ID from object - try common field names
            return (item['id'] ??
                item['voice_id'] ??
                item['name'] ??
                item.toString()) as String;
          }
          return item.toString();
        }).toList();
      }
      return [json];
    } finally {
      _freeString(ptr);
    }
  }

  /// Cancel ongoing TTS synthesis.
  void cancelTts() {
    if (_handle != null) {
      _ttsCancel(_handle!);
    }
  }

  // ============================================================================
  // LLM (Text Generation)
  // ============================================================================

  /// Load a text generation model.
  void loadTextModel(String modelPath, {Map<String, dynamic>? config}) {
    _ensureInitialized();

    final pathPtr = modelPath.toNativeUtf8();
    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final result = _textLoadModel(_handle!, pathPtr, configPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to load text model: ${_getError()}',
          code: result,
        );
      }
    } finally {
      calloc.free(pathPtr);
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Check if a text model is loaded.
  bool get isTextModelLoaded {
    if (_handle == null) return false;
    return _textIsModelLoaded(_handle!);
  }

  /// Unload the text model.
  void unloadTextModel() {
    _ensureInitialized();
    _textUnloadModel(_handle!);
  }

  /// Generate text (non-streaming).
  Map<String, dynamic> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    _ensureInitialized();

    final promptPtr = prompt.toNativeUtf8();
    final sysPromptPtr = systemPrompt?.toNativeUtf8() ?? nullptr;
    final resultPtr = calloc<Pointer<Utf8>>();

    try {
      final status = _textGenerate(
        _handle!,
        promptPtr,
        sysPromptPtr,
        maxTokens,
        temperature,
        resultPtr,
      );

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'Text generation failed: ${_getError()}',
          code: status,
        );
      }

      if (resultPtr.value == nullptr) {
        return {'text': ''};
      }

      final resultJson = resultPtr.value.toDartString();
      _freeString(resultPtr.value);

      return jsonDecode(resultJson) as Map<String, dynamic>;
    } finally {
      calloc.free(promptPtr);
      if (sysPromptPtr != nullptr) calloc.free(sysPromptPtr);
      calloc.free(resultPtr);
    }
  }

  /// Cancel ongoing text generation.
  void cancelTextGeneration() {
    if (_handle != null) {
      _textCancel(_handle!);
    }
  }

  // ============================================================================
  // VAD (Voice Activity Detection)
  // ============================================================================

  /// Load a VAD model.
  void loadVadModel(String? modelPath, {Map<String, dynamic>? config}) {
    _ensureInitialized();

    final pathPtr = modelPath?.toNativeUtf8() ?? nullptr;
    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final result = _vadLoadModel(_handle!, pathPtr, configPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to load VAD model: ${_getError()}',
          code: result,
        );
      }
    } finally {
      if (pathPtr != nullptr) calloc.free(pathPtr);
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Check if a VAD model is loaded.
  bool get isVadModelLoaded {
    if (_handle == null) return false;
    return _vadIsModelLoaded(_handle!);
  }

  /// Unload the VAD model.
  void unloadVadModel() {
    _ensureInitialized();
    _vadUnloadModel(_handle!);
  }

  /// Process audio for voice activity detection.
  ///
  /// Returns a map with:
  /// - 'isSpeech': bool
  /// - 'probability': double (0.0 to 1.0)
  Map<String, dynamic> processVad(
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    _ensureInitialized();

    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    final isSpeechPtr = calloc<Bool>();
    final probabilityPtr = calloc<Float>();

    try {
      final status = _vadProcess(
        _handle!,
        samplesPtr,
        samples.length,
        sampleRate,
        isSpeechPtr,
        probabilityPtr,
      );

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'VAD processing failed: ${_getError()}',
          code: status,
        );
      }

      return {
        'isSpeech': isSpeechPtr.value,
        'probability': probabilityPtr.value,
      };
    } finally {
      calloc.free(samplesPtr);
      calloc.free(isSpeechPtr);
      calloc.free(probabilityPtr);
    }
  }

  /// Create a VAD streaming session.
  RaStreamHandle createVadStream({Map<String, dynamic>? config}) {
    _ensureInitialized();

    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final stream = _vadCreateStream(_handle!, configPtr);
      if (stream == nullptr) {
        throw NativeBackendException(
            'Failed to create VAD stream: ${_getError()}');
      }
      return stream;
    } finally {
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Destroy VAD stream.
  void destroyVadStream(RaStreamHandle stream) {
    if (_handle != null) {
      _vadDestroyStream(_handle!, stream);
    }
  }

  /// Reset VAD state.
  void resetVad() {
    if (_handle != null) {
      _vadReset(_handle!);
    }
  }

  // ============================================================================
  // Embeddings
  // ============================================================================

  /// Load an embedding model.
  void loadEmbedModel(String modelPath, {Map<String, dynamic>? config}) {
    _ensureInitialized();

    final pathPtr = modelPath.toNativeUtf8();
    final configJson = config != null ? jsonEncode(config) : null;
    final configPtr = configJson?.toNativeUtf8() ?? nullptr;

    try {
      final result = _embedLoadModel(_handle!, pathPtr, configPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Failed to load embedding model: ${_getError()}',
          code: result,
        );
      }
    } finally {
      calloc.free(pathPtr);
      if (configPtr != nullptr) calloc.free(configPtr);
    }
  }

  /// Check if an embedding model is loaded.
  bool get isEmbedModelLoaded {
    if (_handle == null) return false;
    return _embedIsModelLoaded(_handle!);
  }

  /// Get embedding dimensions.
  int getEmbedDimensions() {
    _ensureInitialized();
    return _embedGetDimensions(_handle!);
  }

  /// Generate embedding for text.
  Float32List embedText(String text) {
    _ensureInitialized();

    final textPtr = text.toNativeUtf8();
    final embeddingPtr = calloc<Pointer<Float>>();
    final dimensionsPtr = calloc<Int32>();

    try {
      final status = _embedText(_handle!, textPtr, embeddingPtr, dimensionsPtr);

      if (status != RaResultCode.success) {
        throw NativeBackendException(
          'Embedding failed: ${_getError()}',
          code: status,
        );
      }

      final dimensions = dimensionsPtr.value;
      if (embeddingPtr.value == nullptr || dimensions == 0) {
        return Float32List(0);
      }

      // Copy to Dart-managed memory
      final embedding = Float32List.fromList(
        embeddingPtr.value.asTypedList(dimensions),
      );

      // Free C-allocated embedding
      _freeEmbedding(embeddingPtr.value);

      return embedding;
    } finally {
      calloc.free(textPtr);
      calloc.free(embeddingPtr);
      calloc.free(dimensionsPtr);
    }
  }

  // ============================================================================
  // Utility Functions
  // ============================================================================

  /// Extract an archive to a destination directory.
  void extractArchive(String archivePath, String destDir) {
    final archivePtr = archivePath.toNativeUtf8();
    final destPtr = destDir.toNativeUtf8();

    try {
      final result = _extractArchive(archivePtr, destPtr);

      if (result != RaResultCode.success) {
        throw NativeBackendException(
          'Archive extraction failed: ${_getError()}',
          code: result,
        );
      }
    } finally {
      calloc.free(archivePtr);
      calloc.free(destPtr);
    }
  }

  /// Get the library version.
  String get version {
    final ptr = _getVersion();
    if (ptr == nullptr) return 'unknown';
    return ptr.toDartString(); // Don't free - static pointer
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  void _ensureInitialized() {
    if (_handle == null) {
      throw NativeBackendException(
          'Backend not initialized. Call create() first.');
    }
  }

  String _getError() {
    final ptr = _getLastError();
    if (ptr == nullptr) return 'Unknown error';
    return ptr.toDartString(); // Don't free - static pointer
  }
}

/// Exception thrown by native backend operations.
class NativeBackendException implements Exception {
  final String message;
  final int? code;

  NativeBackendException(this.message, {this.code});

  @override
  String toString() {
    if (code != null) {
      return 'NativeBackendException: $message (code: $code - ${RaResultCode.getMessage(code!)})';
    }
    return 'NativeBackendException: $message';
  }
}
