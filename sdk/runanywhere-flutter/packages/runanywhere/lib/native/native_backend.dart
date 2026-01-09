import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// RAC Core - SDK Initialization and Module Management
// =============================================================================

/// Core RAC (RunAnywhere Commons) functionality.
///
/// Provides SDK-level initialization, shutdown, and module management.
/// This is the Dart equivalent of the C rac_core.h API.
class RacCore {
  static bool _initialized = false;
  static DynamicLibrary? _lib;

  // Cached function pointers
  static RacInitDart? _racInit;
  static RacShutdownDart? _racShutdown;
  static RacIsInitializedDart? _racIsInitialized;
  static RacFreeDart? _racFree;
  static RacErrorMessageDart? _racErrorMessage;

  /// Initialize the RAC commons library.
  ///
  /// This must be called before using any RAC functionality.
  /// The platform adapter provides callbacks for platform-specific operations.
  ///
  /// Throws [RacException] if initialization fails.
  static void init({int logLevel = RacLogLevel.info}) {
    if (_initialized) {
      return; // Already initialized
    }

    _lib = PlatformLoader.loadCommons();
    _bindCoreFunctions();

    // For now, pass null config (platform adapter setup done separately)
    // The C++ library handles null config gracefully
    final result = _racInit!(nullptr);

    if (result != RAC_SUCCESS) {
      throw RacException('RAC initialization failed', code: result);
    }

    _initialized = true;
  }

  /// Shutdown the RAC commons library.
  ///
  /// This releases all resources and unregisters all modules.
  static void shutdown() {
    if (!_initialized || _lib == null) {
      return;
    }

    _racShutdown!();
    _initialized = false;
  }

  /// Check if the RAC library is initialized.
  static bool get isInitialized {
    if (_lib == null) {
      return false;
    }
    _bindCoreFunctions();
    return _racIsInitialized!() == RAC_TRUE;
  }

  /// Free memory allocated by RAC functions.
  static void free(Pointer<Void> ptr) {
    if (_lib == null || ptr == nullptr) return;
    _bindCoreFunctions();
    _racFree!(ptr);
  }

  /// Get error message for an error code.
  static String getErrorMessage(int code) {
    if (_lib == null) {
      return RacResultCode.getMessage(code);
    }
    _bindCoreFunctions();
    final ptr = _racErrorMessage!(code);
    if (ptr == nullptr) {
      return RacResultCode.getMessage(code);
    }
    return ptr.toDartString();
  }

  /// Bind core FFI functions (lazy initialization).
  static void _bindCoreFunctions() {
    if (_racInit != null) return;

    _racInit = _lib!.lookupFunction<RacInitNative, RacInitDart>('rac_init');
    _racShutdown = _lib!
        .lookupFunction<RacShutdownNative, RacShutdownDart>('rac_shutdown');
    _racIsInitialized = _lib!
        .lookupFunction<RacIsInitializedNative, RacIsInitializedDart>(
            'rac_is_initialized');
    _racFree = _lib!.lookupFunction<RacFreeNative, RacFreeDart>('rac_free');
    _racErrorMessage = _lib!
        .lookupFunction<RacErrorMessageNative, RacErrorMessageDart>(
            'rac_error_message');
  }

  /// Get the library for advanced operations.
  static DynamicLibrary? get library => _lib;
}

// =============================================================================
// Native Backend - High-Level Wrapper for Backend Operations
// =============================================================================

/// High-level wrapper around the RunAnywhere native C API.
///
/// This class provides a Dart-friendly interface to native backends,
/// handling memory management and type conversions.
///
/// The new architecture supports multiple backends:
/// - LlamaCPP: LLM text generation
/// - ONNX: STT, TTS, VAD
///
/// ## Usage
///
/// ```dart
/// // For LlamaCPP
/// final llamacpp = NativeBackend.llamacpp();
/// llamacpp.initialize();
/// llamacpp.loadModel('/path/to/model.gguf');
/// final result = llamacpp.generate('Hello, world!');
/// llamacpp.dispose();
///
/// // For ONNX
/// final onnx = NativeBackend.onnx();
/// onnx.initialize();
/// onnx.loadSttModel('/path/to/whisper');
/// final text = onnx.transcribe(audioSamples);
/// onnx.dispose();
/// ```
class NativeBackend {
  final DynamicLibrary _lib;
  final String _backendType;
  RacHandle? _handle;

