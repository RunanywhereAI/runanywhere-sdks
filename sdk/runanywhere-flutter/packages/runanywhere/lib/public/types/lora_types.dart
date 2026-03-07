/// LoRA Types
///
/// Data types for LoRA (Low-Rank Adaptation) adapter operations.
/// Mirrors Swift's LLMTypes.swift LoRA types and Kotlin's RunAnywhere+LoRA.kt.
library lora_types;

/// Configuration for loading a LoRA adapter.
class LoRAAdapterConfig {
  /// Path to the LoRA adapter GGUF file.
  final String path;

  /// Scale factor for the adapter (0.0-1.0+, default 1.0).
  final double scale;

  LoRAAdapterConfig({
    required this.path,
    this.scale = 1.0,
  }) : assert(path.isNotEmpty, 'LoRA adapter path cannot be empty');
}

/// Info about a currently loaded LoRA adapter.
class LoRAAdapterInfo {
  /// File path where adapter was loaded from.
  final String path;

  /// LoRA scale factor.
  final double scale;

  /// Whether adapter is currently applied to the context.
  final bool applied;

  const LoRAAdapterInfo({
    required this.path,
    required this.scale,
    required this.applied,
  });
}

/// Catalog entry for a LoRA adapter (metadata for registry).
class LoraAdapterCatalogEntry {
  /// Unique adapter identifier.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Short description of what this adapter does.
  final String description;

  /// Direct download URL (.gguf file).
  final String downloadUrl;

  /// Filename to save as on disk.
  final String filename;

  /// Explicit list of compatible base model IDs.
  final List<String> compatibleModelIds;

  /// File size in bytes (0 if unknown).
  final int fileSize;

  /// Recommended LoRA scale (e.g. 0.3).
  final double defaultScale;

  const LoraAdapterCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUrl,
    required this.filename,
    required this.compatibleModelIds,
    this.fileSize = 0,
    this.defaultScale = 1.0,
  });
}

/// Result of a LoRA compatibility check.
class LoraCompatibilityResult {
  /// Whether the current backend supports LoRA for the given adapter.
  final bool isCompatible;

  /// Error message if incompatible, null if compatible.
  final String? error;

  const LoraCompatibilityResult({
    required this.isCompatible,
    this.error,
  });
}
