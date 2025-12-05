import '../../core/models/framework/framework_modality.dart';
import '../../core/models/framework/llm_framework.dart';
import '../../core/models/framework/model_format.dart';
import '../../core/models/model/model_info.dart';
import '../../core/module_registry.dart';
import '../../core/protocols/frameworks/unified_framework_adapter.dart';
import '../native/native_backend.dart';
import 'providers/llamacpp_llm_provider.dart';
import 'services/llamacpp_llm_service.dart';

/// LlamaCpp adapter for LLM (Language Model) inference.
///
/// This is the Flutter equivalent of Swift's `LLMSwiftAdapter`.
/// It provides LLM capabilities through the native runanywhere-core library.
///
/// ## Usage
///
/// The adapter is typically used internally by [LlamaCppBackend.initialize()],
/// but can also be used directly for advanced scenarios:
///
/// ```dart
/// final adapter = LlamaCppAdapter();
/// adapter.onRegistration(priority: 90);
///
/// // Create a service directly
/// final llm = adapter.createService(FrameworkModality.textToText);
/// ```
class LlamaCppAdapter
    with UnifiedFrameworkAdapterDefaults
    implements UnifiedFrameworkAdapter {
  NativeBackend? _backend;
  bool _isInitialized = false;

  // Cache service instance
  LlamaCppLLMService? _cachedLLMService;
  DateTime? _lastLLMUsage;
  final Duration _cacheTimeout = const Duration(minutes: 5);

  /// Supported quantization levels for GGUF models.
  static const List<String> supportedQuantizations = [
    'Q2_K',
    'Q3_K_S',
    'Q3_K_M',
    'Q3_K_L',
    'Q4_0',
    'Q4_1',
    'Q4_K_S',
    'Q4_K_M',
    'Q5_0',
    'Q5_1',
    'Q5_K_S',
    'Q5_K_M',
    'Q6_K',
    'Q8_0',
    'IQ2_XXS',
    'IQ2_XS',
    'IQ3_S',
    'IQ3_XXS',
    'IQ4_NL',
    'IQ4_XS',
  ];

  /// Create a new LlamaCpp adapter.
  LlamaCppAdapter();

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
  LLMFramework get framework => LLMFramework.llamaCpp;

  @override
  Set<FrameworkModality> get supportedModalities => {
        FrameworkModality.textToText,
      };

  @override
  List<ModelFormat> get supportedFormats =>
      [ModelFormat.gguf, ModelFormat.ggml];

  @override
  bool canHandle(ModelInfo model) {
    // Check format support
    if (!supportedFormats.contains(model.format)) {
      return false;
    }

    // Check quantization compatibility if metadata is available
    if (model.metadata?.quantizationLevel != null) {
      final quantization = model.metadata!.quantizationLevel!.rawValue;
      if (!supportedQuantizations.contains(quantization)) {
        return false;
      }
    }

    return true;
  }

  @override
  dynamic createService(FrameworkModality modality) {
    _ensureInitialized();
    _cleanupStaleCache();

    if (modality != FrameworkModality.textToText) {
      return null;
    }

    if (_cachedLLMService != null) {
      _lastLLMUsage = DateTime.now();
      return _cachedLLMService;
    }

    final service = LlamaCppLLMService(_backend!);
    _cachedLLMService = service;
    _lastLLMUsage = DateTime.now();
    return service;
  }

  @override
  Future<dynamic> loadModel(ModelInfo model, FrameworkModality modality) async {
    _ensureInitialized();
    _cleanupStaleCache();

    if (modality != FrameworkModality.textToText) {
      throw ArgumentError('Unsupported modality: $modality');
    }

    final modelPath = model.localPath?.toFilePath();

    final service = _cachedLLMService ?? LlamaCppLLMService(_backend!);
    await service.initialize(modelPath: modelPath);
    _cachedLLMService = service;
    _lastLLMUsage = DateTime.now();
    return service;
  }

  @override
  int estimateMemoryUsage(ModelInfo model) {
    // GGUF models use approximately their file size in memory
    // Add 20% overhead for context and processing
    final baseSize = model.memoryRequired ?? 0;
    final overhead = (baseSize * 0.2).toInt();
    return baseSize + overhead;
  }

  @override
  void onRegistration({int priority = 90}) {
    // Initialize the native backend with llamacpp
    _backend = NativeBackend();

    // Note: For llamacpp, we might need a different backend name
    // or the same 'onnx' backend with different configuration
    // For now, we use the same backend but the service will handle
    // loading GGUF models through the native API
    _backend!.create('onnx'); // Uses the same native backend

    _isInitialized = true;

    // Register LLM provider with ModuleRegistry
    final registry = ModuleRegistry.shared;

    registry.registerLLM(
      LlamaCppLLMServiceProvider(_backend!),
      priority: priority,
    );
  }

  @override
  void dispose() {
    // Cleanup cached service
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
        'LlamaCppAdapter not initialized. Call onRegistration() first or use LlamaCppBackend.initialize().',
      );
    }
  }

  void _cleanupStaleCache() {
    final now = DateTime.now();

    if (_lastLLMUsage != null &&
        now.difference(_lastLLMUsage!) > _cacheTimeout) {
      _cachedLLMService = null;
      _lastLLMUsage = null;
    }
  }
}
