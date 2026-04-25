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

  /// Load a model by ModelInfo (v4.0 API).
  Future<void> loadModel(ModelInfo modelInfo) async {
    _isLoading = true;
    notifyListeners();

    try {
      await RunAnywhereSDK.instance.llm.load(modelInfo.id);
    } catch (e) {
      _error = e;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Unload the current model (v4.0 API).
  Future<void> unloadCurrentModel() async {
    _isLoading = true;
    notifyListeners();

    try {
      await RunAnywhereSDK.instance.llm.unload();
    } catch (e) {
      _error = e;
      debugPrint('Failed to unload model: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get available models from SDK (v4.0 API).
  Future<List<ModelInfo>> getAvailableModels() async {
    try {
      return await RunAnywhereSDK.instance.models.available();
    } catch (e) {
      debugPrint('Failed to get available models: $e');
      return [];
    }
  }

  /// Get current LLM model (v4.0 API).
  Future<ModelInfo?> getCurrentModel() async {
    return RunAnywhereSDK.instance.llm.currentModel();
  }

  /// Refresh state (for UI notification purposes)
  Future<void> refresh() async {
    notifyListeners();
  }
}
