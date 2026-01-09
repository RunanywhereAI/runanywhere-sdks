/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, and VAD capabilities via the native
/// runanywhere-core library using Dart FFI.
///
/// ## Quick Start (matches Swift ONNX API exactly)
///
/// ```dart
/// import 'package:runanywhere_onnx/runanywhere_onnx.dart';
///
/// // Register the module (matches Swift: ONNX.register())
/// await Onnx.register();
///
/// // Add STT models
/// Onnx.addModel(
///   name: 'Sherpa Whisper Tiny (ONNX)',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
///   memoryRequirement: 75000000,
/// );
/// ```
///
/// ## What This Provides
///
/// - **STT (Speech-to-Text)**: Streaming and batch transcription
/// - **TTS (Text-to-Speech)**: Neural voice synthesis using VITS models
/// - **VAD (Voice Activity Detection)**: Real-time speech detection
library runanywhere_onnx;

import 'dart:async';

import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/runanywhere.dart' show RunAnywhere;
import 'package:runanywhere_onnx/native/onnx_bindings.dart';
import 'package:runanywhere_onnx/providers/onnx_stt_provider.dart';
import 'package:runanywhere_onnx/providers/onnx_tts_provider.dart';
import 'package:runanywhere_onnx/providers/onnx_vad_provider.dart';

export 'onnx_download_strategy.dart';
export 'providers/onnx_stt_provider.dart';
export 'providers/onnx_tts_provider.dart';
export 'providers/onnx_vad_provider.dart';
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';

// ============================================================================
// ONNX Module Implementation
// Matches Swift ONNX enum from ONNXRuntime/ONNX.swift
// ============================================================================

/// ONNX module for STT, TTS, and VAD capabilities.
///
/// Provides speech-to-text, text-to-speech, and voice activity detection
/// services using ONNX Runtime with Sherpa-ONNX models.
///
/// Matches Swift `ONNX` enum from ONNXRuntime/ONNX.swift.
///
/// ## Registration (matches Swift ONNX pattern exactly)
///
/// ```dart
/// // Register module (matches Swift: ONNX.register())
/// await Onnx.register();
///
/// // Or with custom priority
/// await Onnx.register(priority: 150);
/// ```
class Onnx implements RunAnywhereModule {
  // ============================================================================
  // Singleton Pattern (matches Swift enum pattern)
  // ============================================================================

  /// Singleton instance for module metadata
  static final Onnx _instance = Onnx._internal();

  /// Get the module instance (for use with ModuleRegistry.registerModule)
  static Onnx get module => _instance;

  Onnx._internal();

  // ============================================================================
  // Module State
  // ============================================================================

  static final SDKLogger _logger = SDKLogger('Onnx');
  static bool _isRegistered = false;
  static NativeBackend? _backend;
  static OnnxBindings? _bindings;

  // ============================================================================
  // RunAnywhereModule Implementation (matches Swift ONNX enum)
  // ============================================================================

  @override
  String get moduleId => 'onnx';

  @override
  String get moduleName => 'ONNX Runtime';

  @override
  InferenceFramework get inferenceFramework => InferenceFramework.onnx;

  @override
  Set<SDKComponent> get capabilities => {
        SDKComponent.stt,
        SDKComponent.tts,
        SDKComponent.vad,
      };

  @override
  int get defaultPriority => 100;

  // ============================================================================
  // Static API (matches Swift ONNX static methods exactly)
  // ============================================================================

  /// Whether the module is registered
  static bool get isRegistered => _isRegistered;

  /// Get native backend (for advanced usage)
  static NativeBackend? get backend => _backend;

  /// Get native bindings (for advanced usage)
  static OnnxBindings? get bindings => _bindings;

