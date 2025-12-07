import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

import 'model_types.dart';

/// ModelListViewModel (mirroring iOS ModelListViewModel.swift)
///
/// Manages model loading, selection, and state.
/// Now properly fetches models from the SDK registry and uses SDK for downloads.
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
      // Get all models from SDK registry
      final sdkModels = await sdk.RunAnywhere.availableModels();

      // Convert SDK ModelInfo to app ModelInfo
      _availableModels =
          sdkModels.map((sdkModel) => _convertSDKModel(sdkModel)).toList();

      debugPrint(
          '✅ Loaded ${_availableModels.length} models from SDK registry');
      for (final model in _availableModels) {
        debugPrint(
            '  - ${model.name} (${model.category.displayName}) [${model.preferredFramework?.displayName ?? "Unknown"}] downloaded: ${model.isDownloaded}');
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

  /// Convert app LLMFramework to SDK LLMFramework
  sdk.LLMFramework _convertToSDKFramework(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return sdk.LLMFramework.llamaCpp;
      case LLMFramework.foundationModels:
        return sdk.LLMFramework.foundationModels;
      case LLMFramework.mediaPipe:
        return sdk.LLMFramework.mediaPipe;
      case LLMFramework.onnxRuntime:
        return sdk.LLMFramework.onnx;
      case LLMFramework.systemTTS:
        return sdk.LLMFramework.systemTTS;
      case LLMFramework.whisperKit:
        return sdk.LLMFramework.whisperKit;
      case LLMFramework.unknown:
        return sdk.LLMFramework.llamaCpp;
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

      // Get the download service from SDK
      final downloadService = sdk.RunAnywhere.serviceContainer.downloadService;

      // Find the SDK model by ID
      final sdkModels = await sdk.RunAnywhere.availableModels();
      final sdkModel = sdkModels.firstWhere(
        (m) => m.id == model.id,
        orElse: () =>
            throw Exception('Model not found in registry: ${model.id}'),
      );

      // Start download using SDK
      final downloadTask = await downloadService.downloadModel(sdkModel);

      // Listen to progress
      await for (final progress in downloadTask.progress) {
        final progressValue = progress.totalBytes > 0
            ? progress.bytesDownloaded / progress.totalBytes
            : 0.0;

        _downloadProgress[model.id] = progressValue;
        progressHandler(progressValue);
        notifyListeners();

        // Check if completed or failed
        if (progress.state.isCompleted) {
          debugPrint('✅ Download completed for model: ${model.name}');
          break;
        } else if (progress.state.isFailed) {
          throw Exception('Download failed');
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

      // Get the download service from SDK
      final downloadService = sdk.RunAnywhere.serviceContainer.downloadService;

      // Find the SDK model by ID
      final sdkModels = await sdk.RunAnywhere.availableModels();
      final sdkModel = sdkModels.firstWhere(
        (m) => m.id == model.id,
        orElse: () =>
            throw Exception('Model not found in registry: ${model.id}'),
      );

      // Delete using SDK
      await downloadService.deleteModel(sdkModel);

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
      debugPrint('⏳ Loading model: ${model.name}');

      // Use appropriate SDK method based on model category
      switch (model.category) {
        case ModelCategory.language:
          await sdk.RunAnywhere.loadModel(model.id);
          break;
        case ModelCategory.speechRecognition:
          await sdk.RunAnywhere.loadSTTModel(model.id);
          break;
        case ModelCategory.speechSynthesis:
          await sdk.RunAnywhere.loadTTSModel(model.id);
          break;
        default:
          // Default to LLM model loading
          await sdk.RunAnywhere.loadModel(model.id);
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
      await sdk.RunAnywhere.unloadModel();
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

      // Create a ModelRegistration
      final registration = sdk.ModelRegistration(
        url: url,
        framework: _convertToSDKFramework(framework),
        modality: sdk.FrameworkModality.textToText,
        name: name,
        memoryRequirement: estimatedSize ?? 500000000,
        supportsThinking: supportsThinking,
      );

      // Convert to ModelInfo and register with SDK's model registry
      final modelInfo = registration.toModelInfo();
      sdk.RunAnywhere.serviceContainer.modelRegistry.registerModel(modelInfo);

      debugPrint('✅ Registered model with SDK: ${modelInfo.name} (${modelInfo.id})');

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

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
