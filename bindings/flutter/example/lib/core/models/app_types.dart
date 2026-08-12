// App Types
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

/// UI-only load state used by example screens while querying SDK component state.
enum UiModelLoadState {
  notLoaded,
  loading,
  loaded,
  failed,
}

/// UI-only voice state derived from generated VoiceEvent payloads.
enum UiVoiceSessionState {
  disconnected,
  connecting,
  connected,
  listening,
  processing,
  speaking,
  error,
}
