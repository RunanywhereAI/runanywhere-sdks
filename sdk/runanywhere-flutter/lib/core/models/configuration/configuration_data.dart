import '../common/configuration_source.dart';
import '../hardware/hardware_configuration.dart';
import 'api_configuration.dart';
import 'generation_configuration.dart';
import 'model_download_configuration.dart';
import 'routing_configuration.dart';
import 'storage_configuration.dart';

/// Main configuration data structure using composed configurations.
/// Works for both network API and database storage.
/// Matches iOS ConfigurationData from Configuration/ConfigurationData.swift
class ConfigurationData {
  /// Unique identifier for this configuration
  final String id;

  /// Routing configuration
  final RoutingConfiguration routing;

  /// Generation configuration
  final GenerationConfiguration generation;

  /// Storage configuration (includes memory threshold)
  final StorageConfiguration storage;

  /// API configuration (baseURL, timeouts, etc)
  final APIConfiguration api;

  /// Download configuration
  final ModelDownloadConfiguration download;

  /// Hardware preferences (optional)
  final HardwareConfiguration? hardware;

  /// Debug mode flag
  final bool debugMode;

  /// API key for authentication (optional - can be provided separately)
  final String? apiKey;

  /// Whether user can override configuration
  final bool allowUserOverride;

  /// Configuration source
  final ConfigurationSource source;

  /// Metadata - when configuration was created
  final DateTime createdAt;

  /// Metadata - when configuration was last updated
  final DateTime updatedAt;

  /// Whether configuration needs to be synced to cloud
  final bool syncPending;

  ConfigurationData({
    String? id,
    RoutingConfiguration? routing,
    GenerationConfiguration? generation,
    StorageConfiguration? storage,
    APIConfiguration? api,
    ModelDownloadConfiguration? download,
    this.hardware,
    this.debugMode = false,
    this.apiKey,
    this.allowUserOverride = true,
    this.source = ConfigurationSource.defaults,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncPending = false,
  })  : id = id ?? 'default',
        routing = routing ?? const RoutingConfiguration(),
        generation = generation ?? const GenerationConfiguration(),
        storage = storage ?? const StorageConfiguration(),
        api = api ?? APIConfiguration(),
        download = download ?? const ModelDownloadConfiguration(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create SDK default configuration
  static ConfigurationData sdkDefaults({required String apiKey}) {
    return ConfigurationData(
      id: 'default-${DateTime.now().millisecondsSinceEpoch}',
      apiKey: apiKey.isEmpty ? 'dev-mode' : apiKey,
      source: ConfigurationSource.defaults,
    );
  }

  /// Create from JSON map
  factory ConfigurationData.fromJson(Map<String, dynamic> json) {
    return ConfigurationData(
      id: json['id'] as String?,
      routing: json['routing'] != null
          ? RoutingConfiguration.fromJson(json['routing'] as Map<String, dynamic>)
          : const RoutingConfiguration(),
      generation: json['generation'] != null
          ? GenerationConfiguration.fromJson(json['generation'] as Map<String, dynamic>)
          : const GenerationConfiguration(),
      storage: json['storage'] != null
          ? StorageConfiguration.fromJson(json['storage'] as Map<String, dynamic>)
          : const StorageConfiguration(),
      api: json['api'] != null
          ? APIConfiguration.fromJson(json['api'] as Map<String, dynamic>)
          : APIConfiguration(),
      download: json['download'] != null
          ? ModelDownloadConfiguration.fromJson(json['download'] as Map<String, dynamic>)
          : const ModelDownloadConfiguration(),
      hardware: json['hardware'] != null
          ? HardwareConfiguration.fromJson(json['hardware'] as Map<String, dynamic>)
          : null,
      debugMode: json['debugMode'] as bool? ?? false,
      apiKey: json['apiKey'] as String?,
      allowUserOverride: json['allowUserOverride'] as bool? ?? true,
      source: ConfigurationSource.fromRawValue(json['source'] as String? ?? 'defaults'),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      syncPending: json['syncPending'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'routing': routing.toJson(),
      'generation': generation.toJson(),
      'storage': storage.toJson(),
      'api': api.toJson(),
      'download': download.toJson(),
      if (hardware != null) 'hardware': hardware!.toJson(),
      'debugMode': debugMode,
      if (apiKey != null) 'apiKey': apiKey,
      'allowUserOverride': allowUserOverride,
      'source': source.rawValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncPending': syncPending,
    };
  }

  /// Create a copy with updated fields
  ConfigurationData copyWith({
    String? id,
    RoutingConfiguration? routing,
    GenerationConfiguration? generation,
    StorageConfiguration? storage,
    APIConfiguration? api,
    ModelDownloadConfiguration? download,
    HardwareConfiguration? hardware,
    bool? debugMode,
    String? apiKey,
    bool? allowUserOverride,
    ConfigurationSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? syncPending,
  }) {
    return ConfigurationData(
      id: id ?? this.id,
      routing: routing ?? this.routing,
      generation: generation ?? this.generation,
      storage: storage ?? this.storage,
      api: api ?? this.api,
      download: download ?? this.download,
      hardware: hardware ?? this.hardware,
      debugMode: debugMode ?? this.debugMode,
      apiKey: apiKey ?? this.apiKey,
      allowUserOverride: allowUserOverride ?? this.allowUserOverride,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      syncPending: syncPending ?? this.syncPending,
    );
  }

  /// Update and mark as pending sync
  ConfigurationData update(ConfigurationData Function(ConfigurationData) updater) {
    final updated = updater(this);
    return updated.copyWith(
      updatedAt: DateTime.now(),
      syncPending: true,
    );
  }
}
