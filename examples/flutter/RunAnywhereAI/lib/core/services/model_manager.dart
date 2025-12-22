import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// ModelManager (mirroring iOS ModelManager.swift)
///
/// Manages model loading/unloading and availability checks.
/// Service for managing model loading and lifecycle using RunAnywhere SDK.
/// Automatically listens to SDK events to stay in sync.
class ModelManager extends ChangeNotifier {
  static final ModelManager shared = ModelManager._();

  ModelManager._() {
    _setupEventListeners();
  }

  bool _isLoading = false;
  Object? _error;
  String? _currentModelId;
  ModelInfo? _currentModel;
  List<ModelInfo> _availableModels = [];
  // ignore: cancel_subscriptions, cancelled in dispose()
  StreamSubscription<SDKModelEvent>? _modelEventsSubscription;

  bool get isLoading => _isLoading;
  Object? get error => _error;
  String? get currentModelId => _currentModelId;
  ModelInfo? get currentModel => _currentModel;
  List<ModelInfo> get availableModels => _availableModels;
  bool get isModelLoaded => _currentModel != null;
  String? get loadedModelName => _currentModel?.name;

  /// Setup event listeners to automatically sync with SDK state
  void _setupEventListeners() {
    _modelEventsSubscription = RunAnywhere.events.modelEvents.listen((event) {
      if (event is SDKModelLoadStarted) {
        _handleModelLoadStarted(event.modelId);
      } else if (event is SDKModelLoadCompleted) {
        unawaited(_handleModelLoadCompleted(event.modelId));
      } else if (event is SDKModelLoadFailed) {
        _handleModelLoadFailed(event.modelId, event.error);
      } else if (event is SDKModelUnloadStarted) {
        _handleModelUnloadStarted(event.modelId);
      } else if (event is SDKModelUnloadCompleted) {
        _handleModelUnloadCompleted(event.modelId);
      }
    });
  }

  /// Handle model load started event from SDK
  void _handleModelLoadStarted(String modelId) {
    debugPrint('📡 SDK Event: Model load started: $modelId');
    _isLoading = true;
    _error = null;
    notifyListeners();
  }

  /// Handle model load completed event from SDK
  Future<void> _handleModelLoadCompleted(String modelId) async {
    debugPrint('📡 SDK Event: Model load completed: $modelId');
    // Refresh current model from SDK
    _currentModel = RunAnywhere.currentModel;
    _currentModelId = _currentModel?.id;
    _isLoading = false;
    _error = null;
    notifyListeners();
    debugPrint(
        '✅ ModelManager synced: isModelLoaded=$isModelLoaded, modelName=$loadedModelName');
  }

  /// Handle model load failed event from SDK
  void _handleModelLoadFailed(String modelId, Object error) {
    debugPrint('📡 SDK Event: Model load failed: $modelId - $error');
    _isLoading = false;
    _error = error;
    notifyListeners();
  }

  /// Handle model unload started event from SDK
  void _handleModelUnloadStarted(String modelId) {
    debugPrint('📡 SDK Event: Model unload started: $modelId');
    _isLoading = true;
    notifyListeners();
  }

  /// Handle model unload completed event from SDK
  void _handleModelUnloadCompleted(String modelId) {
    debugPrint('📡 SDK Event: Model unload completed: $modelId');
    _currentModel = null;
    _currentModelId = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
    debugPrint('✅ ModelManager synced: isModelLoaded=$isModelLoaded');
  }

  @override
  void dispose() {
    final subscription = _modelEventsSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  // MARK: - Model Operations

  /// Load a model by ID using SDK
  /// Matches iOS ModelManager.loadModel pattern
  Future<void> loadModel(String modelId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('⏳ Loading model: $modelId');

      // Use SDK's model loading with new API
      await RunAnywhere.loadModel(modelId);
      _currentModelId = modelId;
      _currentModel = RunAnywhere.currentModel;
      _error = null;

      debugPrint('✅ Model loaded successfully: ${_currentModel?.name}');
    } catch (e) {
      debugPrint('❌ Failed to load model: $e');
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

  /// Load an STT model by ID using SDK
  /// Matches iOS ModelManager pattern for STT models
  Future<void> loadSTTModel(String modelId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('⏳ Loading STT model: $modelId');

      // Use SDK's STT model loading
      await RunAnywhere.loadSTTModel(modelId);

      debugPrint('✅ STT model loaded successfully: $modelId');
    } catch (e) {
      debugPrint('❌ Failed to load STT model: $e');
      _error = e;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a TTS voice by ID using SDK
  /// Matches iOS ModelManager pattern for TTS models
  Future<void> loadTTSVoice(String voiceId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('⏳ Loading TTS voice: $voiceId');

      // Use SDK's TTS voice loading
      await RunAnywhere.loadTTSVoice(voiceId);

      debugPrint('✅ TTS voice loaded successfully: $voiceId');
    } catch (e) {
      debugPrint('❌ Failed to load TTS voice: $e');
      _error = e;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Unload the current model
  /// Matches iOS ModelManager.unloadCurrentModel pattern
  Future<void> unloadCurrentModel() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('⏳ Unloading current model...');

      // Use SDK's model unloading with new API
      await RunAnywhere.unloadModel();
      _currentModelId = null;
      _currentModel = null;

      debugPrint('✅ Model unloaded successfully');
    } catch (e) {
      debugPrint('❌ Failed to unload model: $e');
      _error = e;
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
      debugPrint('✅ Loaded ${_availableModels.length} available models');
      notifyListeners();
      return _availableModels;
    } catch (e) {
      debugPrint('❌ Failed to get available models: $e');
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
    try {
      final model = _availableModels.firstWhere(
        (m) => m.id == modelId,
        orElse: () => throw StateError('Model not found'),
      );
      return model.isDownloaded;
    } catch (e) {
      return false;
    }
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
          model.preferredFramework?.rawValue.toLowerCase() ==
              framework.toLowerCase() &&
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
    return _availableModels
        .where((m) => m.category.rawValue == category)
        .toList();
  }

  /// Get LLM models only
  List<ModelInfo> get llmModels {
    return _availableModels
        .where((m) => m.category == ModelCategory.language)
        .toList();
  }

  /// Get STT models only
  List<ModelInfo> get sttModels {
    return _availableModels
        .where((m) => m.category == ModelCategory.speechRecognition)
        .toList();
  }

  /// Get TTS models only
  List<ModelInfo> get ttsModels {
    return _availableModels
        .where((m) => m.category == ModelCategory.speechSynthesis)
        .toList();
  }

  /// Get downloaded models only
  List<ModelInfo> get downloadedModels {
    return _availableModels.where((m) => m.isDownloaded).toList();
  }

  /// Get loaded STT capability from SDK
  STTCapability? get loadedSTTCapability => RunAnywhere.loadedSTTCapability;

  /// Get loaded TTS capability from SDK
  TTSCapability? get loadedTTSCapability => RunAnywhere.loadedTTSCapability;

  /// Check if an STT model is loaded
  bool get isSTTModelLoaded => RunAnywhere.loadedSTTCapability != null;

  /// Check if a TTS model is loaded
  bool get isTTSModelLoaded => RunAnywhere.loadedTTSCapability != null;
}
