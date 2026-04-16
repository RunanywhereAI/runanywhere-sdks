enum VisionMode { idle, capturing, processing, streaming }

class VisionState {
  const VisionState({
    this.mode = VisionMode.idle,
    this.isModelLoaded = false,
    this.modelName,
    this.isCameraReady = false,
    this.description = '',
    this.isAutoStreaming = false,
    this.errorMessage,
  });

  final VisionMode mode;
  final bool isModelLoaded;
  final String? modelName;
  final bool isCameraReady;
  final String description;
  final bool isAutoStreaming;
  final String? errorMessage;

  bool get isProcessing =>
      mode == VisionMode.processing || mode == VisionMode.streaming;

  VisionState copyWith({
    VisionMode? mode,
    bool? isModelLoaded,
    String? modelName,
    bool? isCameraReady,
    String? description,
    bool? isAutoStreaming,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VisionState(
      mode: mode ?? this.mode,
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      modelName: modelName ?? this.modelName,
      isCameraReady: isCameraReady ?? this.isCameraReady,
      description: description ?? this.description,
      isAutoStreaming: isAutoStreaming ?? this.isAutoStreaming,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
