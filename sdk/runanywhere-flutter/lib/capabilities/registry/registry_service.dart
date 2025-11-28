import 'dart:async';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/models/common.dart';

/// Implementation of model registry
class RegistryService implements ModelRegistry {
  final Map<String, ModelInfo> _models = {};
  final SDKLogger logger = SDKLogger(category: 'RegistryService');

  RegistryService() {
    logger.debug('Initializing RegistryService');
  }

  /// Initialize registry with configuration
  Future<void> initialize({String? apiKey}) async {
    logger.info('Initializing registry with configuration');

    // Load pre-configured models
    await loadPreconfiguredModels();

    logger.info('Registry initialization complete');
  }

  /// Load pre-configured models
  Future<void> loadPreconfiguredModels() async {
    // Placeholder - models will be registered via registerModel
    logger.debug('Pre-configured models loaded');
  }

  @override
  Future<List<ModelInfo>> discoverModels() async {
    return List.from(_models.values);
  }

  @override
  Future<ModelInfo?> getModel({required String by}) async {
    return _models[by];
  }

  /// Register a model
  void registerModel(ModelInfo model) {
    // Validate model before registering
    if (model.id.isEmpty) {
      logger.error('Attempted to register model with empty ID');
      return;
    }

    logger.debug('Registering model: ${model.id} - ${model.name}');
    _models[model.id] = model;
    logger.info('Successfully registered model: ${model.id}');
  }

  /// Register model and save to database for persistence
  Future<void> registerModelPersistently(ModelInfo model) async {
    registerModel(model);
    // TODO: Save to database
  }

  /// Update an existing model
  void updateModel(ModelInfo model) {
    if (_models.containsKey(model.id)) {
      _models[model.id] = model;
      logger.info('Updated model: ${model.id}');
    }
  }

  /// Remove a model from registry
  void removeModel(String modelId) {
    _models.remove(modelId);
    logger.info('Removed model: $modelId');
  }
}

/// Model registry interface
abstract class ModelRegistry {
  Future<void> initialize({String? apiKey});
  Future<List<ModelInfo>> discoverModels();
  Future<ModelInfo?> getModel({required String by});
}

