/**
 * LLMFramework.ts
 *
 * Supported LLM frameworks
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Framework/LLMFramework.swift
 */

import { FrameworkModality } from './FrameworkModality';

/**
 * Supported LLM frameworks
 */
export enum LLMFramework {
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
}

/**
 * Human-readable display name for a framework
 */
export function getLLMFrameworkDisplayName(framework: LLMFramework): string {
  switch (framework) {
    case LLMFramework.CoreML:
      return 'Core ML';
    case LLMFramework.TensorFlowLite:
      return 'TensorFlow Lite';
    case LLMFramework.MLX:
      return 'MLX';
    case LLMFramework.SwiftTransformers:
      return 'Swift Transformers';
    case LLMFramework.ONNX:
      return 'ONNX Runtime';
    case LLMFramework.ExecuTorch:
      return 'ExecuTorch';
    case LLMFramework.LlamaCpp:
      return 'llama.cpp';
    case LLMFramework.FoundationModels:
      return 'Foundation Models';
    case LLMFramework.PicoLLM:
      return 'Pico LLM';
    case LLMFramework.MLC:
      return 'MLC';
    case LLMFramework.MediaPipe:
      return 'MediaPipe';
    case LLMFramework.WhisperKit:
      return 'WhisperKit';
    case LLMFramework.OpenAIWhisper:
      return 'OpenAI Whisper';
    case LLMFramework.SystemTTS:
      return 'System TTS';
  }
}

/**
 * The primary modality this framework supports
 */
export function getLLMFrameworkPrimaryModality(framework: LLMFramework): FrameworkModality {
  switch (framework) {
    // Voice frameworks
    case LLMFramework.WhisperKit:
    case LLMFramework.OpenAIWhisper:
      return FrameworkModality.VoiceToText;

    // Text generation frameworks
    case LLMFramework.LlamaCpp:
    case LLMFramework.MLX:
    case LLMFramework.MLC:
    case LLMFramework.ExecuTorch:
    case LLMFramework.PicoLLM:
      return FrameworkModality.TextToText;

    // General ML frameworks that can support multiple modalities
    case LLMFramework.CoreML:
    case LLMFramework.TensorFlowLite:
    case LLMFramework.ONNX:
    case LLMFramework.MediaPipe:
      return FrameworkModality.Multimodal;

    // Text-focused frameworks
    case LLMFramework.SwiftTransformers:
    case LLMFramework.FoundationModels:
      return FrameworkModality.TextToText;

    // System TTS
    case LLMFramework.SystemTTS:
      return FrameworkModality.TextToVoice;
  }
}

/**
 * All modalities this framework can support
 */
export function getLLMFrameworkSupportedModalities(framework: LLMFramework): Set<FrameworkModality> {
  switch (framework) {
    // Voice-only frameworks
    case LLMFramework.WhisperKit:
    case LLMFramework.OpenAIWhisper:
      return new Set([FrameworkModality.VoiceToText]);

    // Text-only frameworks
    case LLMFramework.LlamaCpp:
    case LLMFramework.MLX:
    case LLMFramework.MLC:
    case LLMFramework.ExecuTorch:
    case LLMFramework.PicoLLM:
      return new Set([FrameworkModality.TextToText]);

    // Foundation Models might support multimodal in future
    case LLMFramework.FoundationModels:
      return new Set([FrameworkModality.TextToText]);

    // Swift Transformers could support various modalities
    case LLMFramework.SwiftTransformers:
      return new Set([FrameworkModality.TextToText, FrameworkModality.ImageToText]);

    // General frameworks can support multiple modalities
    case LLMFramework.CoreML:
      return new Set([
        FrameworkModality.TextToText,
        FrameworkModality.VoiceToText,
        FrameworkModality.TextToVoice,
        FrameworkModality.ImageToText,
        FrameworkModality.TextToImage,
      ]);

    case LLMFramework.TensorFlowLite:
    case LLMFramework.ONNX:
      return new Set([
        FrameworkModality.TextToText,
        FrameworkModality.VoiceToText,
        FrameworkModality.ImageToText,
      ]);

    case LLMFramework.MediaPipe:
      return new Set([
        FrameworkModality.TextToText,
        FrameworkModality.VoiceToText,
        FrameworkModality.ImageToText,
      ]);

    // System TTS - text-to-voice only
    case LLMFramework.SystemTTS:
      return new Set([FrameworkModality.TextToVoice]);
  }
}

/**
 * Whether this framework is primarily for voice/audio processing
 */
export function isVoiceFramework(framework: LLMFramework): boolean {
  const primaryModality = getLLMFrameworkPrimaryModality(framework);
  return (
    primaryModality === FrameworkModality.VoiceToText ||
    primaryModality === FrameworkModality.TextToVoice
  );
}

/**
 * Whether this framework is primarily for text generation
 */
export function isTextGenerationFramework(framework: LLMFramework): boolean {
  return getLLMFrameworkPrimaryModality(framework) === FrameworkModality.TextToText;
}

/**
 * Whether this framework supports image processing
 */
export function supportsImageProcessing(framework: LLMFramework): boolean {
  const modalities = getLLMFrameworkSupportedModalities(framework);
  return (
    modalities.has(FrameworkModality.ImageToText) ||
    modalities.has(FrameworkModality.TextToImage)
  );
}

