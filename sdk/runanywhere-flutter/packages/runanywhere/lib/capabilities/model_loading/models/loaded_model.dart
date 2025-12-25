import 'package:runanywhere/core/models/common.dart';
import 'package:runanywhere/core/module_registry.dart';

/// Represents a model that has been loaded and is ready for use
class LoadedModel {
  /// The model information
  final ModelInfo model;

  /// The service that can execute this model
  final LLMService service;

  LoadedModel({
    required this.model,
    required this.service,
  });
}
