import 'dart:async';
import '../../foundation/logging/sdk_logger.dart';
import '../../core/models/common.dart';
import '../../core/protocols/registry/model_registry.dart';

// Re-export for backward compatibility
export '../../core/protocols/registry/model_registry.dart';

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
  ModelInfo? getModel(String id) {
    return _models[id];
  }

  /// Get model (async for backward compatibility)
  Future<ModelInfo?> getModelAsync({required String by}) async {
    return _models[by];
  }

  @override
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

  @override
  void updateModel(ModelInfo model) {
    if (_models.containsKey(model.id)) {
      _models[model.id] = model;
      logger.info('Updated model: ${model.id}');
    }
  }

  @override
  void removeModel(String id) {
    _models.remove(id);
    logger.info('Removed model: $id');
  }

  @override
  List<ModelInfo> filterModels(ModelCriteria criteria) {
    if (!criteria.hasFilters) {
      return List.from(_models.values);
    }

    return _models.values.where((model) {
      // Framework filter
      if (criteria.framework != null &&
          !model.compatibleFrameworks.contains(criteria.framework)) {
        return false;
      }

      // Format filter
      if (criteria.format != null && model.format != criteria.format) {
        return false;
      }

      // Size filter
      if (criteria.maxSize != null &&
          model.downloadSize != null &&
          model.downloadSize! > criteria.maxSize!) {
        return false;
      }

      // Context length filters
      if (criteria.minContextLength != null &&
          model.contextLength != null &&
          model.contextLength! < criteria.minContextLength!) {
        return false;
      }
      if (criteria.maxContextLength != null &&
          model.contextLength != null &&
          model.contextLength! > criteria.maxContextLength!) {
        return false;
      }

      // Search filter (name contains search term)
      if (criteria.search != null &&
          !model.name.toLowerCase().contains(criteria.search!.toLowerCase())) {
        return false;
      }

      return true;
    }).toList();
  }
}
