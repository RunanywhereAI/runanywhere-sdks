/**
 * Model Types - Matching iOS and SDK model definitions
 *
 * Reference: sdk/runanywhere-react-native/src/types/models.ts
 */

/**
 * LLM Framework types
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
  PiperTTS = 'PiperTTS',
}

/**
 * Model category
 */
export enum ModelCategory {
  Language = 'language',
  SpeechRecognition = 'speech-recognition',
  SpeechSynthesis = 'speech-synthesis',
  Vision = 'vision',
  ImageGeneration = 'image-generation',
  Multimodal = 'multimodal',
  Audio = 'audio',
}

/**
 * Model modality for filtering
 */
export enum ModelModality {
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  VLM = 'vlm',
}

/**
 * Model load state
 */
export enum ModelLoadState {
  NotLoaded = 'notLoaded',
  Loading = 'loading',
  Loaded = 'loaded',
  Error = 'error',
  Unloading = 'unloading',
}

/**
 * Model download state
 */
export enum ModelDownloadState {
  NotDownloaded = 'notDownloaded',
  Downloading = 'downloading',
  Downloaded = 'downloaded',
  Error = 'error',
}

/**
 * Model info
 */
export interface ModelInfo {
  /** Unique identifier */
  id: string;

  /** Human-readable name */
  name: string;

  /** Model category */
  category: ModelCategory;

  /** Compatible frameworks */
  compatibleFrameworks: LLMFramework[];

  /** Preferred framework */
  preferredFramework?: LLMFramework;

  /** Download size in bytes */
  downloadSize?: number;

  /** Memory required in bytes */
  memoryRequired?: number;

  /** Context length */
  contextLength?: number;

  /** Whether model supports thinking/reasoning */
  supportsThinking: boolean;

  /** Download URL */
  downloadURL?: string;

  /** Local path if downloaded */
  localPath?: string;

  /** Whether downloaded */
  isDownloaded: boolean;

  /** Whether available for use */
  isAvailable: boolean;

  /** Description */
  description?: string;
}

/**
 * Framework info
 */
export interface FrameworkInfo {
  /** Framework identifier */
  framework: LLMFramework;

  /** Display name */
  displayName: string;

  /** Whether available on this device */
  isAvailable: boolean;

  /** Reason if not available */
  unavailableReason?: string;

  /** Modalities supported */
  modalities: ModelModality[];

  /** Icon name for display */
  iconName: string;

  /** Theme color */
  color: string;
}

/**
 * Current model state for a modality
 */
export interface CurrentModelState {
  /** Modality */
  modality: ModelModality;

  /** Model info if loaded */
  model?: ModelInfo;

  /** Framework being used */
  framework?: LLMFramework;

  /** Load state */
  loadState: ModelLoadState;

  /** Error message if any */
  error?: string;

  /** Load progress (0-1) */
  loadProgress?: number;
}

/**
 * Stored model info
 */
export interface StoredModel {
  /** Model ID */
  id: string;

  /** Model name */
  name: string;

  /** Framework */
  framework: LLMFramework;

  /** Size on disk in bytes */
  sizeOnDisk: number;

  /** Download date */
  downloadedAt: Date;

  /** Last used date */
  lastUsed?: Date;
}

/**
 * Device info for model selection
 */
export interface DeviceInfo {
  /** Device model name */
  modelName: string;

  /** Chip name */
  chipName: string;

  /** Total memory in bytes */
  totalMemory: number;

  /** Available memory in bytes */
  availableMemory: number;

  /** Whether device has Neural Engine / NPU */
  hasNeuralEngine: boolean;

  /** OS version */
  osVersion: string;

  /** Whether device has GPU */
  hasGPU?: boolean;

  /** Number of CPU cores */
  cpuCores?: number;
}

/**
 * Framework display name mapping
 */
export const FrameworkDisplayNames: Record<LLMFramework, string> = {
  [LLMFramework.CoreML]: 'Core ML',
  [LLMFramework.TensorFlowLite]: 'TensorFlow Lite',
  [LLMFramework.MLX]: 'MLX',
  [LLMFramework.SwiftTransformers]: 'Swift Transformers',
  [LLMFramework.ONNX]: 'ONNX Runtime',
  [LLMFramework.ExecuTorch]: 'ExecuTorch',
  [LLMFramework.LlamaCpp]: 'llama.cpp',
  [LLMFramework.FoundationModels]: 'Foundation Models',
  [LLMFramework.PicoLLM]: 'Pico LLM',
  [LLMFramework.MLC]: 'MLC',
  [LLMFramework.MediaPipe]: 'MediaPipe',
  [LLMFramework.WhisperKit]: 'WhisperKit',
  [LLMFramework.OpenAIWhisper]: 'OpenAI Whisper',
  [LLMFramework.SystemTTS]: 'System TTS',
  [LLMFramework.PiperTTS]: 'Piper TTS',
};

/**
 * Category display name mapping
 */
export const CategoryDisplayNames: Record<ModelCategory, string> = {
  [ModelCategory.Language]: 'Language Model',
  [ModelCategory.SpeechRecognition]: 'Speech Recognition',
  [ModelCategory.SpeechSynthesis]: 'Text-to-Speech',
  [ModelCategory.Vision]: 'Vision Model',
  [ModelCategory.ImageGeneration]: 'Image Generation',
  [ModelCategory.Multimodal]: 'Multimodal',
  [ModelCategory.Audio]: 'Audio Processing',
};
