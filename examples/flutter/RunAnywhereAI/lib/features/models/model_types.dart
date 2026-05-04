import 'package:runanywhere/runanywhere.dart' as sdk;

typedef ModelInfo = sdk.ModelInfo;
typedef ModelCategory = sdk.ModelCategory;
typedef ModelFormat = sdk.ModelFormat;
typedef LLMFramework = sdk.InferenceFramework;

/// Model selection context is app UI state, not an SDK data contract.
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
        return {
          sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        };
      case ModelSelectionContext.stt:
        return {sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION};
      case ModelSelectionContext.tts:
        return {sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS};
      case ModelSelectionContext.voice:
        return {
          sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL,
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
          sdk.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        };
      case ModelSelectionContext.vlm:
        return {
          sdk.ModelCategory.MODEL_CATEGORY_VISION,
          sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        };
      case ModelSelectionContext.ragEmbedding:
        return {sdk.ModelCategory.MODEL_CATEGORY_EMBEDDING};
      case ModelSelectionContext.ragLLM:
        return {sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE};
    }
  }
}

extension ModelCategoryDisplay on ModelCategory {
  String get displayName {
    switch (this) {
      case sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return 'Language';
      case sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return 'Multimodal';
      case sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return 'Speech Recognition';
      case sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return 'Speech Synthesis';
      case sdk.ModelCategory.MODEL_CATEGORY_VISION:
        return 'Vision';
      case sdk.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
        return 'Image Generation';
      case sdk.ModelCategory.MODEL_CATEGORY_AUDIO:
        return 'Audio';
      case sdk.ModelCategory.MODEL_CATEGORY_EMBEDDING:
        return 'Embedding';
      case sdk.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return 'Voice Activity Detection';
      default:
        return 'Unknown';
    }
  }
}

extension InferenceFrameworkDisplay on LLMFramework {
  String get displayName {
    switch (this) {
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return 'llama.cpp';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return 'ONNX';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return 'Sherpa-ONNX';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return 'Foundation Models';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return 'System TTS';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
        return 'Genie';
      default:
        return 'Unknown';
    }
  }
}

extension ModelFormatDisplay on ModelFormat {
  String get rawValue {
    switch (this) {
      case sdk.ModelFormat.MODEL_FORMAT_GGUF:
        return 'gguf';
      case sdk.ModelFormat.MODEL_FORMAT_GGML:
        return 'ggml';
      case sdk.ModelFormat.MODEL_FORMAT_ONNX:
        return 'onnx';
      case sdk.ModelFormat.MODEL_FORMAT_ORT:
        return 'ort';
      case sdk.ModelFormat.MODEL_FORMAT_BIN:
        return 'bin';
      case sdk.ModelFormat.MODEL_FORMAT_COREML:
        return 'coreml';
      case sdk.ModelFormat.MODEL_FORMAT_MLMODEL:
        return 'mlmodel';
      case sdk.ModelFormat.MODEL_FORMAT_MLPACKAGE:
        return 'mlpackage';
      case sdk.ModelFormat.MODEL_FORMAT_TFLITE:
        return 'tflite';
      case sdk.ModelFormat.MODEL_FORMAT_SAFETENSORS:
        return 'safetensors';
      case sdk.ModelFormat.MODEL_FORMAT_QNN_CONTEXT:
        return 'qnn_context';
      case sdk.ModelFormat.MODEL_FORMAT_ZIP:
        return 'zip';
      case sdk.ModelFormat.MODEL_FORMAT_FOLDER:
        return 'folder';
      case sdk.ModelFormat.MODEL_FORMAT_PROPRIETARY:
        return 'proprietary';
      default:
        return 'unknown';
    }
  }
}

extension ExampleModelInfoView on ModelInfo {
  int? get memoryRequired =>
      hasDownloadSizeBytes() && downloadSizeBytes.toInt() > 0
          ? downloadSizeBytes.toInt()
          : null;

  List<LLMFramework> get compatibleFrameworks => [framework];

  LLMFramework get preferredFramework => framework;

  bool get isDownloaded =>
      localPath.isNotEmpty ||
      framework ==
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
      framework == sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
      builtIn;
}
