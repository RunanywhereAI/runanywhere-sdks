// App Types (mirroring iOS AppTypes.swift)
//
// Contains core data models used throughout the app.

/// System device information for displaying hardware capabilities
class SystemDeviceInfo {
  final String modelName;
  final String chipName;
  final int totalMemory;
  final int availableMemory;
  final bool neuralEngineAvailable;
  final String osVersion;
  final String appVersion;

  const SystemDeviceInfo({
    this.modelName = '',
    this.chipName = '',
    this.totalMemory = 0,
    this.availableMemory = 0,
    this.neuralEngineAvailable = false,
    this.osVersion = '',
    this.appVersion = '',
  });

  SystemDeviceInfo copyWith({
    String? modelName,
    String? chipName,
    int? totalMemory,
    int? availableMemory,
    bool? neuralEngineAvailable,
    String? osVersion,
    String? appVersion,
  }) {
    return SystemDeviceInfo(
      modelName: modelName ?? this.modelName,
      chipName: chipName ?? this.chipName,
      totalMemory: totalMemory ?? this.totalMemory,
      availableMemory: availableMemory ?? this.availableMemory,
      neuralEngineAvailable:
          neuralEngineAvailable ?? this.neuralEngineAvailable,
      osVersion: osVersion ?? this.osVersion,
      appVersion: appVersion ?? this.appVersion,
    );
  }
}

/// Extension for formatting file sizes
extension FileSizeFormatter on int {
  /// Formats bytes into human-readable file size string
  String get formattedFileSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = toDouble();
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '${size.toInt()} ${units[unitIndex]}';
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}

// MessageRole is now provided by the RunAnywhere SDK
// import 'package:runanywhere/runanywhere.dart' show MessageRole;

/// Completion status for message generation
enum CompletionStatus {
  complete,
  interrupted,
  failed,
  timeout,
}

/// Generation mode for LLM inference
enum GenerationMode {
  streaming,
  nonStreaming,
}

/// Routing policy for model selection
enum RoutingPolicy {
  automatic,
  deviceOnly,
  preferDevice,
  preferCloud,
}

// ModelLoadState is now provided by the RunAnywhere SDK
// import 'package:runanywhere/runanywhere.dart' show ModelLoadState;
// Use AppModelLoadState for app-specific states to avoid conflict
enum AppModelLoadState {
  notLoaded,
  loading,
  loaded,
  failed,
}

/// Voice session state for voice assistant
enum VoiceSessionState {
  disconnected,
  connecting,
  connected,
  listening,
  processing,
  speaking,
  error,
}
