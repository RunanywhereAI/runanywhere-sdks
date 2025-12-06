import '../framework/llm_framework.dart';
import '../framework/model_format.dart';

/// Model criteria for filtering
/// Matches iOS ModelCriteria from Core/Models/Model/ModelCriteria.swift
class ModelCriteria {
  final LLMFramework? framework;
  final ModelFormat? format;
  final int? maxSize;
  final int? minContextLength;
  final int? maxContextLength;
  final bool? requiresNeuralEngine;
  final bool? requiresGPU;
  final List<String> tags;
  final String? quantization;
  final String? search;

  const ModelCriteria({
    this.framework,
    this.format,
    this.maxSize,
    this.minContextLength,
    this.maxContextLength,
    this.requiresNeuralEngine,
    this.requiresGPU,
    this.tags = const [],
    this.quantization,
    this.search,
  });

  /// Check if criteria has any filters
  bool get hasFilters =>
      framework != null ||
      format != null ||
      maxSize != null ||
      minContextLength != null ||
      maxContextLength != null ||
      requiresNeuralEngine != null ||
      requiresGPU != null ||
      tags.isNotEmpty ||
      quantization != null ||
      search != null;

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        if (framework != null) 'framework': framework!.rawValue,
        if (format != null) 'format': format!.rawValue,
        if (maxSize != null) 'maxSize': maxSize,
        if (minContextLength != null) 'minContextLength': minContextLength,
        if (maxContextLength != null) 'maxContextLength': maxContextLength,
        if (requiresNeuralEngine != null)
          'requiresNeuralEngine': requiresNeuralEngine,
        if (requiresGPU != null) 'requiresGPU': requiresGPU,
        if (tags.isNotEmpty) 'tags': tags,
        if (quantization != null) 'quantization': quantization,
        if (search != null) 'search': search,
      };

  factory ModelCriteria.fromJson(Map<String, dynamic> json) {
    return ModelCriteria(
      framework: json['framework'] != null
          ? LLMFramework.fromRawValue(json['framework'] as String)
          : null,
      format: json['format'] != null
          ? ModelFormat.fromRawValue(json['format'] as String)
          : null,
      maxSize: json['maxSize'] as int?,
      minContextLength: json['minContextLength'] as int?,
      maxContextLength: json['maxContextLength'] as int?,
      requiresNeuralEngine: json['requiresNeuralEngine'] as bool?,
      requiresGPU: json['requiresGPU'] as bool?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      quantization: json['quantization'] as String?,
      search: json['search'] as String?,
    );
  }

  /// Copy with modifications
  ModelCriteria copyWith({
    LLMFramework? framework,
    ModelFormat? format,
    int? maxSize,
    int? minContextLength,
    int? maxContextLength,
    bool? requiresNeuralEngine,
    bool? requiresGPU,
    List<String>? tags,
    String? quantization,
    String? search,
  }) {
    return ModelCriteria(
      framework: framework ?? this.framework,
      format: format ?? this.format,
      maxSize: maxSize ?? this.maxSize,
      minContextLength: minContextLength ?? this.minContextLength,
      maxContextLength: maxContextLength ?? this.maxContextLength,
      requiresNeuralEngine: requiresNeuralEngine ?? this.requiresNeuralEngine,
      requiresGPU: requiresGPU ?? this.requiresGPU,
      tags: tags ?? this.tags,
      quantization: quantization ?? this.quantization,
      search: search ?? this.search,
    );
  }
}
