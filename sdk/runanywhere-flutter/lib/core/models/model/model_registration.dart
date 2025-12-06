import '../framework/llm_framework.dart';
import '../framework/framework_modality.dart';
import '../framework/model_format.dart';
import '../common/configuration_source.dart';
import 'model_info.dart';
import 'model_category.dart';
import 'model_info_metadata.dart';

/// Helper class for registering models with framework adapters
/// Matches iOS ModelRegistration from Public/Models/ModelRegistration.swift
class ModelRegistration {
  /// The URL where the model can be downloaded
  final Uri url;

  /// The framework this model is designed for
  final LLMFramework framework;

  /// The modality this model supports
  final FrameworkModality modality;

  /// Model identifier (auto-generated from URL if not provided)
  final String id;

  /// Human-readable name
  final String name;

  /// Model file format
  final ModelFormat format;

  /// Estimated memory requirement in bytes
  final int memoryRequirement;

  /// Whether the model supports thinking/reasoning
  final bool supportsThinking;

  /// Optional download size in bytes
  final int? downloadSize;

  /// Optional description
  final String? description;

  /// Optional tags
  final List<String>? tags;

  /// Constructor
  /// [url] Download URL for the model (required)
  /// [framework] Target framework (required)
  /// [modality] Model modality (required)
  /// [id] Model ID (auto-generated if not provided)
  /// [name] Human-readable name (required)
  /// [format] Model format (auto-detected from URL if not provided)
  /// [memoryRequirement] Estimated memory in bytes (default: 500MB)
  /// [supportsThinking] Whether model supports thinking/reasoning
  /// [downloadSize] Download size in bytes
  /// [description] Model description
  /// [tags] Model tags
  ModelRegistration({
    required String url,
    required this.framework,
    required this.modality,
    String? id,
    required this.name,
    ModelFormat? format,
    this.memoryRequirement = 500000000, // Default 500MB
    this.supportsThinking = false,
    this.downloadSize,
    this.description,
    this.tags,
  })  : url = Uri.parse(url),
        id = id ?? _generateModelId(url),
        format = format ?? _detectFormat(url);

  /// Create from URL string with validation
  factory ModelRegistration.fromUrl({
    required String url,
    required LLMFramework framework,
    required FrameworkModality modality,
    String? id,
    required String name,
    ModelFormat? format,
    int memoryRequirement = 500000000,
    bool supportsThinking = false,
    int? downloadSize,
    String? description,
    List<String>? tags,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw ArgumentError('Invalid URL: $url');
    }

    return ModelRegistration(
      url: url,
      framework: framework,
      modality: modality,
      id: id,
      name: name,
      format: format,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
      downloadSize: downloadSize,
      description: description,
      tags: tags,
    );
  }

  /// Convert to ModelInfo
  ModelInfo toModelInfo() {
    final category = _modalityToCategory(modality);

    return ModelInfo(
      id: id,
      name: name,
      category: category,
      format: format,
      downloadURL: url,
      downloadSize: downloadSize,
      memoryRequired: memoryRequirement,
      compatibleFrameworks: [framework],
      preferredFramework: framework,
      contextLength: category == ModelCategory.language ? 2048 : null,
      supportsThinking: supportsThinking,
      metadata: ModelInfoMetadata(
        description: description,
        tags: tags ?? [framework.rawValue.toLowerCase()],
      ),
      source: ConfigurationSource.embedded,
    );
  }

  /// Generate model ID from URL
  static String _generateModelId(String url) {
    final uri = Uri.parse(url);
    final filename = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final nameWithoutExtension = filename.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Create a clean ID
    return nameWithoutExtension
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Detect format from URL
  static ModelFormat _detectFormat(String url) {
    final urlLower = url.toLowerCase();

    if (urlLower.endsWith('.gguf')) return ModelFormat.gguf;
    if (urlLower.endsWith('.ggml')) return ModelFormat.ggml;
    if (urlLower.endsWith('.mlmodel')) return ModelFormat.mlmodel;
    if (urlLower.endsWith('.mlpackage')) return ModelFormat.mlpackage;
    if (urlLower.endsWith('.tflite')) return ModelFormat.tflite;
    if (urlLower.endsWith('.onnx')) return ModelFormat.onnx;
    if (urlLower.endsWith('.ort')) return ModelFormat.ort;
    if (urlLower.endsWith('.safetensors')) return ModelFormat.safetensors;
    if (urlLower.endsWith('.mlx')) return ModelFormat.mlx;
    if (urlLower.endsWith('.pte')) return ModelFormat.pte;
    if (urlLower.endsWith('.bin')) return ModelFormat.bin;
    if (urlLower.endsWith('.tar.bz2')) return ModelFormat.onnx; // Sherpa ONNX archives
    if (urlLower.endsWith('.tar.gz')) return ModelFormat.onnx;

    return ModelFormat.unknown;
  }

  /// Convert modality to category
  static ModelCategory _modalityToCategory(FrameworkModality modality) {
    switch (modality) {
      case FrameworkModality.textToText:
        return ModelCategory.language;
      case FrameworkModality.voiceToText:
        return ModelCategory.speechRecognition;
      case FrameworkModality.textToVoice:
        return ModelCategory.speechSynthesis;
      case FrameworkModality.visionToText:
      case FrameworkModality.imageToText:
        return ModelCategory.vision;
      case FrameworkModality.textToImage:
        return ModelCategory.imageGeneration;
      case FrameworkModality.multimodal:
        return ModelCategory.multimodal;
      case FrameworkModality.voiceActivityDetection:
        return ModelCategory.speechRecognition;
      case FrameworkModality.speakerDiarization:
        return ModelCategory.speechRecognition;
      case FrameworkModality.wakeWord:
        return ModelCategory.speechRecognition;
      case FrameworkModality.textEmbedding:
        return ModelCategory.embedding;
    }
  }
}
