import '../../../public/models/model_info.dart';

/// Model Registry Protocol
/// Similar to Swift SDK's ModelRegistry
abstract class ModelRegistry {
  /// Discover all available models
  Future<List<ModelInfo>> discoverModels();

  /// Get a model by ID
  ModelInfo? getModel(String modelId);

  /// Register a model
  Future<void> registerModel(ModelInfo model);
}

