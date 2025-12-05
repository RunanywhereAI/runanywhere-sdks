import '../../models/framework/framework_modality.dart';
import '../../models/framework/llm_framework.dart';
import '../../models/framework/model_format.dart';
import '../../models/model/model_info.dart';
import '../../models/hardware/hardware_configuration.dart';

/// Unified adapter interface for multi-modal AI framework backends.
///
/// This is the Flutter equivalent of Swift's `UnifiedFrameworkAdapter`.
/// Each backend (ONNX, llama.cpp, etc.) implements this interface to provide
/// pluggable AI capabilities.
///
/// ## Example Implementation
///
/// ```dart
/// class OnnxAdapter implements UnifiedFrameworkAdapter {
///   @override
///   LLMFramework get framework => LLMFramework.onnx;
///
///   @override
///   Set<FrameworkModality> get supportedModalities => {
///     FrameworkModality.voiceToText,
///     FrameworkModality.textToVoice,
///   };
///
///   @override
///   void onRegistration({int priority = 100}) {
///     ModuleRegistry.shared.registerSTT(OnnxSTTProvider(), priority: priority);
///   }
/// }
/// ```
abstract class UnifiedFrameworkAdapter {
  /// The framework this adapter provides.
  LLMFramework get framework;

  /// Supported modalities (STT, TTS, LLM, etc.).
  Set<FrameworkModality> get supportedModalities;

  /// Supported model formats (e.g., .onnx, .gguf).
  List<ModelFormat> get supportedFormats;

  /// Check if this adapter can handle a specific model.
  bool canHandle(ModelInfo model);

  /// Create a service for the given modality.
  ///
  /// Returns the appropriate service instance or null if not supported.
  dynamic createService(FrameworkModality modality);

  /// Load a model for the given modality.
  ///
  /// Returns the initialized service with the model loaded.
  Future<dynamic> loadModel(ModelInfo model, FrameworkModality modality);

  /// Configure the adapter with hardware settings.
  Future<void> configure(HardwareConfiguration hardware);

  /// Estimate memory usage for a model.
  int estimateMemoryUsage(ModelInfo model);

  /// Get optimal hardware configuration for a model.
  HardwareConfiguration optimalConfiguration(ModelInfo model);

  /// Called when adapter is registered with the SDK.
  ///
  /// This should register all service providers with ModuleRegistry.
  void onRegistration({int priority = 100});

  /// Get any pre-bundled models this adapter provides.
  List<ModelInfo> getProvidedModels();

  /// Cleanup and dispose of adapter resources.
  void dispose();
}

/// Mixin providing default implementations for optional adapter methods.
mixin UnifiedFrameworkAdapterDefaults implements UnifiedFrameworkAdapter {
  @override
  Future<void> configure(HardwareConfiguration hardware) async {
    // Default: no-op
  }

  @override
  int estimateMemoryUsage(ModelInfo model) {
    return model.memoryRequired ?? 0;
  }

  @override
  HardwareConfiguration optimalConfiguration(ModelInfo model) {
    return HardwareConfiguration();
  }

  @override
  List<ModelInfo> getProvidedModels() {
    return [];
  }

  @override
  void dispose() {
    // Default: no-op
  }
}
