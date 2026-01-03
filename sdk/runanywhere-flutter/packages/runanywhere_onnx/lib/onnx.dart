/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This module provides STT, TTS, VAD, and LLM capabilities via the native
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
/// - **LLM (Language Models)**: Text generation
library runanywhere_onnx;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/module/capability_type.dart';
import 'package:runanywhere/core/module/inference_framework.dart';
import 'package:runanywhere/core/module/runanywhere_module.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/native_backend.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere_onnx/providers/onnx_llm_provider.dart';
import 'package:runanywhere_onnx/providers/onnx_stt_provider.dart';
import 'package:runanywhere_onnx/providers/onnx_tts_provider.dart';
import 'package:runanywhere_onnx/providers/onnx_vad_provider.dart';

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
// Matches Swift ONNX enum from ONNXRuntime/ONNX.swift
// ============================================================================

/// ONNX module for STT, TTS, VAD, and LLM capabilities.
///
/// Provides speech-to-text, text-to-speech, voice activity detection,
/// and language model services using ONNX Runtime with Sherpa-ONNX models.
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
  Set<CapabilityType> get capabilities => {
        CapabilityType.stt,
        CapabilityType.tts,
        CapabilityType.vad,
        CapabilityType.llm,
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
  // Registration (matches Swift ONNX.register() exactly)
  // ============================================================================

  /// Register ONNX module with the SDK.
  ///
  /// Matches Swift `ONNX.register(priority:)` pattern exactly.
  /// Calls the C++ `rac_backend_onnx_register()` function via FFI.
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

    final lib = PlatformLoader.load();

    // Step 1: Call C++ registration function via FFI (matches Swift exactly)
    try {
      final registerFn = lib.lookupFunction<
          Int32 Function(),
          int Function()>('rac_backend_onnx_register');

      final result = registerFn();

      // RAC_SUCCESS = 0, RAC_ERROR_MODULE_ALREADY_REGISTERED = specific code
      if (result != RacResultCode.success && result != -100) {
        // -100 = already registered, which is OK
        _logger.warning('C++ backend registration returned: $result');
      } else {
        _logger.debug('C++ backend registered successfully');
      }
    } catch (e) {
      _logger.debug('rac_backend_onnx_register not available: $e');
      // Continue with Dart-side registration as fallback
    }

    // Step 2: Create native backend for operations
    _backend = NativeBackend();
    _backend!.create('onnx');

    // Step 3: Register with Dart ModuleRegistry
    ModuleRegistry.shared.registerModule(_instance, priority: priority);

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

    registry.registerLLM(
      OnnxLLMServiceProvider(_backend!),
      priority: priority,
    );

    _isRegistered = true;
    _logger.info('ONNX Runtime registered with capabilities: STT, TTS, VAD, LLM');
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
