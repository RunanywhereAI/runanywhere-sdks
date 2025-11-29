import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// ModelManager (mirroring iOS ModelManager.swift)
///
/// Manages model loading/unloading and availability checks.
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

  /// Load a model by ID
  Future<void> loadModel(String modelId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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

  /// Unload the current model
  Future<void> unloadCurrentModel() async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Implement unload in SDK
      // await RunAnywhere.unloadModel();
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

  /// Check if a specific model is loaded
  bool isModelLoadedById(String modelId) {
    return _currentModelId == modelId;
  }

  /// Check if a model is downloaded
  bool isModelDownloaded(String modelName, String framework) {
    // TODO: Implement proper check via SDK
    return framework == 'foundationModels';
  }

  /// Refresh current model state
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
}
