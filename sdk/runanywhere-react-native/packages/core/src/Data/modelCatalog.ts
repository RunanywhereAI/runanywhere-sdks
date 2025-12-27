/**
 * Model Catalog for RunAnywhere React Native SDK
 *
 * Pre-configured models available in the RunAnywhere platform.
 * This catalog mirrors the Swift SDK's model catalog for consistency.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/Services/MockNetworkService.swift
 */

import type { ModelInfo } from '../types';
import {
  ConfigurationSource,
  LLMFramework,
  ModelCategory,
  ModelFormat,
} from '../types';

/**
 * Pre-configured model catalog
 *
 * These models are available for download and use in the SDK.
 * Models are listed in order of size (smallest to largest).
 */
export const MODEL_CATALOG: ModelInfo[] = [
  // MARK: - Apple Foundation Models (iOS 18+)
  {
    id: 'foundation-models-default',
    name: 'Apple Foundation Model',
    category: ModelCategory.Language,
    format: ModelFormat.ONNX,
    downloadURL: undefined, // Built-in, no download needed
    localPath: undefined,
    downloadSize: 0, // Built-in
    memoryRequired: 500_000_000, // 500MB
    compatibleFrameworks: [LLMFramework.FoundationModels],
    preferredFramework: LLMFramework.FoundationModels,
    contextLength: 8192,
    supportsThinking: false,
    metadata: {
      description: 'Apple Foundation Model for on-device AI',
      author: 'Apple',
      license: 'Proprietary',
      tags: ['built-in', 'apple', 'foundation'],
    },
    source: ConfigurationSource.Builtin,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // MARK: - Language Models (smallest to largest)

  // LiquidAI LFM2 350M Q4_K_M (Smallest, fastest)
  {
    id: 'lfm2-350m-q4-k-m',
    name: 'LiquidAI LFM2 350M Q4_K_M',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    localPath: undefined,
    downloadSize: 218_690_000, // ~219MB
    memoryRequired: 250_000_000, // 250MB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 32768,
    supportsThinking: false,
    metadata: {
      description: 'LiquidAI LFM2 350M model with Q4_K_M quantization',
      author: 'LiquidAI',
      license: 'Apache 2.0',
      tags: ['small', 'fast', 'liquid-ai'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // SmolLM2 360M Q8_0
  {
    id: 'smollm2-360m-q8-0',
    name: 'SmolLM2 360M Q8_0',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    localPath: undefined,
    downloadSize: 385_000_000, // ~385MB
    memoryRequired: 500_000_000, // 500MB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 8192,
    supportsThinking: false,
    metadata: {
      description: 'SmolLM2 360M model with Q8_0 quantization',
      author: 'HuggingFace',
      license: 'Apache 2.0',
      tags: ['small', 'efficient', 'smollm'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // LiquidAI LFM2 350M Q8_0 (Highest quality)
  {
    id: 'lfm2-350m-q8-0',
    name: 'LiquidAI LFM2 350M Q8_0',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
    localPath: undefined,
    downloadSize: 361_650_000, // ~362MB
    memoryRequired: 400_000_000, // 400MB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 32768,
    supportsThinking: false,
    metadata: {
      description:
        'LiquidAI LFM2 350M model with Q8_0 quantization (highest quality)',
      author: 'LiquidAI',
      license: 'Apache 2.0',
      tags: ['small', 'high-quality', 'liquid-ai'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // Qwen-2.5 0.5B Q6_K
  {
    id: 'qwen-2.5-0.5b-instruct-q6-k',
    name: 'Qwen 2.5 0.5B Instruct Q6_K',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    localPath: undefined,
    downloadSize: 650_000_000, // ~650MB
    memoryRequired: 600_000_000, // 600MB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 32768,
    supportsThinking: true,
    metadata: {
      description: 'Qwen 2.5 0.5B Instruct model with Q6_K quantization',
      author: 'Alibaba',
      license: 'Apache 2.0',
      tags: ['qwen', 'instruct', 'thinking'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // Llama-3.2 1B Q6_K
  {
    id: 'llama-3.2-1b-instruct-q6-k',
    name: 'Llama 3.2 1B Instruct Q6_K',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf',
    localPath: undefined,
    downloadSize: 1_100_000_000, // ~1.1GB
    memoryRequired: 1_200_000_000, // 1.2GB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 131072,
    supportsThinking: true,
    metadata: {
      description: 'Llama 3.2 1B Instruct model with Q6_K quantization',
      author: 'Meta',
      license: 'Llama 3.2 Community License',
      tags: ['llama', 'instruct', 'thinking'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // Qwen-2.5 1.5B Q6_K
  {
    id: 'qwen-2.5-1.5b-instruct-q6-k',
    name: 'Qwen 2.5 1.5B Instruct Q6_K',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf',
    localPath: undefined,
    downloadSize: 1_400_000_000, // ~1.4GB
    memoryRequired: 1_600_000_000, // 1.6GB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 32768,
    supportsThinking: true,
    metadata: {
      description: 'Qwen 2.5 1.5B Instruct model with Q6_K quantization',
      author: 'Alibaba',
      license: 'Apache 2.0',
      tags: ['qwen', 'instruct', 'thinking'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // SmolLM2 1.7B Instruct Q6_K_L
  {
    id: 'smollm2-1.7b-instruct-q6-k-l',
    name: 'SmolLM2 1.7B Instruct Q6_K_L',
    category: ModelCategory.Language,
    format: ModelFormat.GGUF,
    downloadURL:
      'https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf',
    localPath: undefined,
    downloadSize: 1_700_000_000, // ~1.7GB
    memoryRequired: 1_800_000_000, // 1.8GB
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    contextLength: 8192,
    supportsThinking: true,
    metadata: {
      description: 'SmolLM2 1.7B Instruct model with Q6_K_L quantization',
      author: 'HuggingFace',
      license: 'Apache 2.0',
      tags: ['smollm', 'instruct', 'thinking'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // MARK: - Voice Models (Speech Recognition)

  // Whisper Tiny
  {
    id: 'sherpa-onnx-whisper-tiny-en',
    name: 'Whisper Tiny (English)',
    category: ModelCategory.SpeechRecognition,
    format: ModelFormat.ONNX,
    downloadURL:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2',
    localPath: undefined,
    downloadSize: 39_000_000, // ~39MB
    memoryRequired: 39_000_000, // 39MB
    compatibleFrameworks: [LLMFramework.ONNX],
    preferredFramework: LLMFramework.ONNX,
    contextLength: 0,
    supportsThinking: false,
    metadata: {
      description: 'Whisper Tiny model for fast speech recognition',
      author: 'OpenAI',
      license: 'MIT',
      tags: ['whisper', 'stt', 'tiny', 'fast'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // Whisper Base
  {
    id: 'sherpa-onnx-whisper-base-en',
    name: 'Whisper Base (English)',
    category: ModelCategory.SpeechRecognition,
    format: ModelFormat.ONNX,
    downloadURL:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.en.tar.bz2',
    localPath: undefined,
    downloadSize: 74_000_000, // ~74MB
    memoryRequired: 74_000_000, // 74MB
    compatibleFrameworks: [LLMFramework.ONNX],
    preferredFramework: LLMFramework.ONNX,
    contextLength: 0,
    supportsThinking: false,
    metadata: {
      description: 'Whisper Base model for balanced speech recognition',
      author: 'OpenAI',
      license: 'MIT',
      tags: ['whisper', 'stt', 'base'],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // MARK: - Text-to-Speech Models - Sherpa-ONNX Compatible

  // System TTS (Built-in, always available)
  {
    id: 'system-tts',
    name: 'System TTS',
    category: ModelCategory.SpeechSynthesis,
    format: ModelFormat.Proprietary,
    downloadURL: 'builtin://system-tts',
    localPath: 'builtin://system-tts',
    downloadSize: 0,
    memoryRequired: 0,
    compatibleFrameworks: [LLMFramework.SystemTTS],
    preferredFramework: LLMFramework.SystemTTS,
    contextLength: 0,
    supportsThinking: false,
    metadata: {
      description: 'Built-in system text-to-speech using AVSpeechSynthesizer',
      author: 'Apple',
      license: 'Proprietary',
      tags: ['tts', 'system', 'built-in', 'offline'],
    },
    source: ConfigurationSource.Builtin,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: true,
    isAvailable: true,
  },

  // Sherpa-ONNX VITS Piper - English (US) - Amy
  {
    id: 'vits-piper-en-us-libritts',
    name: 'Piper LibriTTS (US English)',
    category: ModelCategory.SpeechSynthesis,
    format: ModelFormat.ONNX,
    downloadURL:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-libritts_r-medium.tar.bz2',
    localPath: undefined,
    downloadSize: 63_000_000,
    memoryRequired: 100_000_000,
    compatibleFrameworks: [LLMFramework.ONNX],
    preferredFramework: LLMFramework.ONNX,
    contextLength: 0,
    supportsThinking: false,
    metadata: {
      description: 'Sherpa-ONNX VITS Piper voice - LibriTTS (American English)',
      author: 'Piper/k2-fsa',
      license: 'MIT',
      tags: [
        'tts',
        'piper',
        'vits',
        'neural',
        'english',
        'female',
        'sherpa-onnx',
      ],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },

  // Sherpa-ONNX VITS Piper - English (US) - Lessac
  {
    id: 'vits-piper-en-us-lessac',
    name: 'Piper Lessac (US English)',
    category: ModelCategory.SpeechSynthesis,
    format: ModelFormat.ONNX,
    downloadURL:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
    localPath: undefined,
    downloadSize: 63_000_000,
    memoryRequired: 100_000_000,
    compatibleFrameworks: [LLMFramework.ONNX],
    preferredFramework: LLMFramework.ONNX,
    contextLength: 0,
    supportsThinking: false,
    metadata: {
      description: 'Sherpa-ONNX VITS Piper voice - Lessac (American English)',
      author: 'Piper/k2-fsa',
      license: 'MIT',
      tags: [
        'tts',
        'piper',
        'vits',
        'neural',
        'english',
        'male',
        'sherpa-onnx',
      ],
    },
    source: ConfigurationSource.Remote,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    syncPending: false,
    usageCount: 0,
    isDownloaded: false,
    isAvailable: true,
  },
];

/**
 * Get all models in the catalog
 */
export function getAllCatalogModels(): ModelInfo[] {
  return MODEL_CATALOG;
}

/**
 * Get a model by ID from the catalog
 */
export function getCatalogModel(id: string): ModelInfo | undefined {
  return MODEL_CATALOG.find((model) => model.id === id);
}

/**
 * Get models by category from the catalog
 */
export function getCatalogModelsByCategory(
  category: ModelCategory
): ModelInfo[] {
  return MODEL_CATALOG.filter((model) => model.category === category);
}

/**
 * Get models by framework from the catalog
 */
export function getCatalogModelsByFramework(
  framework: LLMFramework
): ModelInfo[] {
  return MODEL_CATALOG.filter((model) =>
    model.compatibleFrameworks.includes(framework)
  );
}

/**
 * Get language models from the catalog
 */
export function getLanguageModels(): ModelInfo[] {
  return getCatalogModelsByCategory(ModelCategory.Language);
}

/**
 * Get speech recognition models from the catalog
 */
export function getSpeechRecognitionModels(): ModelInfo[] {
  return getCatalogModelsByCategory(ModelCategory.SpeechRecognition);
}

/**
 * Get models sorted by size (smallest to largest)
 */
export function getModelsSortedBySize(): ModelInfo[] {
  return [...MODEL_CATALOG].sort(
    (a, b) => (a.downloadSize || 0) - (b.downloadSize || 0)
  );
}
