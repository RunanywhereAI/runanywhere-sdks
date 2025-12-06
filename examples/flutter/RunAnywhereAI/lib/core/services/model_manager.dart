import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// ModelManager (mirroring iOS ModelManager.swift)
///
/// Manages model loading/unloading and availability checks.
/// Service for managing model loading and lifecycle
class ModelManager extends ChangeNotifier {
  static final ModelManager shared = ModelManager._();

  ModelManager._();

  bool _isLoading = false;
  Object? _error;
  String? _currentModelId;
  ModelInfo? _currentModel;
  List<ModelInfo> _availableModels = [];

  bool get isLoading => _isLoading;
  Object? get error => _error;
  String? get currentModelId => _currentModelId;
  ModelInfo? get currentModel => _currentModel;
  List<ModelInfo> get availableModels => _availableModels;
  bool get isModelLoaded => _currentModel != null;
  String? get loadedModelName => _currentModel?.name;

  // MARK: - Model Operations

  /// Load a model by ID
  /// Matches iOS ModelManager.loadModel pattern
  Future<void> loadModel(String modelId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Use SDK's model loading with new API
      await RunAnywhere.loadModel(modelId);
      _currentModelId = modelId;
      _currentModel = RunAnywhere.currentModel;
      _error = null;
    } catch (e) {
      _error = e;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a model by ModelInfo
  /// Convenience method matching iOS pattern
  Future<void> loadModelInfo(ModelInfo modelInfo) async {
    await loadModel(modelInfo.id);
  }

  /// Unload the current model
  /// Matches iOS ModelManager.unloadCurrentModel pattern
  Future<void> unloadCurrentModel() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Use SDK's model unloading with new API
      await RunAnywhere.unloadModel();
      _currentModelId = null;
      _currentModel = null;
    } catch (e) {
      _error = e;
      debugPrint('Failed to unload model: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get available models from SDK
  /// Matches iOS ModelManager.getAvailableModels pattern
  Future<List<ModelInfo>> getAvailableModels() async {
    try {
      _availableModels = await RunAnywhere.availableModels();
      notifyListeners();
      return _availableModels;
    } catch (e) {
      debugPrint('Failed to get available models: $e');
      return [];
    }
  }

  /// Get current model from SDK
  /// Matches iOS ModelManager.getCurrentModel pattern
  ModelInfo? getCurrentModel() {
    // Use the SDK's public method to get the current model
    return RunAnywhere.currentModel;
  }

  /// Check if a specific model is loaded
  bool isModelLoadedById(String modelId) {
    return _currentModelId == modelId;
  }

  /// Check if a model is downloaded
  /// Checks the model's local path to determine if it's available
  bool isModelDownloaded(String modelId) {
    final model = _availableModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw StateError('Model not found'),
    );
    return model.isDownloaded;
  }

  /// Check if a model is downloaded by name and framework
  /// Legacy method for backwards compatibility
  bool isModelDownloadedByName(String modelName, String framework) {
    // Built-in models (e.g., Apple Foundation Models) are always available
    if (framework == 'foundationModels' || framework == 'FoundationModels') {
      return true;
    }

    // Check if any model matches the name and framework
    try {
      return _availableModels.any((model) =>
          model.name.toLowerCase() == modelName.toLowerCase() &&
          model.preferredFramework?.rawValue.toLowerCase() == framework.toLowerCase() &&
          model.isDownloaded);
    } catch (e) {
      return false;
    }
  }

  /// Refresh current model state
  /// Matches iOS ModelManager pattern
  Future<void> refresh() async {
    _currentModel = RunAnywhere.currentModel;
    _currentModelId = _currentModel?.id;
    await getAvailableModels();
    notifyListeners();
  }

  /// Set current model directly (for notification handling)
  void setCurrentModel(String? modelId) {
    _currentModelId = modelId;
    _currentModel = RunAnywhere.currentModel;
    notifyListeners();
  }

  /// Clear any error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Filter models by category
  List<ModelInfo> filterByCategory(String category) {
    return _availableModels.where((m) => m.category.rawValue == category).toList();
  }

  /// Get LLM models only
  List<ModelInfo> get llmModels {
    return _availableModels.where((m) => m.category.rawValue == 'language').toList();
  }

  /// Get STT models only
  List<ModelInfo> get sttModels {
    return _availableModels.where((m) => m.category.rawValue == 'speech-recognition').toList();
  }

  /// Get TTS models only
  List<ModelInfo> get ttsModels {
    return _availableModels.where((m) => m.category.rawValue == 'speech-synthesis').toList();
  }

  /// Get downloaded models only
  List<ModelInfo> get downloadedModels {
    return _availableModels.where((m) => m.isDownloaded).toList();
  }
}
