import 'dart:async';

import 'package:runanywhere/core/models/model/model_criteria.dart';
import 'package:runanywhere/core/models/model/model_info.dart';

/// Model registry protocol
/// Matches iOS ModelRegistry from Core/Protocols/Registry/ModelRegistry.swift
abstract class ModelRegistry {
  /// Discover available models
  Future<List<ModelInfo>> discoverModels();

  /// Register a model
  void registerModel(ModelInfo model);

  /// Get model by ID
  ModelInfo? getModel(String id);

  /// Filter models by criteria
  List<ModelInfo> filterModels(ModelCriteria criteria);

  /// Update model information
  void updateModel(ModelInfo model);

  /// Remove a model
  void removeModel(String id);
}
