import 'dart:async';
import 'dart:io';

import 'diffusion_types.dart';
import 'native/diffusion_bindings.dart';

/// Diffusion module for image generation using Stable Diffusion models.
///
/// iOS only (CoreML/ANE). On Android, methods throw [DiffusionException].
class Diffusion {
  static final Diffusion _instance = Diffusion._internal();

  /// Shared instance
  static Diffusion get module => _instance;

  Diffusion._internal();

  /// Module identifier
  static const String moduleId = 'diffusion';

  /// Human-readable module name
  static const String moduleName = 'Diffusion';

  /// Capabilities provided by this module
  static const List<String> capabilities = ['image-generation'];

  /// True only on iOS/macOS. On Android, diffusion is not supported.
  static bool get isSupported => Platform.isIOS || Platform.isMacOS;

  DiffusionConfiguration? _currentConfig;
  String? _loadedModelId;
  DiffusionBindings? _bindings;

  /// Lazy: only created on iOS/macOS when first needed.
  DiffusionBindings get _bindingsInstance {
    Diffusion._throwIfUnsupported();
    return _bindings ??= DiffusionBindings();
  }

  static void _throwIfUnsupported() {
    if (!isSupported) {
      throw DiffusionException(
        'Diffusion is only supported on iOS/macOS (CoreML/ANE). It is not available on Android.',
      );
    }
  }

  /// Register the Diffusion backend with the SDK
  static Future<void> register({int priority = 100}) async {
    _throwIfUnsupported();
    final result = _instance._bindingsInstance.register();
    if (result != 0) {
      throw DiffusionException('Failed to register Diffusion backend: $result');
    }
  }

  /// Unregister the Diffusion backend
  static Future<void> unregister() async {
    if (!isSupported) return;
    _instance._bindingsInstance.unregister();
  }

  /// Check if a model is loaded
  bool get isModelLoaded => _loadedModelId != null;

  /// Get the currently loaded model ID
  String? get loadedModelId => _loadedModelId;

  /// Get the current configuration
  DiffusionConfiguration? get currentConfig => _currentConfig;

  /// Configure the diffusion component
  Future<void> configure(DiffusionConfiguration config) async {
    Diffusion._throwIfUnsupported();
    final result = _bindingsInstance.configure(
      modelId: config.modelId,
      preferredFramework: config.preferredFramework?.rawValue,
      modelVariant: config.modelVariant.cValue,
      enableSafetyChecker: config.enableSafetyChecker,
      reduceMemory: config.reduceMemory,
      tokenizerSource: config.effectiveTokenizerSource.cValue,
      tokenizerCustomURL: config.tokenizerSource is CustomTokenizerSource
          ? (config.tokenizerSource as CustomTokenizerSource).customBaseURL
          : null,
    );
    if (result != 0) {
      throw DiffusionException('Failed to configure diffusion: $result');
    }
    _currentConfig = config;
  }

  /// Load a diffusion model
  Future<void> loadModel({
    required String path,
    required String modelId,
    String? modelName,
  }) async {
    Diffusion._throwIfUnsupported();
    final result = _bindingsInstance.loadModel(
      path: path,
      modelId: modelId,
      modelName: modelName,
    );
    if (result != 0) {
      throw DiffusionException('Failed to load model: $result');
    }
    _loadedModelId = modelId;
  }

  /// Unload the current model
  Future<void> unloadModel() async {
    if (!Diffusion.isSupported) return;
    _bindingsInstance.unloadModel();
    _loadedModelId = null;
  }

  /// Generate an image from a text prompt
  Future<DiffusionResult> generateImage(
    DiffusionGenerationOptions options,
  ) async {
    Diffusion._throwIfUnsupported();
    if (!isModelLoaded) {
      throw DiffusionException('No model loaded');
    }

    final result = await _bindingsInstance.generate(options);
    return result;
  }

  /// Generate an image with progress updates
  Stream<DiffusionProgress> generateImageWithProgress(
    DiffusionGenerationOptions options,
  ) async* {
    Diffusion._throwIfUnsupported();
    if (!isModelLoaded) {
      throw DiffusionException('No model loaded');
    }

    // TODO: Implement streaming progress from native
    throw UnimplementedError('Progress streaming not yet implemented');
  }

  /// Cancel ongoing generation
  Future<void> cancel() async {
    if (!Diffusion.isSupported) return;
    _bindingsInstance.cancel();
  }

  /// Simple text-to-image generation
  Future<DiffusionResult> textToImage(
    String prompt, {
    String negativePrompt = '',
    int? width,
    int? height,
    int? steps,
    int seed = -1,
  }) async {
    final variant = _currentConfig?.modelVariant ?? DiffusionModelVariant.sd15;
    final options = DiffusionGenerationOptions.textToImage(
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width ?? variant.defaultWidth,
      height: height ?? variant.defaultHeight,
      steps: steps ?? variant.defaultSteps,
      seed: seed,
    );
    return generateImage(options);
  }

  /// Add a model to the model registry
  static void addModel({
    required String name,
    required String url,
    DiffusionModelVariant? variant,
    int? memoryRequirement,
  }) {
    // This would integrate with the core model registry
    // For now, we just validate the options
    if (name.isEmpty || url.isEmpty) {
      throw ArgumentError('Model name and URL are required');
    }
  }
}

/// Exception thrown by Diffusion operations
class DiffusionException implements Exception {
  final String message;
  final int? errorCode;

  DiffusionException(this.message, {this.errorCode});

  @override
  String toString() =>
      errorCode != null ? 'DiffusionException: $message (code: $errorCode)' : 'DiffusionException: $message';
}
