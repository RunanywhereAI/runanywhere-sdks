/// Model Information
/// Similar to Swift SDK's ModelInfo
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int memoryRequirement;
  final String? format;
  final String? framework;
  final String? downloadURL;

  ModelInfo({
    required this.id,
    required this.name,
    this.description,
    required this.memoryRequirement,
    this.format,
    this.framework,
    this.downloadURL,
  });
}

