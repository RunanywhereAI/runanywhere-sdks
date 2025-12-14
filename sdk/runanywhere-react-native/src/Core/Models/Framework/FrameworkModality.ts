/**
 * FrameworkModality.ts
 *
 * Defines the input/output modalities a framework supports
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Framework/FrameworkModality.swift
 */

/**
 * Defines the input/output modalities a framework supports
 */
export enum FrameworkModality {
  TextToText = 'text-to-text', // Traditional LLM text generation
  VoiceToText = 'voice-to-text', // Speech recognition/transcription
  TextToVoice = 'text-to-voice', // Text-to-speech synthesis
  ImageToText = 'image-to-text', // Image captioning/OCR
  TextToImage = 'text-to-image', // Image generation
  Multimodal = 'multimodal', // Supports multiple modalities
}

/**
 * Human-readable display name for a modality
 */
export function getFrameworkModalityDisplayName(modality: FrameworkModality): string {
  switch (modality) {
    case FrameworkModality.TextToText:
      return 'Text Generation';
    case FrameworkModality.VoiceToText:
      return 'Speech Recognition';
    case FrameworkModality.TextToVoice:
      return 'Text-to-Speech';
    case FrameworkModality.ImageToText:
      return 'Image Understanding';
    case FrameworkModality.TextToImage:
      return 'Image Generation';
    case FrameworkModality.Multimodal:
      return 'Multimodal';
  }
}

/**
 * Icon name for UI display
 */
export function getFrameworkModalityIconName(modality: FrameworkModality): string {
  switch (modality) {
    case FrameworkModality.TextToText:
      return 'text.bubble';
    case FrameworkModality.VoiceToText:
      return 'mic';
    case FrameworkModality.TextToVoice:
      return 'speaker.wave.2';
    case FrameworkModality.ImageToText:
      return 'photo.badge.arrow.down';
    case FrameworkModality.TextToImage:
      return 'photo.badge.plus';
    case FrameworkModality.Multimodal:
      return 'sparkles';
  }
}

