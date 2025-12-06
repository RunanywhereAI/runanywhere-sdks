import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'model_types.dart';

/// ModelListViewModel (mirroring iOS ModelListViewModel.swift)
///
/// Manages model loading, selection, and state.
/// Now properly fetches models from the SDK registry.
class ModelListViewModel extends ChangeNotifier {
  static final ModelListViewModel shared = ModelListViewModel._();

  ModelListViewModel._() {
    _initialize();
  }

  // State
  List<ModelInfo> _availableModels = [];
  List<LLMFramework> _availableFrameworks = [];
  ModelInfo? _currentModel;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<ModelInfo> get availableModels => _availableModels;
  List<LLMFramework> get availableFrameworks => _availableFrameworks;
  ModelInfo? get currentModel => _currentModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> _initialize() async {
    await loadModelsFromRegistry();
  }

  /// Load models from SDK registry
  /// Fetches all registered models from the RunAnywhere SDK
  Future<void> loadModelsFromRegistry() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get all models from SDK registry
      final sdkModels = await sdk.RunAnywhere.availableModels();

      // Convert SDK ModelInfo to app ModelInfo
      _availableModels =
          sdkModels.map((sdkModel) => _convertSDKModel(sdkModel)).toList();

      debugPrint(
          '✅ Loaded ${_availableModels.length} models from SDK registry');
      for (final model in _availableModels) {
        debugPrint(
            '  - ${model.name} (${model.category.displayName}) [${model.preferredFramework?.displayName ?? "Unknown"}]');
      }
    } catch (e) {
      debugPrint('❌ Failed to load models from SDK: $e');
      _errorMessage = 'Failed to load models: $e';
      _availableModels = [];
    }

    _currentModel = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Convert SDK ModelInfo to app ModelInfo
  ModelInfo _convertSDKModel(sdk.ModelInfo sdkModel) {
    return ModelInfo(
      id: sdkModel.id,
      name: sdkModel.name,
      category: _convertCategory(sdkModel.category),
      format: _convertFormat(sdkModel.format),
      downloadURL: sdkModel.downloadURL?.toString(),
      localPath: sdkModel.localPath?.toFilePath(),
      memoryRequired: sdkModel.memoryRequired,
      compatibleFrameworks: sdkModel.compatibleFrameworks
          .map((f) => _convertFramework(f))
          .toList(),
      preferredFramework: sdkModel.preferredFramework != null
          ? _convertFramework(sdkModel.preferredFramework!)
          : null,
      supportsThinking: sdkModel.supportsThinking,
    );
  }

  /// Convert SDK ModelCategory to app ModelCategory
  ModelCategory _convertCategory(sdk.ModelCategory sdkCategory) {
    switch (sdkCategory) {
      case sdk.ModelCategory.language:
        return ModelCategory.language;
      case sdk.ModelCategory.multimodal:
        return ModelCategory.multimodal;
      case sdk.ModelCategory.speechRecognition:
        return ModelCategory.speechRecognition;
      case sdk.ModelCategory.speechSynthesis:
        return ModelCategory.speechSynthesis;
      case sdk.ModelCategory.vision:
        return ModelCategory.vision;
      case sdk.ModelCategory.imageGeneration:
        return ModelCategory.imageGeneration;
      case sdk.ModelCategory.audio:
        return ModelCategory.audio;
      case sdk.ModelCategory.embedding:
        return ModelCategory.embedding;
    }
  }

  /// Convert SDK ModelFormat to app ModelFormat
  ModelFormat _convertFormat(sdk.ModelFormat sdkFormat) {
    switch (sdkFormat) {
      case sdk.ModelFormat.gguf:
        return ModelFormat.gguf;
      case sdk.ModelFormat.ggml:
        return ModelFormat.ggml;
      case sdk.ModelFormat.mlmodel:
      case sdk.ModelFormat.mlpackage:
        return ModelFormat.coreml;
      case sdk.ModelFormat.onnx:
      case sdk.ModelFormat.ort:
        return ModelFormat.onnx;
      case sdk.ModelFormat.tflite:
        return ModelFormat.tflite;
      case sdk.ModelFormat.bin:
        return ModelFormat.bin;
      default:
        return ModelFormat.unknown;
    }
  }

  /// Convert SDK LLMFramework to app LLMFramework
  LLMFramework _convertFramework(sdk.LLMFramework sdkFramework) {
    switch (sdkFramework) {
      case sdk.LLMFramework.llamaCpp:
        return LLMFramework.llamaCpp;
      case sdk.LLMFramework.foundationModels:
        return LLMFramework.foundationModels;
      case sdk.LLMFramework.mediaPipe:
        return LLMFramework.mediaPipe;
      case sdk.LLMFramework.onnx:
        return LLMFramework.onnxRuntime;
      case sdk.LLMFramework.systemTTS:
        return LLMFramework.systemTTS;
      case sdk.LLMFramework.whisperKit:
        return LLMFramework.whisperKit;
      default:
        return LLMFramework.unknown;
    }
  }

  /// Get available frameworks based on registered models
  Future<void> loadAvailableFrameworks() async {
    try {
      // Extract unique frameworks from available models
      final frameworks = <LLMFramework>{};
      for (final model in _availableModels) {
        if (model.preferredFramework != null) {
          frameworks.add(model.preferredFramework!);
        }
        frameworks.addAll(model.compatibleFrameworks);
      }
      _availableFrameworks = frameworks.toList();
      debugPrint(
          '✅ Available frameworks: ${_availableFrameworks.map((f) => f.displayName).join(", ")}');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Failed to load frameworks: $e');
      _availableFrameworks = [];
      notifyListeners();
    }
  }

  /// Alias for loadModelsFromRegistry
  Future<void> loadModels() async {
    await loadModelsFromRegistry();
    await loadAvailableFrameworks();
  }

  /// Set current model
  void setCurrentModel(ModelInfo? model) {
    _currentModel = model;
    notifyListeners();
  }

  /// Select and load a model
  Future<void> selectModel(ModelInfo model) async {
    try {
      await loadModel(model);
      setCurrentModel(model);

      // TODO: Post notification that model was loaded successfully
      // This would be handled by event bus in production
    } catch (e) {
      _errorMessage = 'Failed to load model: $e';
      notifyListeners();
    }
  }

  /// Download a model with progress
  Future<void> downloadModel(
    ModelInfo model,
    void Function(double) progressHandler,
  ) async {
    // TODO: Use RunAnywhere SDK to download model
    // await RunAnywhere.downloadModel(model.id);

    // Simulate download for demo
    for (int i = 0; i <= 100; i += 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      progressHandler(i / 100);
    }

    // Update model with local path after download
    final index = _availableModels.indexWhere((m) => m.id == model.id);
    if (index != -1) {
      _availableModels[index] = model.copyWith(
        localPath: '/models/${model.id}',
      );
      notifyListeners();
    }
  }

  /// Delete a downloaded model
  Future<void> deleteModel(ModelInfo model) async {
    // TODO: Use RunAnywhere SDK to delete model
    // await RunAnywhere.deleteModel(model.id);

    // Update model to remove local path
    final index = _availableModels.indexWhere((m) => m.id == model.id);
    if (index != -1) {
      _availableModels[index] = ModelInfo(
        id: model.id,
        name: model.name,
        category: model.category,
        format: model.format,
        downloadURL: model.downloadURL,
        localPath: null,
        memoryRequired: model.memoryRequired,
        compatibleFrameworks: model.compatibleFrameworks,
        preferredFramework: model.preferredFramework,
        supportsThinking: model.supportsThinking,
      );
      notifyListeners();
    }

    await loadModelsFromRegistry();
  }

  /// Load a model into memory
  Future<void> loadModel(ModelInfo model) async {
    // TODO: Use RunAnywhere SDK to load model
    // await RunAnywhere.loadModel(model.id);

    // Simulate loading for demo
    await Future.delayed(const Duration(seconds: 1));
    _currentModel = model;
    notifyListeners();
  }

  /// Add a custom model from URL
  Future<void> addModelFromURL({
    required String name,
    required String url,
    required LLMFramework framework,
    int? estimatedSize,
    bool supportsThinking = false,
  }) async {
    // TODO: Use SDK's addModelFromURL method
    // final model = await RunAnywhere.addModelFromURL(
    //   url,
    //   name: name,
    //   type: framework.rawValue,
    // );

    // Add placeholder model for demo
    final model = ModelInfo(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: ModelCategory.language,
      format: ModelFormat.gguf,
      downloadURL: url,
      memoryRequired: estimatedSize,
      compatibleFrameworks: [framework],
      preferredFramework: framework,
      supportsThinking: supportsThinking,
    );

    _availableModels.add(model);
    notifyListeners();
  }

  /// Add an imported model
  Future<void> addImportedModel(ModelInfo model) async {
    await loadModelsFromRegistry();
  }

  /// Get models for a specific framework
  List<ModelInfo> modelsForFramework(LLMFramework framework) {
    return _availableModels.where((model) {
      if (framework == LLMFramework.foundationModels) {
        return model.preferredFramework == LLMFramework.foundationModels;
      }
      return model.compatibleFrameworks.contains(framework);
    }).toList();
  }

  /// Get models for a specific context
  List<ModelInfo> modelsForContext(ModelSelectionContext context) {
    return _availableModels.where((model) {
      return context.relevantCategories.contains(model.category);
    }).toList();
  }
}