  // Cached function lookups - Memory management
  // ignore: unused_field
  late final RacFreeDart _freePtr;

  // State
  bool _isInitialized = false;
  String? _currentModel;

  NativeBackend._(this._lib, this._backendType) {
    _bindBaseFunctions();
  }

  /// Create a LlamaCPP backend for LLM operations.
  factory NativeBackend.llamacpp() {
    return NativeBackend._(PlatformLoader.loadLlamaCpp(), 'llamacpp');
  }

  /// Create an ONNX backend for STT/TTS/VAD operations.
  factory NativeBackend.onnx() {
    return NativeBackend._(PlatformLoader.loadOnnx(), 'onnx');
  }

  /// Create a backend using the default (commons) library.
  /// For backward compatibility.
  factory NativeBackend() {
    return NativeBackend._(PlatformLoader.loadCommons(), 'commons');
  }

  /// Try to create a native backend, returning null if it fails.
  static NativeBackend? tryCreate() {
    try {
      return NativeBackend();
    } catch (_) {
      return null;
    }
  }

  void _bindBaseFunctions() {
    try {
      _freePtr = _lib.lookupFunction<RacFreeNative, RacFreeDart>('rac_free');
    } catch (_) {
      // Some backends might not export rac_free directly
      // Fall back to RacCore.free
      _freePtr = (ptr) => RacCore.free(ptr);
    }
  }

  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  /// Create and initialize the backend.
  ///
  /// [backendName] - Name of the backend (for backward compatibility)
  /// [config] - Optional JSON configuration
  void create(String backendName, {Map<String, dynamic>? config}) {
    // The new architecture doesn't require explicit create()
    // Backends register themselves via their register() functions
    _isInitialized = true;
  }

  /// Initialize the backend (simplified for new architecture).
  void initialize() {
    _isInitialized = true;
  }

  /// Check if the backend is initialized.
  bool get isInitialized => _isInitialized;

  /// Get the backend type.
  String get backendName => _backendType;

  /// Get the backend handle (for advanced operations).
  RacHandle? get handle => _handle;

  /// Destroy the backend and release resources.
  void dispose() {
    if (_handle != null && _handle != nullptr) {
      // Call appropriate destroy function based on backend type
      _destroyHandle();
      _handle = null;
    }
    _isInitialized = false;
    _currentModel = null;
  }

  void _destroyHandle() {
    if (_handle == null || _handle == nullptr) return;

    try {
      switch (_backendType) {
        case 'llamacpp':
          final destroy = _lib.lookupFunction<RacLlmLlamacppDestroyNative,
              RacLlmLlamacppDestroyDart>('rac_llm_llamacpp_destroy');
          destroy(_handle!);
          break;
        case 'onnx':
          // ONNX has separate destroy functions for each service type
          // Handle based on what was loaded
          break;
        default:
          // Commons library doesn't have a generic destroy
          break;
      }
    } catch (_) {
      // Ignore errors during cleanup
    }
  }

  // ============================================================================
  // LLM Operations (LlamaCPP Backend)
  // ============================================================================

  /// Load a text generation model (LLM).
  void loadTextModel(String modelPath, {Map<String, dynamic>? config}) {
    _ensureBackendType('llamacpp');

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();

    try {
      final create = _lib.lookupFunction<RacLlmLlamacppCreateNative,
          RacLlmLlamacppCreateDart>('rac_llm_llamacpp_create');

      final result = create(pathPtr, nullptr, handlePtr);

      if (result != RAC_SUCCESS) {
        throw NativeBackendException(
          'Failed to load text model: ${RacCore.getErrorMessage(result)}',
          code: result,
        );
      }

      _handle = handlePtr.value;
      _currentModel = modelPath;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
    }
  }

