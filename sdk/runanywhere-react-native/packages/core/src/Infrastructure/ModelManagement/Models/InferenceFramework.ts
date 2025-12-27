/**
 * InferenceFramework.ts
 * RunAnywhere SDK
 *
 * Supported inference frameworks/runtimes for running models
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/ModelManagement/Models/Domain/InferenceFramework.swift
 */

/**
 * Supported inference frameworks/runtimes for executing models
 */
export enum InferenceFramework {
  CoreML = 'CoreML',
  TensorFlowLite = 'TFLite',
  MLX = 'MLX',
  SwiftTransformers = 'SwiftTransformers',
  ONNX = 'ONNX',
  ExecuTorch = 'ExecuTorch',
  LlamaCpp = 'LlamaCpp',
  FoundationModels = 'FoundationModels',
  PicoLLM = 'PicoLLM',
  MLC = 'MLC',
  MediaPipe = 'MediaPipe',
  WhisperKit = 'WhisperKit',
  OpenAIWhisper = 'OpenAIWhisper',
  SystemTTS = 'SystemTTS',
  FluidAudio = 'FluidAudio',
}

/**
 * Get human-readable display name for the framework
 */
export function getFrameworkDisplayName(framework: InferenceFramework): string {
  switch (framework) {
    case InferenceFramework.CoreML:
      return 'Core ML';
    case InferenceFramework.TensorFlowLite:
      return 'TensorFlow Lite';
    case InferenceFramework.MLX:
      return 'MLX';
    case InferenceFramework.SwiftTransformers:
      return 'Swift Transformers';
    case InferenceFramework.ONNX:
      return 'ONNX Runtime';
    case InferenceFramework.ExecuTorch:
      return 'ExecuTorch';
    case InferenceFramework.LlamaCpp:
      return 'llama.cpp';
    case InferenceFramework.FoundationModels:
      return 'Foundation Models';
    case InferenceFramework.PicoLLM:
      return 'Pico LLM';
    case InferenceFramework.MLC:
      return 'MLC';
    case InferenceFramework.MediaPipe:
      return 'MediaPipe';
    case InferenceFramework.WhisperKit:
      return 'WhisperKit';
    case InferenceFramework.OpenAIWhisper:
      return 'OpenAI Whisper';
    case InferenceFramework.SystemTTS:
      return 'System TTS';
    case InferenceFramework.FluidAudio:
      return 'FluidAudio';
  }
}

/**
 * Check if framework supports LLM (text-to-text)
 */
export function frameworkSupportsLLM(framework: InferenceFramework): boolean {
  switch (framework) {
    case InferenceFramework.LlamaCpp:
    case InferenceFramework.MLX:
    case InferenceFramework.CoreML:
    case InferenceFramework.ONNX:
    case InferenceFramework.FoundationModels:
    case InferenceFramework.PicoLLM:
    case InferenceFramework.MLC:
      return true;
    default:
      return false;
  }
}

/**
 * Check if framework supports STT (speech-to-text)
 */
export function frameworkSupportsSTT(framework: InferenceFramework): boolean {
  switch (framework) {
    case InferenceFramework.WhisperKit:
    case InferenceFramework.OpenAIWhisper:
    case InferenceFramework.MediaPipe:
      return true;
    default:
      return false;
  }
}

/**
 * Check if framework supports TTS (text-to-speech)
 */
export function frameworkSupportsTTS(framework: InferenceFramework): boolean {
  switch (framework) {
    case InferenceFramework.SystemTTS:
      return true;
    default:
      return false;
  }
}
