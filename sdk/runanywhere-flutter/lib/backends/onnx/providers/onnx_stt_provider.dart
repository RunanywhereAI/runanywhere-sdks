import '../../../core/module_registry.dart';
import '../../../native/native_backend.dart';
import '../services/onnx_stt_service.dart';

/// Provider for ONNX-based STT service.
///
/// This is the Flutter equivalent of Swift's `ONNXSTTServiceProvider`.
class OnnxSTTServiceProvider implements STTServiceProvider {
  final NativeBackend _backend;

  /// Create a new ONNX STT provider.
  OnnxSTTServiceProvider(this._backend);

  @override
  String get name => 'ONNX Runtime';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();

    // Handle ONNX models
    if (lower.endsWith('.onnx') || lower.contains('onnx')) {
      return true;
    }

    // Handle Sherpa-ONNX models
    if (lower.contains('zipformer') || lower.contains('sherpa')) {
      return true;
    }

    // Handle Whisper ONNX models
    if (lower.contains('whisper') && !lower.contains('whisperkit')) {
      return true;
    }

    // Handle Paraformer models
    if (lower.contains('paraformer')) {
      return true;
    }

    // Handle Glados/Distil models (ONNX-based)
    if (lower.contains('glados') || lower.contains('distil')) {
      return true;
    }

    return false;
  }

  @override
  Future<STTService> createSTTService(dynamic configuration) async {
    final service = OnnxSTTService(_backend);

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