  /// Check if a text model is loaded.
  bool get isTextModelLoaded {
    if (_handle == null || _backendType != 'llamacpp') return false;

    try {
      final isLoaded = _lib.lookupFunction<RacLlmLlamacppIsModelLoadedNative,
          RacLlmLlamacppIsModelLoadedDart>('rac_llm_llamacpp_is_model_loaded');
      return isLoaded(_handle!) == RAC_TRUE;
    } catch (_) {
      return false;
    }
  }

  /// Unload the text model.
  void unloadTextModel() {
    if (_handle == null || _backendType != 'llamacpp') return;

    try {
      final unload = _lib.lookupFunction<RacLlmLlamacppUnloadModelNative,
          RacLlmLlamacppUnloadModelDart>('rac_llm_llamacpp_unload_model');
      unload(_handle!);
      _currentModel = null;
    } catch (e) {
      throw NativeBackendException('Failed to unload text model: $e');
    }
  }

  /// Generate text (non-streaming).
  Map<String, dynamic> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    _ensureBackendType('llamacpp');
    _ensureHandle();

    final promptPtr = prompt.toNativeUtf8();
    final resultPtr = calloc<RacLlmResultStruct>();

    // Create options struct
    final optionsPtr = calloc<RacLlmOptionsStruct>();
    optionsPtr.ref.maxTokens = maxTokens;
    optionsPtr.ref.temperature = temperature;
    optionsPtr.ref.topP = 1.0;
    optionsPtr.ref.streamingEnabled = RAC_FALSE;
    optionsPtr.ref.systemPrompt = systemPrompt?.toNativeUtf8() ?? nullptr;