  /// Check if the native backend is available on this platform.
  static bool get isAvailable {
    try {
      PlatformLoader.loadOnnx();
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
  // Registration (matches Swift ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX module with the SDK.
  ///
  /// Matches Swift `ONNX.register(priority:)` pattern exactly.
  /// Calls the C++ `rac_backend_onnx_register()` function via FFI.
  /// Registers STT, TTS, and VAD providers.
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

    // Step 1: Create bindings for native operations
    try {
      _bindings = OnnxBindings();
      _logger.debug('ONNX bindings initialized');
    } catch (e) {
      _logger.debug('OnnxBindings not available: $e');
      // Continue with Dart-side registration as fallback
    }

    // Step 2: Create native backend for operations (backward compatibility)
    _backend = NativeBackend.onnx();
    _backend!.initialize();

    // Step 3: Register module metadata with Dart ModuleRegistry
    ModuleRegistry.shared.registerModuleMetadata(ModuleMetadata(
      moduleId: _instance.moduleId,
      moduleName: _instance.moduleName,
      inferenceFramework: _instance.inferenceFramework,
      capabilities: _instance.capabilities,
      priority: priority,
      registeredAt: DateTime.now(),
    ));

    // Step 4: Register all capability providers
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

    // Step 5: Register model collector with RunAnywhere
    RunAnywhere.registerModelCollector(() => _registeredModels);

    _isRegistered = true;
    _logger.info('ONNX Runtime registered with capabilities: STT, TTS, VAD');
  }

  /// Register only ONNX STT service.
  ///
  /// Matches Swift `ONNX.registerSTT(priority:)` pattern.
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
  /// Matches Swift `ONNX.registerTTS(priority:)` pattern.
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

  /// Ensure native backend is initialized.
  static Future<void> _ensureBackendInitialized() async {
    if (_backend != null) return;

    if (!isAvailable) {
      throw StateError('ONNX native library not available');
    }

    _bindings ??= OnnxBindings();
    _backend = NativeBackend.onnx();
    _backend!.initialize();
  }

  // ============================================================================
  // Model Registration (matches Swift RunAnywhere.registerModel pattern)
  // ============================================================================

  /// Add a model to be used with ONNX Runtime.
  ///
  /// This is a convenience method that matches the Swift pattern where modules
  /// own their models.
  ///
  /// ```dart
  /// Onnx.addModel(
  ///   id: 'sherpa-onnx-whisper-tiny.en',
  ///   name: 'Sherpa Whisper Tiny (ONNX)',
  ///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
  ///   modality: ModelCategory.speechRecognition,
  ///   artifactType: ModelArtifactType.tarGzArchive(...),
  ///   memoryRequirement: 75000000,
  /// );
  /// ```
  static void addModel({
    String? id,
    required String name,
    required String url,
    ModelCategory modality = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _logger.error('Invalid URL for model: $name');
      return;
    }

    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    // Determine format and artifact type from URL
    final format = _inferFormat(uri.path);
    final inferredArtifact =
        artifactType ?? ModelArtifactType.infer(uri, format);

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: format,
      framework: InferenceFramework.onnx,
      downloadURL: uri,
      artifactType: inferredArtifact,
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
      source: ModelSource.local,
    );

    // Register with the module's internal registry
    _registeredModels.add(model);
    _logger.info('Added ONNX model: $name ($modelId) [$modality]');
  }

  /// Infer model format from URL path
  static ModelFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.onnx')) return ModelFormat.onnx;
    if (lower.endsWith('.ort')) return ModelFormat.ort;
    // Archives typically contain ONNX models
    if (lower.contains('.tar.') || lower.endsWith('.zip')) {
      return ModelFormat.onnx;
    }
    return ModelFormat.onnx; // Default for ONNX
  }

  /// Internal model registry for models added via addModel
  static final List<ModelInfo> _registeredModels = [];

  /// Get all models registered with this module
  static List<ModelInfo> get registeredModels =>
      List.unmodifiable(_registeredModels);

  // ============================================================================
  // Cleanup
  // ============================================================================

  /// Dispose of resources (for cleanup)
  static void dispose() {
    if (_backend != null) {
      _backend!.dispose();
      _backend = null;
    }
    _bindings = null;
    _registeredModels.clear();
    _isRegistered = false;
    _logger.info('ONNX disposed');
  }
}
