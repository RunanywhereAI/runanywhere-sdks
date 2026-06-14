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
      final sdkModels = await sdk.RunAnywhere.models.available();

      _availableModels = sdkModels;

      debugPrint(
          '✅ Loaded ${_availableModels.length} models from SDK registry');
      for (final model in _availableModels) {
        debugPrint(
            '  - ${model.name} (${model.category.displayName}) [${model.preferredFramework.displayName}] ready: ${model.isReadyOnDevice}');
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

      await for (final progress in sdk.RunAnywhere.downloads.start(model.id)) {
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

      await sdk.RunAnywhere.deleteModel(model.id);

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
        ModelCategory.MODEL_CATEGORY_LANGUAGE =>
          await sdk.RunAnywhere.llm.currentModel().then((m) => m?.id),
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION =>
          sdk.RunAnywhere.stt.currentModelId,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS =>
          sdk.RunAnywhere.tts.currentVoiceId,
        ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION =>
          sdk.RunAnywhere.vad.currentModelId,
        _ => await sdk.RunAnywhere.llm.currentModel().then((m) => m?.id),
      };

      if (alreadyLoadedId == model.id) {
        debugPrint('♻️ Model ${model.name} already loaded — skipping reload');
        _currentModel = model;
        return;
      }

      debugPrint('⏳ Loading model: ${model.name}');

      switch (model.category) {
        case ModelCategory.MODEL_CATEGORY_LANGUAGE:
          await sdk.RunAnywhere.llm.load(model.id);
          break;
        case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
          await sdk.RunAnywhere.stt.load(model.id);
          break;
        case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
          await sdk.RunAnywhere.tts.loadVoice(model.id);
          break;
        case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
          // Route VAD models through the VAD lifecycle (mirrors iOS, which
          // preloads with category .voiceActivityDetection). Falling through
          // to llm.load would load a 2 MB silero model as an LLM and fail.
          await sdk.RunAnywhere.vad.loadModel(model.id);
          break;
        default:
          // After the picker filters (model_types.dart), only contexts the
          // sheet already skips preload for (RAG, VLM/multimodal) reach
          // here; their views own the correct lifecycle call.
          await sdk.RunAnywhere.llm.load(model.id);
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

  /// Get models for a specific context (category + framework allow-list +
  /// supporting-file exclusion via the shared `includes` predicate).
  List<ModelInfo> modelsForContext(ModelSelectionContext context) {
    return _availableModels.where(context.includes).toList();
  }
}
