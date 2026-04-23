// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_models.dart — v4.0 Models capability instance API.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// Model registry / availability surface.
///
/// Access via `RunAnywhere.instance.models`.
class RunAnywhereModels {
  RunAnywhereModels._();
  static final RunAnywhereModels _instance = RunAnywhereModels._();
  static RunAnywhereModels get shared => _instance;

  /// All available models from the registry (cache + remote).
  Future<List<ModelInfo>> available() => legacy.RunAnywhere.availableModels();

  /// Refresh the model registry from the remote backend.
  Future<void> refresh() => legacy.RunAnywhere.refreshDiscoveredModels();
}
