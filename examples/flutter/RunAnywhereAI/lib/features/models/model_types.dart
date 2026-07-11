import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/runanywhere.dart' show formatFramework;
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

typedef ModelInfo = sdk.ModelInfo;
typedef ModelCategory = sdk.ModelCategory;
typedef ModelFormat = sdk.ModelFormat;
typedef LLMFramework = sdk.InferenceFramework;

const Set<String> _privateHfTags = {
  'private',
  'requires-hf-auth',
  'hf-auth',
  'huggingface-auth',
  'hugging-face-auth',
};

/// Model selection context is app UI state, not an SDK data contract.
enum ModelSelectionContext {
  llm,
  stt,
  tts,
  voice,
  vlm,
  vad,
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
      case ModelSelectionContext.vad:
        return 'Select VAD Model';
      case ModelSelectionContext.ragEmbedding:
        return 'Select Embedding Model';
      case ModelSelectionContext.ragLLM:
        return 'Select LLM Model';
    }
  }

  /// Mirrors iOS `ModelSelectionSheet.swift` `relevantCategories`: the LLM
  /// picker is language-only (multimodal models load through the VLM
  /// lifecycle), and the voice picker covers exactly the assistant pipeline
  /// components (language + STT + TTS).
  Set<ModelCategory> get relevantCategories {
    switch (this) {
      case ModelSelectionContext.llm:
        return {sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE};
      case ModelSelectionContext.stt:
        return {sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION};
      case ModelSelectionContext.tts:
        return {sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS};
      case ModelSelectionContext.voice:
        return {
          sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        };
      case ModelSelectionContext.vlm:
        return {
          sdk.ModelCategory.MODEL_CATEGORY_VISION,
          sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        };
      case ModelSelectionContext.vad:
        return {sdk.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION};
      case ModelSelectionContext.ragEmbedding:
        return {sdk.ModelCategory.MODEL_CATEGORY_EMBEDDING};
      case ModelSelectionContext.ragLLM:
        return {sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE};
    }
  }

  /// Frameworks to include. `null` means all frameworks that have matching
  /// models. Android RAG can use either the portable CPU backend or QHexRT's
  /// native device-accepted embedding/generator rows.
  Set<LLMFramework>? get allowedFrameworks {
    switch (this) {
      case ModelSelectionContext.ragEmbedding:
        return {
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        };
      case ModelSelectionContext.ragLLM:
        return {
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        };
      default:
        return null;
    }
  }

  /// Single shared picker predicate: category match, framework allow-list,
  /// and (RAG embedding only) supporting-file/reranker exclusion. The suffix
  /// checks mirror iOS; the reranker guard mirrors the Android QHexRT picker.
  bool includes(ModelInfo model) {
    if (!relevantCategories.contains(model.category)) return false;
    final frameworks = allowedFrameworks;
    if (frameworks != null && !frameworks.contains(model.backendFramework)) {
      return false;
    }
    if (this == ModelSelectionContext.ragEmbedding &&
        (model.id.endsWith('-vocab') ||
            model.id.endsWith('-tokenizer') ||
            model.id.toLowerCase().contains('rerank'))) {
      return false;
    }
    return true;
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
  String get displayName => formatFramework(this);

  String get backendShortLabel {
    switch (this) {
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return 'llama.cpp';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return 'ONNX';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return 'Sherpa';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return 'Apple';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return 'System';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT:
        return 'QHexRT';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
        return 'Core ML';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return 'MLX';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:
        return 'Piper';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return 'Fluid';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:
        return 'TFLite';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH:
        return 'ExecuTorch';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE:
        return 'MediaPipe';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MLC:
        return 'MLC';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM:
        return 'Pico';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
        return 'Swift';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return 'Built-in';
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return 'None';
      default:
        return displayName;
    }
  }

  IconData get backendIcon {
    switch (this) {
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return Icons.storage;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return Icons.developer_board;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return Icons.graphic_eq;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return Icons.apple;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:
        return Icons.volume_up;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return Icons.memory;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return Icons.graphic_eq;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MLC:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
        return Icons.view_in_ar;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return Icons.check_circle;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return Icons.block;
      default:
        return Icons.info_outline;
    }
  }

  Color get backendColor {
    switch (this) {
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return AppColors.primaryBlue;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return AppColors.primaryPurple;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return AppColors.primaryOrange;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT:
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return AppColors.primaryGreen;
      case sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return AppColors.statusGray;
      default:
        return AppColors.statusGray;
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
  bool get requiresHfAuth {
    final tags = hasMetadata()
        ? metadata.tags.map((tag) => tag.toLowerCase()).toSet()
        : const <String>{};
    return tags.any(_privateHfTags.contains) ||
        (framework == sdk.InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT &&
            QHexRT.modelRequiresHfAuth(id));
  }

  int? get memoryRequired {
    final downloadBytes =
        hasDownloadSizeBytes() && downloadSizeBytes.toInt() > 0
        ? downloadSizeBytes.toInt()
        : null;
    if (downloadBytes != null) return downloadBytes;
    return hasMemoryRequiredBytes() && memoryRequiredBytes.toInt() > 0
        ? memoryRequiredBytes.toInt()
        : null;
  }

  LLMFramework get backendFramework {
    final preferred = preferredFramework;
    if (hasPreferredFramework() &&
        preferred != sdk.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED &&
        preferred != sdk.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN) {
      return preferred;
    }
    if (framework != sdk.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED) {
      return framework;
    }
    return sdk.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
  }

  List<LLMFramework> get compatibleFrameworks => [backendFramework];

  /// Readiness check for the example UI.
  ///
  /// NOTE: this is deliberately NOT named `isDownloaded`. The generated
  /// `ModelInfo` proto already exposes a `bool isDownloaded` instance member,
  /// and a Dart extension getter of the same name is silently shadowed by that
  /// instance member. The C++ registry populates `localPath` on download but
  /// does not flip the proto `isDownloaded` flag, so gating load on
  /// `model.isDownloaded` resolved to the always-false proto field and made the
  /// "Use" action a no-op. Gate on the same on-disk/built-in signal the row UI
  /// uses instead (mirrors Swift `isDownloaded` / Kotlin `isDownloadedOnDisk`).
  bool get isReadyOnDevice =>
      localPath.isNotEmpty ||
      backendFramework ==
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
      backendFramework ==
          sdk.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
      builtIn;
}
