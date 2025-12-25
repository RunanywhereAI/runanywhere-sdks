/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, VAD, and LLM capabilities via the native
/// runanywhere-core library using Dart FFI.
///
/// ## Quick Start (matches iOS ONNX API exactly)
///
/// ```dart
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// // Register the module (matches iOS ONNX.register())
/// await Onnx.register();
///
/// // Add STT models
/// Onnx.addModel(
///   name: 'Sherpa Whisper Tiny (ONNX)',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
///   memoryRequirement: 75000000,
/// );
///
/// // Add TTS models
/// Onnx.addModel(
///   name: 'Piper TTS (US English)',
///   url: 'https://github.com/.../vits-piper-en_US-lessac-medium.tar.gz',
///   modality: ModelCategory.speechSynthesis,
///   memoryRequirement: 65000000,
/// );
/// ```
///
/// ## What This Provides
///
/// - **STT (Speech-to-Text)**: Streaming and batch transcription
/// - **TTS (Text-to-Speech)**: Neural voice synthesis using VITS models
/// - **VAD (Voice Activity Detection)**: Real-time speech detection
/// - **LLM (Language Models)**: Text generation
library runanywhere_onnx;

import 'package:runanywhere/backends/onnx/onnx_download_strategy.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_llm_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_stt_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_tts_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_vad_provider.dart';
import 'package:runanywhere/core/models/framework/model_artifact_type.dart';
import 'package:runanywhere/core/models/model/model_category.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/module/capability_type.dart';
import 'package:runanywhere/core/module/inference_framework.dart';
import 'package:runanywhere/core/module/model_storage_strategy.dart';
import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/core/protocols/downloading/download_strategy.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';

export 'onnx_download_strategy.dart';
export 'providers/onnx_llm_provider.dart';
export 'providers/onnx_stt_provider.dart';
export 'providers/onnx_tts_provider.dart';
export 'providers/onnx_vad_provider.dart';
export 'services/onnx_llm_service.dart';
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';

// ============================================================================
// ONNX Module Implementation
// Matches iOS ONNX enum from ONNXRuntime/ONNXServiceProvider.swift
// ============================================================================

