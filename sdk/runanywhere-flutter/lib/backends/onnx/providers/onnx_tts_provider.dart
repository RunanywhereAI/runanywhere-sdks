import '../../../core/module_registry.dart';
import '../../native/native_backend.dart';
import '../services/onnx_tts_service.dart';

/// Provider for ONNX-based TTS service.
///
/// This is the Flutter equivalent of Swift's `ONNXTTSServiceProvider`.
class OnnxTTSServiceProvider implements TTSServiceProvider {
  final NativeBackend _backend;

  /// Create a new ONNX TTS provider.
  OnnxTTSServiceProvider(this._backend);

  @override
  String get name => 'ONNX Runtime';

  @override
  String get version => '1.23.2';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();

    // Handle ONNX models
    if (lower.endsWith('.onnx') || lower.contains('onnx')) {
      return true;
    }

    // Handle VITS models (ONNX-based TTS)
    if (lower.contains('vits')) {
      return true;
    }

    // Handle Sherpa TTS models
    if (lower.contains('sherpa') && lower.contains('tts')) {
      return true;
    }

    return false;
  }

  @override
  Future<dynamic> createTTSService(dynamic configuration) async {
    final service = OnnxTTSService(_backend);

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
