import '../protocols/frameworks/unified_framework_adapter.dart';
import '../models/framework/framework_modality.dart';
import '../models/model/model_info.dart';

/// Unified Service Registry
/// Similar to Swift SDK's UnifiedServiceRegistry
class UnifiedServiceRegistry {
  final Map<UnifiedFrameworkAdapter, int> _adapters = {};

  /// Register a framework adapter
  void registerAdapter(UnifiedFrameworkAdapter adapter, {int priority = 100}) {
    _adapters[adapter] = priority;
  }

  /// Find all adapters for a model and modality
  Future<List<UnifiedFrameworkAdapter>> findAllAdapters(
    ModelInfo model,
    FrameworkModality modality,
  ) async {
    // TODO: Implement adapter selection logic
    return [];
  }
}

