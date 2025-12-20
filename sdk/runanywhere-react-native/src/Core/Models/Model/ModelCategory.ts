/**
 * ModelCategory.ts
 *
 * Defines the category/type of a model based on its input/output modality
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Model/ModelCategory.swift
 */

import { FrameworkModality } from '../Framework/FrameworkModality';
import { LLMFramework } from '../Framework/LLMFramework';
import { ModelFormat } from './ModelFormat';

/**
 * Defines the category/type of a model based on its input/output modality
 */
export enum ModelCategory {
  Language = 'language', // Text-to-text models (LLMs)
  SpeechRecognition = 'speech-recognition', // Voice-to-text models (ASR)
  SpeechSynthesis = 'speech-synthesis', // Text-to-voice models (TTS)
  Vision = 'vision', // Image understanding models
  ImageGeneration = 'image-generation', // Text-to-image models
  Multimodal = 'multimodal', // Models that handle multiple modalities
  Audio = 'audio', // Audio processing (diarization, etc.)
}

/**
 * Human-readable display name
 */
export function getModelCategoryDisplayName(category: ModelCategory): string {
  switch (category) {
    case ModelCategory.Language:
      return 'Language Model';
    case ModelCategory.SpeechRecognition:
      return 'Speech Recognition';
    case ModelCategory.SpeechSynthesis:
      return 'Text-to-Speech';
    case ModelCategory.Vision:
      return 'Vision Model';
    case ModelCategory.ImageGeneration:
      return 'Image Generation';
    case ModelCategory.Multimodal:
      return 'Multimodal';
    case ModelCategory.Audio:
      return 'Audio Processing';
  }
}

/**
 * Maps to the corresponding FrameworkModality
 */
export function getFrameworkModality(
  category: ModelCategory
): FrameworkModality {
  switch (category) {
    case ModelCategory.Language:
      return FrameworkModality.TextToText;
    case ModelCategory.SpeechRecognition:
      return FrameworkModality.VoiceToText;
    case ModelCategory.SpeechSynthesis:
      return FrameworkModality.TextToVoice;
    case ModelCategory.Vision:
      return FrameworkModality.ImageToText;
    case ModelCategory.ImageGeneration:
      return FrameworkModality.TextToImage;
    case ModelCategory.Multimodal:
      return FrameworkModality.Multimodal;
    case ModelCategory.Audio:
      return FrameworkModality.VoiceToText; // Audio processing often involves voice-to-text
  }
}

/**
 * Initialize from a FrameworkModality
 */
export function modelCategoryFromModality(
  modality: FrameworkModality
): ModelCategory | null {
  switch (modality) {
    case FrameworkModality.TextToText:
      return ModelCategory.Language;
    case FrameworkModality.VoiceToText:
      return ModelCategory.SpeechRecognition;
    case FrameworkModality.TextToVoice:
      return ModelCategory.SpeechSynthesis;
    case FrameworkModality.ImageToText:
      return ModelCategory.Vision;
    case FrameworkModality.TextToImage:
      return ModelCategory.ImageGeneration;
    case FrameworkModality.Multimodal:
      return ModelCategory.Multimodal;
  }
}

/**
 * Whether this category typically requires context length
 */
export function requiresContextLength(category: ModelCategory): boolean {
  switch (category) {
    case ModelCategory.Language:
    case ModelCategory.Multimodal:
      return true;
    case ModelCategory.SpeechRecognition:
    case ModelCategory.SpeechSynthesis:
    case ModelCategory.Vision:
    case ModelCategory.ImageGeneration:
    case ModelCategory.Audio:
      return false;
  }
}

/**
 * Whether this category typically supports thinking/reasoning
 */
export function supportsThinking(category: ModelCategory): boolean {
  switch (category) {
    case ModelCategory.Language:
    case ModelCategory.Multimodal:
      return true;
    case ModelCategory.SpeechRecognition:
    case ModelCategory.SpeechSynthesis:
    case ModelCategory.Vision:
    case ModelCategory.ImageGeneration:
    case ModelCategory.Audio:
      return false;
  }
}

/**
 * Determine category from a FrameworkModality (non-failable)
 */
export function modelCategoryFromModalityNonFailable(
  modality: FrameworkModality
): ModelCategory {
  switch (modality) {
    case FrameworkModality.TextToText:
      return ModelCategory.Language;
    case FrameworkModality.VoiceToText:
      return ModelCategory.SpeechRecognition;
    case FrameworkModality.TextToVoice:
      return ModelCategory.SpeechSynthesis;
    case FrameworkModality.ImageToText:
      return ModelCategory.Vision;
    case FrameworkModality.TextToImage:
      return ModelCategory.ImageGeneration;
    case FrameworkModality.Multimodal:
      return ModelCategory.Multimodal;
  }
}

/**
 * Determine category from a framework
 */
export function modelCategoryFromFramework(
  framework: LLMFramework
): ModelCategory {
  switch (framework) {
    case LLMFramework.WhisperKit:
    case LLMFramework.OpenAIWhisper:
      return ModelCategory.SpeechRecognition;
    case LLMFramework.LlamaCpp:
    case LLMFramework.MLX:
    case LLMFramework.MLC:
    case LLMFramework.ExecuTorch:
    case LLMFramework.PicoLLM:
    case LLMFramework.FoundationModels:
    case LLMFramework.SwiftTransformers:
      return ModelCategory.Language;
    case LLMFramework.CoreML:
    case LLMFramework.TensorFlowLite:
    case LLMFramework.ONNX:
    case LLMFramework.MediaPipe:
      // These are general frameworks that could be any category
      // Default to multimodal since they can handle various types
      return ModelCategory.Multimodal;
    case LLMFramework.SystemTTS:
      return ModelCategory.SpeechSynthesis;
    default:
      // For any unknown or new frameworks, default to Multimodal
      return ModelCategory.Multimodal;
  }
}

/**
 * Determine category from format and frameworks
 */
export function modelCategoryFromFormatAndFrameworks(
  format: ModelFormat,
  frameworks: LLMFramework[]
): ModelCategory {
  // First check if we have framework hints
  if (frameworks.length > 0 && frameworks[0] !== undefined) {
    return modelCategoryFromFramework(frameworks[0]);
  }

  // Otherwise guess from format
  switch (format) {
    case ModelFormat.MLModel:
    case ModelFormat.MLPackage:
      return ModelCategory.Multimodal; // Core ML models can be anything
    case ModelFormat.GGUF:
    case ModelFormat.GGML:
    case ModelFormat.SafeTensors:
    case ModelFormat.Bin:
      return ModelCategory.Language; // Usually LLMs
    case ModelFormat.TFLite:
    case ModelFormat.ONNX:
      return ModelCategory.Multimodal; // Could be anything
    default:
      return ModelCategory.Language; // Default to language
  }
}
