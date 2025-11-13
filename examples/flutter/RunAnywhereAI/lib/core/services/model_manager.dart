import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

/// Model Manager - Manages current model state
class ModelManager extends ChangeNotifier {
  static final ModelManager shared = ModelManager._();

  ModelManager._();

  String? currentModelId;
  ModelInfo? _currentModel;

  ModelInfo? get currentModel => _currentModel;

  void setCurrentModel(String? modelId) {
    currentModelId = modelId;
    _currentModel = RunAnywhere.currentModel;
    notifyListeners();
  }

  Future<void> loadModel(String modelId) async {
    try {
      await RunAnywhere.loadModel(modelId);
      setCurrentModel(modelId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refresh() async {
    _currentModel = RunAnywhere.currentModel;
    notifyListeners();
  }
}

