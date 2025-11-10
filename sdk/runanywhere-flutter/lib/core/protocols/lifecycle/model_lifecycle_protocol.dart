/// Model Lifecycle Protocol
/// Similar to Swift SDK's ModelLifecycleProtocol
abstract class ModelLifecycleProtocol {
  /// Load model
  Future<void> loadModel(String modelId);

  /// Unload model
  Future<void> unloadModel(String modelId);

  /// Check if model is loaded
  bool isModelLoaded(String modelId);

  /// Get loaded model IDs
  List<String> getLoadedModelIds();
}

