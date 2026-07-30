import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'package:runanywhere_ai/core/services/qhexrt_model_catalog.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';

/// ModelListViewModel (mirroring iOS ModelListViewModel.swift)
///
/// Manages model loading, selection, and state.
/// Now properly fetches models from the SDK registry and uses SDK for downloads.
class ModelListViewModel extends ChangeNotifier {
  static final ModelListViewModel shared = ModelListViewModel._();

  ModelListViewModel._() {
    unawaited(_initialize());
  }

  // State
  List<ModelInfo> _availableModels = [];
  List<LLMFramework> _availableFrameworks = [];
  ModelInfo? _currentModel;
  bool _isLoading = false;
  String? _errorMessage;

  // Download progress tracking
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloadingModels = {};

  // Getters
  List<ModelInfo> get availableModels => _availableModels;
  List<LLMFramework> get availableFrameworks => _availableFrameworks;
  ModelInfo? get currentModel => _currentModel;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, double> get downloadProgress =>
      Map.unmodifiable(_downloadProgress);
  bool isDownloading(String modelId) => _downloadingModels.contains(modelId);

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
      final sdkModels = await sdk.RunAnywhere.models.list();

      // Native device-aware QHexRT registration is authoritative. Older app
      // versions may have left generic logical HNPU rows in the persistent
      // registry; retain only the exact IDs returned by native registration.
      _availableModels = sdkModels
          .where(QHexRTModelCatalog.isVisibleForNativeCatalog)
          .toList(growable: false);

      debugPrint('Loaded ${_availableModels.length} models from SDK registry');
      for (final model in _availableModels) {
        debugPrint(
          '  - ${model.name} (${model.category.displayName}) [${model.backendFramework.displayName}] ready: ${model.isReadyOnDevice}',
        );
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

  /// Get available frameworks based on registered models
  Future<void> loadAvailableFrameworks() async {
    try {
      // Extract unique frameworks from available models
      final frameworks = <LLMFramework>{};
      for (final model in _availableModels) {
        frameworks.add(model.backendFramework);
        frameworks.addAll(model.compatibleFrameworks);
      }
      _availableFrameworks = frameworks.toList();
      debugPrint(
        'Available frameworks: ${_availableFrameworks.map((f) => f.displayName).join(", ")}',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load frameworks: $e');
      _availableFrameworks = [];
      notifyListeners();
    }
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
      debugPrint('Model ${model.name} selected and loaded');
    } catch (e) {
      _errorMessage = 'Failed to load model: $e';
      notifyListeners();
    }
  }

  /// Download a model using SDK DownloadService
  /// This is the proper implementation using the SDK's download functionality
  Future<void> downloadModel(
    ModelInfo model,
    void Function(double) progressHandler,
  ) async {
    if (_downloadingModels.contains(model.id)) {
      debugPrint('Model ${model.id} is already downloading');
      return;
    }

    _downloadingModels.add(model.id);
    _downloadProgress[model.id] = 0.0;
    notifyListeners();

    try {
      debugPrint('Starting download for model: ${model.name}');

      await for (final event in sdk.RunAnywhere.models.download(model.id)) {
        switch (event) {
          case sdk.DownloadProgressEvent(:final percent):
            _downloadProgress[model.id] = percent;
            progressHandler(percent);
            notifyListeners();
          case sdk.DownloadExtracting():
            debugPrint('Extracting model: ${model.name}');
          case sdk.DownloadCompleted():
            debugPrint('Download completed for model: ${model.name}');
        }
      }

      // Update model with local path after download
      await loadModelsFromRegistry();

      debugPrint('Model ${model.name} download complete');
    } catch (e) {
      debugPrint('Failed to download model ${model.id}: $e');
      _errorMessage = 'Download failed: $e';
    } finally {
      _downloadingModels.remove(model.id);
      _downloadProgress.remove(model.id);
      notifyListeners();
    }
  }

  /// Delete a downloaded model using SDK
  Future<void> deleteModel(ModelInfo model) async {
    try {
      debugPrint('Deleting model: ${model.name}');

      await sdk.RunAnywhere.models.delete(model.id);

      // Refresh models from registry
      await loadModelsFromRegistry();

      debugPrint('Model ${model.name} deleted successfully');
    } catch (e) {
      debugPrint('Failed to delete model: $e');
      _errorMessage = 'Failed to delete model: $e';
      notifyListeners();
    }
  }

  /// Load a model into memory using SDK
  Future<void> loadModel(ModelInfo model) async {
    _isLoading = true;
    notifyListeners();

    try {
      // B-FL-4-001: short-circuit if the SDK already has this exact
      // model loaded for the right capability. Re-calling load() each
      // time the user taps Send was triggering an unnecessary native
      // re-init for the same handle.
      final state = await sdk.RunAnywhere.models.state();
      if (state.loaded[model.category]?.id == model.id) {
        debugPrint('Model ${model.name} already loaded — skipping reload');
        _currentModel = model;
        return;
      }

      debugPrint('Loading model: ${model.name}');
      // One entry point: the SDK routes the id to the right component by
      // the model's own category.
      await sdk.RunAnywhere.models.load(model.id);

      _currentModel = model;
      debugPrint('Model ${model.name} loaded successfully');
    } catch (e) {
      debugPrint('Failed to load model ${model.id}: $e');
      _errorMessage = 'Failed to load model: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get models for a specific context (category + framework allow-list +
  /// supporting-file exclusion via the shared `includes` predicate).
  List<ModelInfo> modelsForContext(ModelSelectionContext context) {
    return _availableModels.where(context.includes).toList();
  }
}