    try {
      final generate = _lib.lookupFunction<RacLlmLlamacppGenerateNative,
          RacLlmLlamacppGenerateDart>('rac_llm_llamacpp_generate');

      final status = generate(
        _handle!,
        promptPtr,
        optionsPtr.cast(),
        resultPtr.cast(),
      );

      if (status != RAC_SUCCESS) {
        throw NativeBackendException(
          'Text generation failed: ${RacCore.getErrorMessage(status)}',
          code: status,
        );
      }

      // Extract result
      final result = resultPtr.ref;
      final text = result.text != nullptr ? result.text.toDartString() : '';

      return {
        'text': text,
        'prompt_tokens': result.promptTokens,
        'completion_tokens': result.completionTokens,
        'total_tokens': result.totalTokens,
        'time_to_first_token_ms': result.timeToFirstTokenMs,
        'total_time_ms': result.totalTimeMs,
        'tokens_per_second': result.tokensPerSecond,
      };
    } finally {
      calloc.free(promptPtr);
      if (optionsPtr.ref.systemPrompt != nullptr) {
        calloc.free(optionsPtr.ref.systemPrompt);
      }
      calloc.free(optionsPtr);
      calloc.free(resultPtr);
    }
  }

  /// Cancel ongoing text generation.
  void cancelTextGeneration() {
    if (_handle == null || _backendType != 'llamacpp') return;

    try {
      final cancel = _lib.lookupFunction<RacLlmLlamacppCancelNative,
          RacLlmLlamacppCancelDart>('rac_llm_llamacpp_cancel');
      cancel(_handle!);
    } catch (_) {
      // Ignore errors
    }
  }

  // ============================================================================
  // STT Operations (ONNX Backend)
  // ============================================================================

  /// Load an STT model.
  void loadSttModel(
    String modelPath, {
    String modelType = 'whisper',
    Map<String, dynamic>? config,
  }) {
    _ensureBackendType('onnx');

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    final configPtr = calloc<RacSttOnnxConfigStruct>();

    // Set config defaults
    configPtr.ref.modelType = modelType == 'whisper' ? 0 : 99; // AUTO
    configPtr.ref.numThreads = 0; // Auto
    configPtr.ref.useCoreml = RAC_TRUE;

    try {
      final create =
          _lib.lookupFunction<RacSttOnnxCreateNative, RacSttOnnxCreateDart>(
              'rac_stt_onnx_create');

      final result = create(pathPtr, configPtr.cast(), handlePtr);

      if (result != RAC_SUCCESS) {
        throw NativeBackendException(
          'Failed to load STT model: ${RacCore.getErrorMessage(result)}',
          code: result,
        );
      }

      _handle = handlePtr.value;
      _currentModel = modelPath;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      calloc.free(configPtr);
    }
  }

  /// Check if an STT model is loaded.
  bool get isSttModelLoaded {
    return _handle != null && _backendType == 'onnx';
  }

  /// Unload the STT model.
  void unloadSttModel() {
    if (_handle == null || _backendType != 'onnx') return;

    try {
      final destroy =
          _lib.lookupFunction<RacSttOnnxDestroyNative, RacSttOnnxDestroyDart>(
              'rac_stt_onnx_destroy');
      destroy(_handle!);
      _handle = null;
      _currentModel = null;
    } catch (e) {
      throw NativeBackendException('Failed to unload STT model: $e');
    }
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
    _ensureBackendType('onnx');
    _ensureHandle();

    // Allocate native array
    final samplesPtr = calloc<Float>(samples.length);
    final nativeList = samplesPtr.asTypedList(samples.length);
    nativeList.setAll(0, samples);

    final resultPtr = calloc<RacSttOnnxResultStruct>();

    try {
      final transcribe = _lib.lookupFunction<RacSttOnnxTranscribeNative,
          RacSttOnnxTranscribeDart>('rac_stt_onnx_transcribe');

      final status = transcribe(
        _handle!,
        samplesPtr,
        samples.length,
        nullptr, // options
        resultPtr.cast(),
      );

      if (status != RAC_SUCCESS) {
        throw NativeBackendException(
          'Transcription failed: ${RacCore.getErrorMessage(status)}',
          code: status,
        );
      }

      // Extract result from struct
      final result = resultPtr.ref;
      final text = result.text != nullptr ? result.text.toDartString() : '';
      final confidence = result.confidence;
      final languageOut =
          result.language != nullptr ? result.language.toDartString() : null;

      return {
        'text': text,
        'confidence': confidence,
        'language': languageOut,
        'duration_ms': result.durationMs,
      };
    } finally {
      calloc.free(samplesPtr);
      // Free result text if allocated by C++
      if (resultPtr.ref.text != nullptr) {
        RacCore.free(resultPtr.ref.text.cast());
      }
      calloc.free(resultPtr);
    }
  }

  /// Check if STT supports streaming.
  bool get sttSupportsStreaming {
    if (_handle == null || _backendType != 'onnx') return false;

    try {
      final supports = _lib.lookupFunction<RacSttOnnxSupportsStreamingNative,
          RacSttOnnxSupportsStreamingDart>('rac_stt_onnx_supports_streaming');
      return supports(_handle!) == RAC_TRUE;
    } catch (_) {
      return false;
    }
  }

  // ============================================================================
  // TTS Operations (ONNX Backend)
  // ============================================================================

  /// Load a TTS model.
  void loadTtsModel(
    String modelPath, {
    String modelType = 'vits',
    Map<String, dynamic>? config,
  }) {
    _ensureBackendType('onnx');

    final pathPtr = modelPath.toNativeUtf8();
    final handlePtr = calloc<RacHandle>();
    final configPtr = calloc<RacTtsOnnxConfigStruct>();

    // Set config defaults
    configPtr.ref.numThreads = 0; // Auto
    configPtr.ref.useCoreml = RAC_TRUE;
    configPtr.ref.sampleRate = 22050;

    try {
      final create =
          _lib.lookupFunction<RacTtsOnnxCreateNative, RacTtsOnnxCreateDart>(
              'rac_tts_onnx_create');

      final result = create(pathPtr, configPtr.cast(), handlePtr);

      if (result != RAC_SUCCESS) {
        throw NativeBackendException(
          'Failed to load TTS model: ${RacCore.getErrorMessage(result)}',
          code: result,
        );
      }

      _handle = handlePtr.value;
      _currentModel = modelPath;
    } finally {
      calloc.free(pathPtr);
      calloc.free(handlePtr);
      calloc.free(configPtr);
    }
  }

  /// Check if a TTS model is loaded.
  bool get isTtsModelLoaded {
    return _handle != null && _backendType == 'onnx';
  }

  /// Unload the TTS model.
  void unloadTtsModel() {
    if (_handle == null || _backendType != 'onnx') return;

    try {
      final destroy =
          _lib.lookupFunction<RacTtsOnnxDestroyNative, RacTtsOnnxDestroyDart>(
              'rac_tts_onnx_destroy');
      destroy(_handle!);
      _handle = null;
      _currentModel = null;
    } catch (e) {
      throw NativeBackendException('Failed to unload TTS model: $e');
    }
  }

  /// Synthesize speech from text.
  Map<String, dynamic> synthesize(
    String text, {
    String? voiceId,
    double speed = 1.0,
    double pitch = 0.0,
  }) {
    _ensureBackendType('onnx');
    _ensureHandle();

    final textPtr = text.toNativeUtf8();
    final resultPtr = calloc<RacTtsOnnxResultStruct>();

    try {
      final synthesize = _lib.lookupFunction<RacTtsOnnxSynthesizeNative,
          RacTtsOnnxSynthesizeDart>('rac_tts_onnx_synthesize');

      final status = synthesize(
        _handle!,
        textPtr,
        nullptr, // options (could include voice, speed, pitch)
        resultPtr.cast(),
      );

      if (status != RAC_SUCCESS) {
        throw NativeBackendException(
          'TTS synthesis failed: ${RacCore.getErrorMessage(status)}',
          code: status,
        );
      }

      // Extract result from struct
      final result = resultPtr.ref;
      final numSamples = result.numSamples;
      final sampleRate = result.sampleRate;

      // Copy audio samples to Dart
      Float32List samples;
      if (result.audioSamples != nullptr && numSamples > 0) {
        samples = Float32List.fromList(
          result.audioSamples.asTypedList(numSamples),
        );
      } else {
        samples = Float32List(0);
      }

      return {
        'samples': samples,
        'sampleRate': sampleRate,
        'durationMs': result.durationMs,
      };
    } finally {
      calloc.free(textPtr);
      // Free audio samples if allocated by C++
      if (resultPtr.ref.audioSamples != nullptr) {
        RacCore.free(resultPtr.ref.audioSamples.cast());
      }
      calloc.free(resultPtr);
    }
  }

  /// Get available TTS voices.
  List<String> getTtsVoices() {
    if (_handle == null || _backendType != 'onnx') return [];

    try {
      final getVoices = _lib.lookupFunction<RacTtsOnnxGetVoicesNative,
          RacTtsOnnxGetVoicesDart>('rac_tts_onnx_get_voices');

      final voicesPtr = calloc<Pointer<Pointer<Utf8>>>();
      final countPtr = calloc<IntPtr>();

      try {
        final status = getVoices(_handle!, voicesPtr, countPtr);

        if (status != RAC_SUCCESS) {
          return [];
        }

        final count = countPtr.value;
        final voices = <String>[];

        if (count > 0 && voicesPtr.value != nullptr) {
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
    } catch (_) {
      return [];
    }
  }

  // ============================================================================
  // VAD Operations (ONNX Backend)
  // ============================================================================

  RacHandle? _vadHandle;
  bool _vadUseNative = false;

  /// Load a VAD model.
  void loadVadModel(String? modelPath, {Map<String, dynamic>? config}) {
    _ensureBackendType('onnx');

    // Try to load native VAD if model path provided
    if (modelPath != null && modelPath.isNotEmpty) {
      try {
        final pathPtr = modelPath.toNativeUtf8();
        final handlePtr = calloc<RacHandle>();
        final configPtr = calloc<RacVadOnnxConfigStruct>();

        // Set config defaults
        configPtr.ref.numThreads = 0; // Auto
        configPtr.ref.sampleRate = 16000;
        configPtr.ref.windowSizeMs = 30;
        configPtr.ref.threshold = 0.5;

        try {
          final create =
              _lib.lookupFunction<RacVadOnnxCreateNative, RacVadOnnxCreateDart>(
                  'rac_vad_onnx_create');

          final result = create(pathPtr, configPtr.cast(), handlePtr);

          if (result == RAC_SUCCESS) {
            _vadHandle = handlePtr.value;
            _vadUseNative = true;
          }
        } finally {
          calloc.free(pathPtr);
          calloc.free(handlePtr);
          calloc.free(configPtr);
        }
      } catch (_) {
        // Fall back to energy-based detection
        _vadUseNative = false;
      }
    }

    _isInitialized = true;
  }

  /// Check if a VAD model is loaded.
  bool get isVadModelLoaded {
    return _isInitialized && _backendType == 'onnx';
  }

  /// Unload the VAD model.
  void unloadVadModel() {
    if (_vadHandle != null && _vadUseNative) {
      try {
        final destroy =
            _lib.lookupFunction<RacVadOnnxDestroyNative, RacVadOnnxDestroyDart>(
                'rac_vad_onnx_destroy');
        destroy(_vadHandle!);
      } catch (_) {
        // Ignore cleanup errors
      }
      _vadHandle = null;
    }
    _vadUseNative = false;
  }

  /// Process audio for voice activity detection.
  Map<String, dynamic> processVad(
    Float32List samples, {
    int sampleRate = 16000,
  }) {
    _ensureBackendType('onnx');

    // Use native VAD if available
    if (_vadUseNative && _vadHandle != null) {
      try {
        final samplesPtr = calloc<Float>(samples.length);
        final nativeList = samplesPtr.asTypedList(samples.length);
        nativeList.setAll(0, samples);

        final resultPtr = calloc<RacVadOnnxResultStruct>();

        try {
          final process = _lib.lookupFunction<RacVadOnnxProcessNative,
              RacVadOnnxProcessDart>('rac_vad_onnx_process');

          final status = process(
            _vadHandle!,
            samplesPtr,
            samples.length,
            resultPtr.cast(),
          );

          if (status == RAC_SUCCESS) {
            final result = resultPtr.ref;
            return {
              'isSpeech': result.isSpeech == RAC_TRUE,
              'probability': result.probability,
            };
          }
        } finally {
          calloc.free(samplesPtr);
          calloc.free(resultPtr);
        }
      } catch (_) {
        // Fall through to energy-based detection
      }
    }

    // Fallback: Basic energy-based VAD
    double energy = 0;
    for (final sample in samples) {
      energy += sample * sample;
    }
    energy = samples.isNotEmpty ? energy / samples.length : 0;

    const threshold = 0.01;
    final isSpeech = energy > threshold;

    return {
      'isSpeech': isSpeech,
      'probability': energy.clamp(0.0, 1.0),
    };
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /// Get backend info as a map.
  Map<String, dynamic> getBackendInfo() {
    return {
      'type': _backendType,
      'initialized': _isInitialized,
      'model': _currentModel,
      'hasHandle': _handle != null,
    };
  }

  /// Get list of available backend names.
  List<String> getAvailableBackends() {
    return ['llamacpp', 'onnx'];
  }

  /// Get the library version.
  String get version {
    // Return SDK version
    return '0.1.4';
  }

  /// Check if backend supports a specific capability.
  bool supportsCapability(int capability) {
    switch (_backendType) {
      case 'llamacpp':
        return capability == RacCapability.textGeneration;
      case 'onnx':
        return capability == RacCapability.stt ||
            capability == RacCapability.tts ||
            capability == RacCapability.vad;
      default:
        return false;
    }
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  void _ensureBackendType(String expected) {
    if (_backendType != expected) {
      throw NativeBackendException(
        'Backend type mismatch. Expected: $expected, got: $_backendType',
      );
    }
  }

  void _ensureHandle() {
    if (_handle == null || _handle == nullptr) {
      throw NativeBackendException(
        'No model loaded. Call loadTextModel/loadSttModel first.',
      );
    }
  }
}

// =============================================================================
// Exceptions
// =============================================================================

/// Exception thrown by RAC operations.
class RacException implements Exception {
  final String message;
  final int? code;

  RacException(this.message, {this.code});

  @override
  String toString() {
    if (code != null) {
      return 'RacException: $message (code: $code - ${RacResultCode.getMessage(code!)})';
    }
    return 'RacException: $message';
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
      return 'NativeBackendException: $message (code: $code - ${RacResultCode.getMessage(code!)})';
    }
    return 'NativeBackendException: $message';
  }
}