/// ONNX module for STT, TTS, VAD, and LLM capabilities.
///
/// Provides speech-to-text, text-to-speech, voice activity detection,
/// and language model services using ONNX Runtime with Sherpa-ONNX models.
///
/// Matches iOS `ONNX` enum from ONNXRuntime/ONNXServiceProvider.swift.
///
/// ## Registration (matches iOS ONNX pattern exactly)
///
/// ```dart
/// // Register module (matches iOS: ONNX.register())
/// await Onnx.register();
///
/// // Or with custom priority
/// await Onnx.register(priority: 150);
///
/// // Add models (matches iOS: ONNX.addModel())
/// Onnx.addModel(
///   name: 'Sherpa Whisper Tiny',
///   url: 'https://github.com/.../model.tar.gz',
///   modality: ModelCategory.speechRecognition,
/// );
/// ```
class Onnx extends RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches iOS enum pattern)
  // ============================================================================

  /// Singleton instance for module metadata
  static final Onnx _instance = Onnx._internal();

  /// Get the module instance (for use with ModuleRegistry.registerModule)
  static Onnx get module => _instance;

  Onnx._internal();

  // ============================================================================
  // Module State
  // ============================================================================

  static final SDKLogger _logger = SDKLogger(category: 'Onnx');
  static bool _isRegistered = false;
  static NativeBackend? _backend;
  static OnnxDownloadStrategy? _downloadStrategyInstance;

  // ============================================================================
  // RunAnywhereModule Implementation (matches iOS ONNX enum)
  // ============================================================================

  @override
  String get moduleId => 'onnx';

  @override
  String get moduleName => 'ONNX Runtime';

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.onnx;

  @override
  Set<CapabilityType> get capabilities => {
        CapabilityType.stt,
        CapabilityType.tts,
        CapabilityType.vad,
        CapabilityType.llm,
      };

  @override
  int get defaultPriority => 100;

  @override
  ModelStorageStrategy? get storageStrategy => null;

  @override
  DownloadStrategy? get downloadStrategy {
    _downloadStrategyInstance ??= OnnxDownloadStrategy();
    return _downloadStrategyInstance;
  }

  // ============================================================================
  // Static API (matches iOS ONNX static methods exactly)
  // ============================================================================

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

  /// Check if the native backend is available on this platform.
  static bool get isAvailable {
    try {
      PlatformLoader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get the native library version.
  static String get version => _backend?.version ?? 'not initialized';

  /// Get backend info as a map.
  static Map<String, dynamic> getBackendInfo() {
    if (_backend == null) return {};
    return _backend!.getBackendInfo();
  }

  /// List of available backend names from the native library.
  static List<String> get availableBackends {
    if (_backend != null) {
      try {
        return _backend!.getAvailableBackends();
      } catch (_) {
        return [];
      }
    }
    if (!isAvailable) return [];
    NativeBackend? tempBackend;
    try {
      tempBackend = NativeBackend();
      return tempBackend.getAvailableBackends();
    } catch (_) {
      return [];
    } finally {
      tempBackend?.dispose();
    }
  }

  // ============================================================================
  // Registration (matches iOS ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX module with the SDK.
  ///
  /// Matches iOS `ONNX.register(priority:)` pattern exactly.
  /// Registers STT, TTS, VAD, and LLM providers.
  ///
  /// [priority] - Registration priority (higher = preferred). Default: 100.
  static Future<void> register({int priority = 100}) async {
    if (_isRegistered) {
      _logger.debug('ONNX already registered');
      return;
    }

    // Check native library availability
    if (!isAvailable) {
      _logger.error('ONNX native library not available');
      return;
    }

    // Create native backend
    _backend = NativeBackend();
    _backend!.create('onnx');

    // Register as a module with ModuleRegistry (matches iOS pattern)
    ModuleRegistry.shared.registerModule(_instance, priority: priority);

    // Register all capability providers
    final registry = ModuleRegistry.shared;

    registry.registerSTT(
      OnnxSTTServiceProvider(_backend!),
      priority: priority,
    );

    registry.registerTTS(
      OnnxTTSServiceProvider(_backend!),
      priority: priority,
    );

    registry.registerVAD(
      OnnxVADServiceProvider(_backend!),
      priority: priority,
    );

    registry.registerLLM(
      OnnxLLMServiceProvider(_backend!),
      priority: priority,
    );

    _isRegistered = true;
    _logger
        .info('ONNX Runtime registered with capabilities: STT, TTS, VAD, LLM');
  }

  /// Register only ONNX STT service.
  ///
  /// Matches iOS `ONNX.registerSTT(priority:)` pattern.
  static Future<void> registerSTT({int priority = 100}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerSTT(
      OnnxSTTServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX STT registered');
  }

  /// Register only ONNX TTS service.
  ///
  /// Matches iOS `ONNX.registerTTS(priority:)` pattern.
  static Future<void> registerTTS({int priority = 100}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerTTS(
      OnnxTTSServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX TTS registered');
  }

  /// Register only ONNX VAD service.
  static Future<void> registerVAD({int priority = 100}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerVAD(
      OnnxVADServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX VAD registered');
  }

  /// Register only ONNX LLM service.
  static Future<void> registerLLM({int priority = 100}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerLLM(
      OnnxLLMServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX LLM registered');
  }

  /// Ensure native backend is initialized.
  static Future<void> _ensureBackendInitialized() async {
    if (_backend != null) return;

    if (!isAvailable) {
      throw StateError('ONNX native library not available');
    }

    _backend = NativeBackend();
    _backend!.create('onnx');
  }

  // ============================================================================
  // Model Registration (matches iOS ONNX.addModel() exactly)
  // ============================================================================

  /// Add a model to this module.
  ///
  /// Matches iOS `ONNX.addModel()` pattern exactly.
  /// Uses the module's inferenceFramework automatically.
  ///
  /// [id] - Explicit model ID. If null, generated from URL filename.
  /// [name] - Display name for the model.
  /// [url] - Download URL string for the model.
  /// [modality] - Model category (speechRecognition, speechSynthesis, etc.).
  /// [artifactType] - How the model is packaged (e.g., tarGzArchive).
  /// [memoryRequirement] - Estimated memory usage in bytes.
  /// [supportsThinking] - Whether the model supports reasoning/thinking.
  ///
  /// Returns the created ModelInfo, or null if URL is invalid.
  static ModelInfo? addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory? modality,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    return _instance.addModelInternal(
      id: id,
      name: name,
      url: url,
      modality: modality,
      artifactType: artifactType,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources (for cleanup)
  static void dispose() {
    if (_backend != null) {
      _backend!.dispose();
      _backend = null;
    }
    _isRegistered = false;
    _logger.info('ONNX disposed');
  }
}
