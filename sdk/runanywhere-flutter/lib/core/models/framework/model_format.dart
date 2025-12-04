/// Model formats supported
/// Matches iOS ModelFormat from Core/Models/Framework/ModelFormat.swift
enum ModelFormat {
  mlmodel('mlmodel'),
  mlpackage('mlpackage'),
  tflite('tflite'),
  onnx('onnx'),
  ort('ort'),
  safetensors('safetensors'),
  gguf('gguf'),
  ggml('ggml'),
  mlx('mlx'),
  pte('pte'),
  bin('bin'),
  weights('weights'),
  checkpoint('checkpoint'),
  unknown('unknown');

  final String rawValue;

  const ModelFormat(this.rawValue);

  /// Create from raw string value
  static ModelFormat fromRawValue(String value) {
    return ModelFormat.values.firstWhere(
      (f) => f.rawValue == value,
      orElse: () => ModelFormat.unknown,
    );
  }

  /// Get format from file extension
  static ModelFormat fromExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    return ModelFormat.values.firstWhere(
      (f) => f.rawValue == ext,
      orElse: () => ModelFormat.unknown,
    );
  }
}
