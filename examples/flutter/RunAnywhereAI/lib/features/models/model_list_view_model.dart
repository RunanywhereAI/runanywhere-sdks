import 'package:flutter/foundation.dart';
// ignore: unused_import
import 'package:runanywhere/runanywhere.dart' hide ModelInfo, LLMFramework, ModelCategory;

import 'model_types.dart';

/// ModelListViewModel (mirroring iOS ModelListViewModel.swift)
///
/// Manages model loading, selection, and state.
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
  Future<void> loadModelsFromRegistry() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: Get all models from SDK registry
      // This should include:
      // 1. Models from remote configuration
      // 2. Models from framework adapters
      // 3. Models from local storage
      // 4. User-added models
      // final allModels = await RunAnywhere.availableModels();

      // Placeholder models for demo
      _availableModels = [
        ModelInfo(
          id: 'llama-3.2-1b',
          name: 'Llama 3.2 1B',
          category: ModelCategory.language,
          format: ModelFormat.gguf,
          downloadURL: 'https://example.com/llama-3.2-1b.gguf',
          memoryRequired: 1000000000,
          compatibleFrameworks: [LLMFramework.llamaCpp],
          preferredFramework: LLMFramework.llamaCpp,
        ),
        ModelInfo(
          id: 'llama-3.2-3b',
          name: 'Llama 3.2 3B',
          category: ModelCategory.language,
          format: ModelFormat.gguf,
          downloadURL: 'https://example.com/llama-3.2-3b.gguf',
          memoryRequired: 3000000000,
          compatibleFrameworks: [LLMFramework.llamaCpp],
          preferredFramework: LLMFramework.llamaCpp,
        ),
        ModelInfo(
          id: 'whisper-base',
          name: 'Whisper Base',
          category: ModelCategory.speechRecognition,
          format: ModelFormat.coreml,
          downloadURL: 'https://example.com/whisper-base.zip',
          memoryRequired: 150000000,
          compatibleFrameworks: [LLMFramework.whisperKit],
          preferredFramework: LLMFramework.whisperKit,
        ),
        ModelInfo(
          id: 'whisper-small',
          name: 'Whisper Small',
          category: ModelCategory.speechRecognition,
          format: ModelFormat.coreml,
          downloadURL: 'https://example.com/whisper-small.zip',
          memoryRequired: 500000000,
          compatibleFrameworks: [LLMFramework.whisperKit],
          preferredFramework: LLMFramework.whisperKit,
        ),
      ];

      debugPrint('Loaded ${_availableModels.length} models from registry');
      for (final model in _availableModels) {
        debugPrint(
            '  - ${model.name} (${model.preferredFramework?.displayName ?? "Unknown"})');
      }
    } catch (e) {
      debugPrint('Failed to load models from SDK: $e');
      _errorMessage = 'Failed to load models: $e';
      _availableModels = [];
    }

    _currentModel = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Get available frameworks
  Future<void> loadAvailableFrameworks() async {
    try {
      // TODO: Get from SDK
      // final frameworks = RunAnywhere.getAvailableFrameworks();
      _availableFrameworks = [
        LLMFramework.llamaCpp,
        LLMFramework.whisperKit,
        LLMFramework.mediaPipe,
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load frameworks: $e');
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
