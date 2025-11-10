/// Configuration Entity for storage
class ConfigurationEntity {
  final String id;
  final String apiKey;
  final String baseURL;
  final String environment;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConfigurationEntity({
    required this.id,
    required this.apiKey,
    required this.baseURL,
    required this.environment,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'apiKey': apiKey,
      'baseURL': baseURL,
      'environment': environment,
      'data': data,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory ConfigurationEntity.fromJson(Map<String, dynamic> json) {
    return ConfigurationEntity(
      id: json['id'] as String,
      apiKey: json['apiKey'] as String,
      baseURL: json['baseURL'] as String,
      environment: json['environment'] as String,
      data: json['data'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

