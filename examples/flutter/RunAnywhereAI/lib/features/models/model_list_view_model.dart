import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

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
      final sdkModels = await sdk.RunAnywhereSDK.instance.models.available();

      _availableModels = sdkModels;

      debugPrint(
          '✅ Loaded ${_availableModels.length} models from SDK registry');
      for (final model in _availableModels) {
        debugPrint(
            '  - ${model.name} (${model.category.displayName}) [${model.preferredFramework.displayName}] downloaded: ${model.isDownloaded}');
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

  /// Get available frameworks based on registered models
  Future<void> loadAvailableFrameworks() async {
    try {
      // Extract unique frameworks from available models
      final frameworks = <LLMFramework>{};
      for (final model in _availableModels) {
        frameworks.add(model.preferredFramework);
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
      debugPrint('✅ Model ${model.name} selected and loaded');
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
      debugPrint('⚠️ Model ${model.id} is already downloading');
      return;
    }

    _downloadingModels.add(model.id);
    _downloadProgress[model.id] = 0.0;
    notifyListeners();

    try {
      debugPrint('📥 Starting download for model: ${model.name}');

      await for (final progress
          in sdk.RunAnywhereSDK.instance.downloads.start(model.id)) {
        final totalBytes = progress.totalBytes.toInt();
        final progressValue = totalBytes > 0
            ? progress.bytesDownloaded.toInt() / totalBytes
            : progress.stageProgress.toDouble();

        _downloadProgress[model.id] = progressValue;
        progressHandler(progressValue);
        notifyListeners();

        // Check if completed or failed
        if (progress.stage == sdk.DownloadStage.DOWNLOAD_STAGE_COMPLETED) {
          debugPrint('✅ Download completed for model: ${model.name}');
          break;
        } else if (progress.stage ==
                sdk.DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED &&
            progress.errorMessage.isNotEmpty) {
          throw Exception('Download failed: ${progress.errorMessage}');
        }
      }

      // Update model with local path after download
      await loadModelsFromRegistry();

      debugPrint('✅ Model ${model.name} download complete');
    } catch (e) {
      debugPrint('❌ Failed to download model ${model.id}: $e');
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
      debugPrint('🗑️ Deleting model: ${model.name}');

      await sdk.RunAnywhereSDK.instance.downloads.delete(model.id);

      // Refresh models from registry
      await loadModelsFromRegistry();

      debugPrint('✅ Model ${model.name} deleted successfully');
    } catch (e) {
      debugPrint('❌ Failed to delete model: $e');
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
      final alreadyLoadedId = switch (model.category) {
        ModelCategory.MODEL_CATEGORY_LANGUAGE => await sdk
            .RunAnywhereSDK.instance.llm
            .currentModel()
            .then((m) => m?.id),
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION =>
          sdk.RunAnywhereSDK.instance.stt.currentModelId,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS =>
          sdk.RunAnywhereSDK.instance.tts.currentVoiceId,
        _ => await sdk.RunAnywhereSDK.instance.llm
            .currentModel()
            .then((m) => m?.id),
      };

      if (alreadyLoadedId == model.id) {
        debugPrint('♻️ Model ${model.name} already loaded — skipping reload');
        _currentModel = model;
        return;
      }

      debugPrint('⏳ Loading model: ${model.name}');

      switch (model.category) {
        case ModelCategory.MODEL_CATEGORY_LANGUAGE:
          await sdk.RunAnywhereSDK.instance.llm.load(model.id);
          break;
        case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
          await sdk.RunAnywhereSDK.instance.stt.load(model.id);
          break;
        case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
          await sdk.RunAnywhereSDK.instance.tts.loadVoice(model.id);
          break;
        default:
          await sdk.RunAnywhereSDK.instance.llm.load(model.id);
      }

      _currentModel = model;
      debugPrint('✅ Model ${model.name} loaded successfully');
    } catch (e) {
      debugPrint('❌ Failed to load model ${model.id}: $e');
      _errorMessage = 'Failed to load model: $e';
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Unload the current model
  Future<void> unloadCurrentModel() async {
    if (_currentModel == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await sdk.RunAnywhereSDK.instance.llm.unload();
      _currentModel = null;
      debugPrint('✅ Model unloaded successfully');
    } catch (e) {
      debugPrint('❌ Failed to unload model: $e');
      _errorMessage = 'Failed to unload model: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a custom model from URL using SDK
  Future<void> addModelFromURL({
    required String name,
    required String url,
    required LLMFramework framework,
    int? estimatedSize,
    bool supportsThinking = false,
  }) async {
    try {
      debugPrint('➕ Adding model from URL: $name');

      final modelInfo = sdk.RunAnywhereSDK.instance.models.register(
        name: name,
        url: Uri.parse(url),
        framework: framework,
        modality: sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
        supportsThinking: supportsThinking,
      );

      debugPrint(
          '✅ Registered model with SDK: ${modelInfo.name} (${modelInfo.id})');

      // Refresh models from registry
      await loadModelsFromRegistry();

      debugPrint('✅ Model $name added successfully');
    } catch (e) {
      debugPrint('❌ Failed to add model from URL: $e');
      _errorMessage = 'Failed to add model: $e';
      notifyListeners();
    }
  }

  /// Add an imported model
  Future<void> addImportedModel(ModelInfo model) async {
    await loadModelsFromRegistry();
  }

  /// Get models for a specific framework
  List<ModelInfo> modelsForFramework(LLMFramework framework) {
    return _availableModels.where((model) {
      if (framework == LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS) {
        return model.preferredFramework ==
            LLMFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
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

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
