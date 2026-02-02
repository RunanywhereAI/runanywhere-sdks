import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// ModelManager (matching iOS ModelManager.swift exactly)
///
/// Service for managing model loading and lifecycle.
/// This is a minimal wrapper that delegates to RunAnywhere SDK.
/// Each feature view (Chat, STT, TTS) manages its own state.
class ModelManager extends ChangeNotifier {
  static final ModelManager shared = ModelManager._();

  ModelManager._();

  bool _isLoading = false;
  Object? _error;

  bool get isLoading => _isLoading;
  Object? get error => _error;

  // ============================================================================
  // MARK: - Model Operations (matches Swift ModelManager.swift)
  // ============================================================================

  /// Load a model by ModelInfo
  Future<void> loadModel(ModelInfo modelInfo) async {
    _isLoading = true;
    notifyListeners();

    try {
      await RunAnywhere.loadModel(modelInfo.id);
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
      await RunAnywhere.unloadModel();
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
      return await RunAnywhere.availableModels();
    } catch (e) {
      debugPrint('Failed to get available models: $e');
      return [];
    }
  }

  /// Get current model (LLM)
  Future<ModelInfo?> getCurrentModel() async {
    final modelId = RunAnywhere.currentModelId;
    if (modelId == null) return null;

    final models = await getAvailableModels();
    return models.where((m) => m.id == modelId).firstOrNull;
  }

  /// Refresh state (for UI notification purposes)
  Future<void> refresh() async {
    notifyListeners();
  }
}
