import '../../../public/models/model_info.dart' as public;
import 'model_registry.dart' as protocol;

/// Model Registry Implementation
class ModelRegistryImpl implements protocol.ModelRegistry {
  final Map<String, public.ModelInfo> _models = {};

  @override
  Future<List<public.ModelInfo>> discoverModels() async {
    return _models.values.toList();
  }

  @override
  public.ModelInfo? getModel(String modelId) {
    return _models[modelId];
  }

  @override
  Future<void> registerModel(public.ModelInfo model) async {
    _models[model.id] = model;
  }
}
