import { Colors } from '../theme/colors';
import { RunAnywhere } from '@runanywhere/core';
import {
  InferenceFramework,
  ModelFormat,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';

export const DEFAULT_INFERENCE_FRAMEWORK =
  InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;

// Display-name table lives in the SDK (`RunAnywhere.formatFramework`),
// proxying the canonical `rac_framework_display_name` C ABI in
// runanywhere-commons. Re-export for backward compatibility with the
// existing view code that imported `getFrameworkDisplayName` from here.
export const getFrameworkDisplayName = RunAnywhere.formatFramework;

export const getFrameworkColor = (
  framework?: InferenceFramework | null
): string => {
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
      return Colors.frameworkLlamaCpp;
    case InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:
      return Colors.frameworkPiperTTS;
    case InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
      return Colors.frameworkFoundationModels;
    case InferenceFramework.INFERENCE_FRAMEWORK_COREML:
      return Colors.frameworkCoreML;
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
      return Colors.frameworkONNX;
    case InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
      return Colors.frameworkSystemTTS;
    case InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:
      return Colors.frameworkTFLite;
    case InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
    case InferenceFramework.INFERENCE_FRAMEWORK_MLX:
    case InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT:
      return Colors.primaryPurple;
    case InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH:
    case InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE:
      return Colors.primaryOrange;
    case InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM:
      return Colors.primaryGreen;
    case InferenceFramework.INFERENCE_FRAMEWORK_MLC:
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
    case InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
      return Colors.primaryBlue;
    default:
      return Colors.primaryBlue;
  }
};

export const getFrameworkIcon = (
  framework?: InferenceFramework | null
): string => {
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
      return 'terminal-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
      return 'mic-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS:
      return 'volume-high-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
      return 'sparkles-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_COREML:
    case InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
    case InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT:
      return 'hardware-chip-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
      return 'cube-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
      return 'megaphone-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_TFLITE:
      return 'layers-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_MLX:
      return 'flash-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
      return 'code-slash-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH:
      return 'flame-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM:
      return 'radio-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_MLC:
      return 'git-branch-outline';
    case InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE:
      return 'videocam-outline';
    default:
      return 'extension-puzzle-outline';
  }
};

const isUsableFramework = (
  framework: InferenceFramework | undefined
): framework is InferenceFramework =>
  framework !== undefined &&
  framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED &&
  framework !== InferenceFramework.UNRECOGNIZED;

export const getModelFrameworks = (model: ModelInfo): InferenceFramework[] => {
  const seen = new Set<InferenceFramework>();
  const candidates = [
    model.preferredFramework,
    ...(model.compatibility?.compatibleFrameworks ?? []),
    model.framework,
  ];
  for (const framework of candidates) {
    if (isUsableFramework(framework)) {
      seen.add(framework);
    }
  }
  return Array.from(seen);
};

export const getPrimaryFramework = (
  model: ModelInfo,
  fallback: InferenceFramework = DEFAULT_INFERENCE_FRAMEWORK
): InferenceFramework => getModelFrameworks(model)[0] ?? fallback;

export const isModelCompatibleWithFramework = (
  model: ModelInfo,
  framework: InferenceFramework
): boolean => getModelFrameworks(model).includes(framework);

export const getModelDownloadSizeBytes = (model: ModelInfo): number =>
  model.downloadSizeBytes || 0;

export const getModelFormatLabel = (format?: ModelFormat | null): string => {
  switch (format) {
    case ModelFormat.MODEL_FORMAT_GGUF:
      return 'GGUF';
    case ModelFormat.MODEL_FORMAT_ONNX:
      return 'ONNX';
    case ModelFormat.MODEL_FORMAT_ORT:
      return 'ORT';
    case ModelFormat.MODEL_FORMAT_QNN_CONTEXT:
      return 'QNN';
    case ModelFormat.MODEL_FORMAT_TFLITE:
      return 'TFLite';
    case ModelFormat.MODEL_FORMAT_COREML:
      return 'Core ML';
    case ModelFormat.MODEL_FORMAT_ZIP:
      return 'ZIP';
    case ModelFormat.MODEL_FORMAT_FOLDER:
      return 'Folder';
    case ModelFormat.MODEL_FORMAT_PROPRIETARY:
      return 'Built in';
    default:
      return 'Model';
  }
};
