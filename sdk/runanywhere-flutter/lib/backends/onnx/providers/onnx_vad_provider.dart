import 'dart:async';

import '../../../core/module_registry.dart';
import '../../../native/native_backend.dart';
import '../services/onnx_vad_service.dart';

/// Provider for ONNX-based VAD service.
///
/// This is the Flutter equivalent of Swift's Silero VAD provider.
class OnnxVADServiceProvider implements VADServiceProvider {
  final NativeBackend _backend;

  /// Create a new ONNX VAD provider.
  OnnxVADServiceProvider(this._backend);

  @override
  String get name => 'ONNX Silero VAD';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();

    // Handle ONNX VAD models
    if (lower.endsWith('.onnx') && lower.contains('vad')) {
      return true;
    }

    // Handle Silero VAD
    if (lower.contains('silero')) {
      return true;
    }

    // Handle Sherpa VAD
    if (lower.contains('sherpa') && lower.contains('vad')) {
      return true;
    }

    return false;
  }

  @override
  Future<VADService> createVADService(dynamic configuration) async {
    final service = OnnxVADService(_backend);

    String? modelPath;
    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String?;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    await service.initialize(modelPath: modelPath);
    return service;
  }
}
