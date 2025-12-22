/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, VAD capabilities via the native
/// runanywhere-core library using Dart FFI.
///
/// ## Quick Start (iOS-style API)
///
/// ```dart
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// // Register the module (matches iOS ONNX.register())
/// await Onnx.register();
///
/// // Add STT models
/// Onnx.addModel(
///   id: 'sherpa-onnx-whisper-tiny.en',
///   name: 'Sherpa Whisper Tiny (ONNX)',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
///   memoryRequirement: 75000000,
/// );
///
/// // Add TTS models
/// Onnx.addModel(
///   id: 'vits-piper-en_US-lessac-medium',
///   name: 'Piper TTS (US English)',
///   url: 'https://github.com/.../vits-piper-en_US-lessac-medium.tar.gz',
///   modality: ModelCategory.speechSynthesis,
///   memoryRequirement: 65000000,
/// );
/// ```
///
/// ## What This Provides
///
/// - **STT (Speech-to-Text)**: Streaming and batch transcription using
///   Sherpa-ONNX with Whisper and Zipformer models
/// - **TTS (Text-to-Speech)**: Neural voice synthesis using VITS models
/// - **VAD (Voice Activity Detection)**: Real-time speech detection
/// - **LLM (Language Models)**: Text generation (future)
///
/// ## Native Library Setup
///
/// Before using this backend, ensure native libraries are set up:
///
/// ```bash
/// # From runanywhere-core directory
/// ./scripts/flutter/setup.sh --platform ios /path/to/runanywhere-flutter
/// ./scripts/flutter/setup.sh --platform android /path/to/runanywhere-flutter
/// ```
library runanywhere_onnx;

import 'package:runanywhere/backends/onnx/onnx_download_strategy.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_llm_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_stt_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_tts_provider.dart';
import 'package:runanywhere/backends/onnx/providers/onnx_vad_provider.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/framework/model_artifact_type.dart';
import 'package:runanywhere/core/models/model/model_category.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';

export 'onnx_download_strategy.dart';
export 'providers/onnx_llm_provider.dart';
// Providers
export 'providers/onnx_stt_provider.dart';
export 'providers/onnx_tts_provider.dart';
export 'providers/onnx_vad_provider.dart';
export 'services/onnx_llm_service.dart';
// Services
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';

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
/// import 'package:runanywhere/backends/onnx/onnx.dart';
///
/// // Register module (matches iOS: ONNX.register())
/// await Onnx.register();
///
/// // Or register with custom priority
/// await Onnx.register(priority: 100);
///
/// // Add STT model
/// Onnx.addModel(
///   id: 'sherpa-onnx-whisper-tiny.en',
///   name: 'Sherpa Whisper Tiny (ONNX)',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
///   memoryRequirement: 75000000,
/// );
/// ```
class Onnx {
  static final _logger = SDKLogger(category: 'Onnx');

  // Module state
  static bool _isRegistered = false;
  static NativeBackend? _backend;
  static OnnxDownloadStrategy? _downloadStrategy;

  // Private constructor - use static methods only
  Onnx._();

  // ============================================================================
  // RunAnywhereModule Properties (matches iOS ONNX enum)
  // ============================================================================

  /// Module identifier (matches iOS ONNX.moduleId)
  static const String moduleId = 'onnx';

  /// Human-readable module name (matches iOS ONNX.moduleName)
  static const String moduleName = 'ONNX Runtime';

  /// Inference framework for this module (matches iOS ONNX.inferenceFramework)
  static LLMFramework get inferenceFramework => LLMFramework.onnx;

  /// Default registration priority (matches iOS ONNX.defaultPriority)
  static const int defaultPriority = 100;

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

  // ============================================================================
  // Backend Info (for compatibility with legacy code)
  // ============================================================================

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
    // Create temporary backend to check
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

  /// Get the download strategy for ONNX models.
  static DownloadStrategy? get downloadStrategy {
    _downloadStrategy ??= OnnxDownloadStrategy();
    return _downloadStrategy;
  }

  // ============================================================================
  // Registration (matches iOS ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX module with the SDK.
  ///
  /// Matches iOS `ONNX.register(priority:)` pattern exactly.
  /// Registers STT, TTS, VAD, and LLM providers with ModuleRegistry.
  ///
  /// [priority] - Registration priority (higher = preferred). Default: 100.
  static Future<void> register({int priority = defaultPriority}) async {
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

    // Register all providers with ModuleRegistry
    // Matches iOS: ServiceRegistry.shared.registerSTT/TTS/VAD/LLM(...)
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
    _logger.info('ONNX Runtime registered (STT, TTS, VAD, LLM)');
  }

  /// Register only ONNX STT service.
  ///
  /// Matches iOS `ONNX.registerSTT(priority:)` pattern.
  static Future<void> registerSTT({int priority = defaultPriority}) async {
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
  static Future<void> registerTTS({int priority = defaultPriority}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerTTS(
      OnnxTTSServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX TTS registered');
  }

  /// Register only ONNX VAD service.
  static Future<void> registerVAD({int priority = defaultPriority}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerVAD(
      OnnxVADServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX VAD registered');
  }

  /// Register only ONNX LLM service.
  static Future<void> registerLLM({int priority = defaultPriority}) async {
    await _ensureBackendInitialized();

    ModuleRegistry.shared.registerLLM(
      OnnxLLMServiceProvider(_backend!),
      priority: priority,
    );
    _logger.info('ONNX LLM registered');
  }

  // ============================================================================
  // Model Registration (matches iOS ONNX.addModel() exactly)
  // ============================================================================

  /// Add a model to this module.
  ///
  /// Matches iOS `ONNX.addModel()` pattern exactly.
  /// Uses the module's inferenceFramework automatically.
  ///
  /// [id] - Explicit model ID. If null, a stable ID is generated from the URL filename.
  /// [name] - Display name for the model.
  /// [url] - Download URL string for the model.
  /// [modality] - Model category (.speechRecognition for STT, .speechSynthesis for TTS).
  /// [artifactType] - How the model is packaged (e.g., tarGzArchive).
  /// [memoryRequirement] - Estimated memory usage in bytes.
  ///
  /// Returns the created ModelInfo, or null if URL is invalid.
  static ModelInfo? addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory modality = ModelCategory.speechRecognition,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
  }) {
    final downloadURL = Uri.tryParse(url);
    if (downloadURL == null) {
      _logger.error("Invalid URL for model '$name': $url");
      return null;
    }

    // Register the model with this module's framework
    final modelInfo = ServiceContainer.shared.modelRegistry.addModelFromURL(
      id: id,
      name: name,
      url: downloadURL,
      framework: inferenceFramework,
      category: modality,
      artifactType: artifactType,
      estimatedSize: memoryRequirement,
    );

    _logger.info("Added model '$name' (id: ${modelInfo.id})");
    return modelInfo;
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

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
