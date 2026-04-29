// Model Types (mirroring iOS model types)
//
// Contains model-related enums and data classes.
//
// G-E10 / §15 — LLMFramework was deleted; callers now use the canonical
// `sdk.InferenceFramework` from `package:runanywhere/runanywhere.dart`.

import 'package:runanywhere/runanywhere.dart' as sdk;

// Re-export SDK's InferenceFramework under the app-level alias so existing
// callers that reference `LLMFramework` compile without changes while
// being transparently backed by the SDK enum.
typedef LLMFramework = sdk.InferenceFramework;

/// Model category enumeration
/// Matches SDK ModelCategory for proper conversion
enum ModelCategory {
  language,
  multimodal,
  speechRecognition,
  speechSynthesis,
  vision,
  imageGeneration,
  audio,
  embedding,
  unknown;

  String get displayName {
    switch (this) {
      case ModelCategory.language:
        return 'Language';
      case ModelCategory.multimodal:
        return 'Multimodal';
      case ModelCategory.speechRecognition:
        return 'Speech Recognition';
      case ModelCategory.speechSynthesis:
        return 'Speech Synthesis';
      case ModelCategory.vision:
        return 'Vision';
      case ModelCategory.imageGeneration:
        return 'Image Generation';
      case ModelCategory.audio:
        return 'Audio';
      case ModelCategory.embedding:
        return 'Embedding';
      case ModelCategory.unknown:
        return 'Unknown';
    }
  }
}

/// Model format enumeration
enum ModelFormat {
  gguf,
  ggml,
  coreml,
  onnx,
  tflite,
  bin,
  unknown;

  String get rawValue {
    switch (this) {
      case ModelFormat.gguf:
        return 'gguf';
      case ModelFormat.ggml:
        return 'ggml';
      case ModelFormat.coreml:
        return 'coreml';
      case ModelFormat.onnx:
        return 'onnx';
      case ModelFormat.tflite:
        return 'tflite';
      case ModelFormat.bin:
        return 'bin';
      case ModelFormat.unknown:
        return 'unknown';
    }
  }
}

/// Model selection context
enum ModelSelectionContext {
  llm,
  stt,
  tts,
  voice,
  vlm,
  ragEmbedding,
  ragLLM;

  String get title {
    switch (this) {
      case ModelSelectionContext.llm:
        return 'Select LLM Model';
      case ModelSelectionContext.stt:
        return 'Select STT Model';
      case ModelSelectionContext.tts:
        return 'Select TTS Model';
      case ModelSelectionContext.voice:
        return 'Select Model';
      case ModelSelectionContext.vlm:
        return 'Select VLM Model';
      case ModelSelectionContext.ragEmbedding:
        return 'Select Embedding Model';
      case ModelSelectionContext.ragLLM:
        return 'Select LLM Model';
    }
  }

  Set<ModelCategory> get relevantCategories {
    switch (this) {
      case ModelSelectionContext.llm:
        return {ModelCategory.language, ModelCategory.multimodal};
      case ModelSelectionContext.stt:
        return {ModelCategory.speechRecognition};
      case ModelSelectionContext.tts:
        return {ModelCategory.speechSynthesis};
      case ModelSelectionContext.voice:
        return {
          ModelCategory.language,
          ModelCategory.multimodal,
          ModelCategory.speechRecognition,
          ModelCategory.speechSynthesis,
        };
      case ModelSelectionContext.vlm:
        return {ModelCategory.vision, ModelCategory.multimodal};
      case ModelSelectionContext.ragEmbedding:
        return {ModelCategory.embedding};
      case ModelSelectionContext.ragLLM:
        return {ModelCategory.language};
    }
  }
}

/// Model info class (app-local view over SDK models)
class ModelInfo {
  final String id;
  final String name;
  final ModelCategory category;
  final ModelFormat format;
  final String? downloadURL;
  final String? localPath;
  final int? memoryRequired;
  // Uses canonical InferenceFramework (via LLMFramework typedef)
  final List<LLMFramework> compatibleFrameworks;
  final LLMFramework? preferredFramework;
  final bool supportsThinking;

  const ModelInfo({
    required this.id,
    required this.name,
    this.category = ModelCategory.language,
    this.format = ModelFormat.unknown,
    this.downloadURL,
    this.localPath,
    this.memoryRequired,
    this.compatibleFrameworks = const [],
    this.preferredFramework,
    this.supportsThinking = false,
  });

  bool get isDownloaded => localPath != null;

  ModelInfo copyWith({
    String? id,
    String? name,
    ModelCategory? category,
    ModelFormat? format,
    String? downloadURL,
    String? localPath,
    int? memoryRequired,
    List<LLMFramework>? compatibleFrameworks,
    LLMFramework? preferredFramework,
    bool? supportsThinking,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      format: format ?? this.format,
      downloadURL: downloadURL ?? this.downloadURL,
      localPath: localPath ?? this.localPath,
      memoryRequired: memoryRequired ?? this.memoryRequired,
      compatibleFrameworks: compatibleFrameworks ?? this.compatibleFrameworks,
      preferredFramework: preferredFramework ?? this.preferredFramework,
      supportsThinking: supportsThinking ?? this.supportsThinking,
    );
  }
}

/// Download progress state
enum DownloadState {
  notStarted,
  downloading,
  completed,
  failed,
}

/// Download progress info
class DownloadProgress {
  final double percentage;
  final DownloadState state;
  final String? error;

  const DownloadProgress({
    this.percentage = 0.0,
    this.state = DownloadState.notStarted,
    this.error,
  });
}
