import '../../core/models/framework/framework_modality.dart';
import '../../core/models/framework/llm_framework.dart';
import '../../core/models/framework/model_format.dart';
import '../../core/models/hardware/hardware_configuration.dart';
import '../../core/models/model/model_info.dart';
import '../../core/module_registry.dart';
import '../../core/protocols/downloading/download_strategy.dart';
import '../../core/protocols/frameworks/unified_framework_adapter.dart';
import '../native/native_backend.dart';
import 'onnx_download_strategy.dart';
import 'providers/onnx_stt_provider.dart';
import 'providers/onnx_tts_provider.dart';
import 'providers/onnx_vad_provider.dart';
import 'providers/onnx_llm_provider.dart';
import 'services/onnx_stt_service.dart';
import 'services/onnx_tts_service.dart';
import 'services/onnx_vad_service.dart';
import 'services/onnx_llm_service.dart';

/// ONNX Runtime adapter for multi-modal inference.
///
/// This is the Flutter equivalent of Swift's `ONNXAdapter`.
/// It provides STT, TTS, VAD, and LLM capabilities through the
/// native runanywhere-core library.
///
/// ## Usage
///
/// The adapter is typically used internally by [OnnxBackend.initialize()],
/// but can also be used directly for advanced scenarios:
///
/// ```dart
/// final adapter = OnnxAdapter();
/// adapter.onRegistration(priority: 100);
///
/// // Create a service directly
/// final stt = adapter.createService(FrameworkModality.voiceToText);
/// ```
class OnnxAdapter
    with UnifiedFrameworkAdapterDefaults
    implements UnifiedFrameworkAdapter {
  NativeBackend? _backend;
  bool _isInitialized = false;

  // Cache service instances to avoid re-initialization
  OnnxSTTService? _cachedSTTService;
  OnnxTTSService? _cachedTTSService;
  OnnxVADService? _cachedVADService;
  OnnxLLMService? _cachedLLMService;

  // Download strategy for ONNX models
  OnnxDownloadStrategy? _downloadStrategy;

  // Track last usage for smart cleanup
  DateTime? _lastSTTUsage;
  DateTime? _lastTTSUsage;
  DateTime? _lastVADUsage;
  DateTime? _lastLLMUsage;
  final Duration _cacheTimeout = const Duration(minutes: 5);

  /// Create a new ONNX adapter.
  OnnxAdapter();

  /// Get the underlying native backend.
  NativeBackend? get nativeBackend => _backend;

  /// Check if the adapter is initialized.
  bool get isInitialized => _isInitialized;

  /// Get the native library version.
  String get version => _backend?.version ?? 'not initialized';

  /// Get backend info as a map.
  Map<String, dynamic> getBackendInfo() {
    if (_backend == null) {
      return {};
    }
    return _backend!.getBackendInfo();
  }

  // ============================================================================
  // UnifiedFrameworkAdapter Implementation
  // ============================================================================

  @override
  LLMFramework get framework => LLMFramework.onnx;

  @override
  Set<FrameworkModality> get supportedModalities => {
        FrameworkModality.voiceToText,
        FrameworkModality.textToVoice,
        FrameworkModality.voiceActivityDetection,
        FrameworkModality.textToText,
      };

  @override
  List<ModelFormat> get supportedFormats => [ModelFormat.onnx, ModelFormat.ort];

  @override
  bool canHandle(ModelInfo model) {
    // Check if model is compatible with ONNX Runtime
    return model.compatibleFrameworks.contains(LLMFramework.onnx) &&
        supportedModalities.any((m) => _modalityMatchesCategory(m, model));
  }

  @override
  dynamic createService(FrameworkModality modality) {
    _ensureInitialized();
    _cleanupStaleCache();

    switch (modality) {
      case FrameworkModality.voiceToText:
        if (_cachedSTTService != null) {
          _lastSTTUsage = DateTime.now();
          return _cachedSTTService;
        }
        final service = OnnxSTTService(_backend!);
        _cachedSTTService = service;
        _lastSTTUsage = DateTime.now();
        return service;

      case FrameworkModality.textToVoice:
        if (_cachedTTSService != null) {
          _lastTTSUsage = DateTime.now();
          return _cachedTTSService;
        }
        final service = OnnxTTSService(_backend!);
        _cachedTTSService = service;
        _lastTTSUsage = DateTime.now();
        return service;

      case FrameworkModality.voiceActivityDetection:
        if (_cachedVADService != null) {
          _lastVADUsage = DateTime.now();
          return _cachedVADService;
        }
        final service = OnnxVADService(_backend!);
        _cachedVADService = service;
        _lastVADUsage = DateTime.now();
        return service;

      case FrameworkModality.textToText:
        if (_cachedLLMService != null) {
          _lastLLMUsage = DateTime.now();
          return _cachedLLMService;
        }
        final service = OnnxLLMService(_backend!);
        _cachedLLMService = service;
        _lastLLMUsage = DateTime.now();
        return service;

      default:
        return null;
    }
  }

  @override
  Future<dynamic> loadModel(ModelInfo model, FrameworkModality modality) async {
    _ensureInitialized();
    _cleanupStaleCache();

    final modelPath = model.localPath?.toFilePath();

    switch (modality) {
      case FrameworkModality.voiceToText:
        final service = _cachedSTTService ?? OnnxSTTService(_backend!);
        await service.initialize(modelPath: modelPath);
        _cachedSTTService = service;
        _lastSTTUsage = DateTime.now();
        return service;

      case FrameworkModality.textToVoice:
        final service = _cachedTTSService ?? OnnxTTSService(_backend!);
        await service.initialize(modelPath: modelPath);
        _cachedTTSService = service;
        _lastTTSUsage = DateTime.now();
        return service;

      case FrameworkModality.voiceActivityDetection:
        final service = _cachedVADService ?? OnnxVADService(_backend!);
        await service.initialize(modelPath: modelPath);
        _cachedVADService = service;
        _lastVADUsage = DateTime.now();
        return service;

      case FrameworkModality.textToText:
        final service = _cachedLLMService ?? OnnxLLMService(_backend!);
        await service.initialize(modelPath: modelPath);
        _cachedLLMService = service;
        _lastLLMUsage = DateTime.now();
        return service;

      default:
        throw ArgumentError('Unsupported modality: $modality');
    }
  }

  @override
  int estimateMemoryUsage(ModelInfo model) {
    // ONNX models use approximately their file size in memory
    // Add overhead for session and processing
    final baseSize = model.memoryRequired ?? 0;
    final overhead = (baseSize * 0.3).toInt();
    return baseSize + overhead;
  }

  @override
  Future<void> configure(HardwareConfiguration hardware) async {
    // ONNX adapter can use hardware configuration
    // For now, this is a no-op
  }

  @override
  HardwareConfiguration optimalConfiguration(ModelInfo model) {
    // Return default configuration optimized for ONNX
    return HardwareConfiguration.defaultConfig;
  }

  @override
  List<ModelInfo> getProvidedModels() {
    // ONNX adapter doesn't provide built-in models
    return [];
  }

  @override
  DownloadStrategy? getDownloadStrategy() {
    // Return ONNX-specific download strategy
    _downloadStrategy ??= OnnxDownloadStrategy();
    return _downloadStrategy;
  }

  @override
  Future<dynamic> initializeComponent({
    required AdapterInitParameters parameters,
    required FrameworkModality modality,
  }) async {
    _ensureInitialized();

    final service = createService(modality);
    if (service != null && parameters.modelId != null) {
      await service.initialize(modelPath: parameters.modelId);
    }
    return service;
  }

  @override
  void onRegistration({int priority = 100}) {
    // Initialize the native backend
    _backend = NativeBackend();
    _backend!.create('onnx');
    _isInitialized = true;

    // Register all providers with ModuleRegistry
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
  }

  /// Dispose of resources
  void dispose() {
    // Cleanup cached services before nulling them to release backend resources
    _cachedSTTService?.cleanup();
    _cachedTTSService?.cleanup();
    _cachedVADService?.cleanup();
    _cachedLLMService?.cleanup();

    _cachedSTTService = null;
    _cachedTTSService = null;
    _cachedVADService = null;
    _cachedLLMService = null;

    // Dispose native backend
    if (_backend != null) {
      _backend!.dispose();
      _backend = null;
    }

    _isInitialized = false;
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  void _ensureInitialized() {
    if (!_isInitialized || _backend == null) {
      throw StateError(
        'OnnxAdapter not initialized. Call onRegistration() first or use OnnxBackend.initialize().',
      );
    }
  }

  void _cleanupStaleCache() {
    final now = DateTime.now();

    // Clean up STT service if not used recently
    if (_lastSTTUsage != null &&
        now.difference(_lastSTTUsage!) > _cacheTimeout) {
      _cachedSTTService = null;
      _lastSTTUsage = null;
    }

    // Clean up TTS service if not used recently
    if (_lastTTSUsage != null &&
        now.difference(_lastTTSUsage!) > _cacheTimeout) {
      _cachedTTSService = null;
      _lastTTSUsage = null;
    }

    // Clean up VAD service if not used recently
    if (_lastVADUsage != null &&
        now.difference(_lastVADUsage!) > _cacheTimeout) {
      _cachedVADService = null;
      _lastVADUsage = null;
    }

    // Clean up LLM service if not used recently
    if (_lastLLMUsage != null &&
        now.difference(_lastLLMUsage!) > _cacheTimeout) {
      _cachedLLMService = null;
      _lastLLMUsage = null;
    }
  }

  bool _modalityMatchesCategory(FrameworkModality modality, ModelInfo model) {
    switch (modality) {
      case FrameworkModality.voiceToText:
        return model.category.rawValue.contains('speech') ||
            model.category.rawValue.contains('recognition');
      case FrameworkModality.textToVoice:
        return model.category.rawValue.contains('synthesis') ||
            model.category.rawValue.contains('tts');
      case FrameworkModality.textToText:
        return model.category.rawValue.contains('language') ||
            model.category.rawValue.contains('text');
      case FrameworkModality.voiceActivityDetection:
        return model.category.rawValue.contains('vad') ||
            model.category.rawValue.contains('voice');
      default:
        return false;
    }
  }
}
