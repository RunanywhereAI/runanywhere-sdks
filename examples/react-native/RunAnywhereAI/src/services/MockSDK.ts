/**
 * Mock SDK Service
 *
 * This service mocks the RunAnywhere SDK for UI development.
 * TODO: Replace with actual SDK calls when ready.
 *
 * Reference: sdk/runanywhere-react-native/src/RunAnywhere.ts
 */

import {
  ModelInfo,
  ModelCategory,
  LLMFramework,
  ModelLoadState,
  StoredModel,
  DeviceInfo,
  FrameworkInfo,
  ModelModality,
} from '../types/model';
import { STTResult, TTSResult, TTSConfiguration } from '../types/voice';
import { StorageInfo, AppSettings, DEFAULT_SETTINGS } from '../types/settings';

// ============================================================================
// Mock Data
// ============================================================================

/**
 * Mock models available in the app
 */
export const MOCK_MODELS: ModelInfo[] = [
  // LLM Models
  {
    id: 'smollm2-360m',
    name: 'SmolLM2 360M Q8_0',
    category: ModelCategory.Language,
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    downloadSize: 500 * 1024 * 1024, // 500MB
    memoryRequired: 600 * 1024 * 1024,
    contextLength: 4096,
    supportsThinking: false,
    isDownloaded: true,
    isAvailable: true,
    description: 'Small but capable language model',
  },
  {
    id: 'qwen-2.5-0.5b',
    name: 'Qwen 2.5 0.5B Instruct Q6_K',
    category: ModelCategory.Language,
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    downloadSize: 600 * 1024 * 1024,
    memoryRequired: 700 * 1024 * 1024,
    contextLength: 8192,
    supportsThinking: false,
    isDownloaded: true,
    isAvailable: true,
    description: 'Efficient instruction-following model',
  },
  {
    id: 'llama-3.2-1b',
    name: 'Llama 3.2 1B Instruct Q6_K',
    category: ModelCategory.Language,
    compatibleFrameworks: [LLMFramework.LlamaCpp],
    preferredFramework: LLMFramework.LlamaCpp,
    downloadSize: 1.2 * 1024 * 1024 * 1024,
    memoryRequired: 1.5 * 1024 * 1024 * 1024,
    contextLength: 8192,
    supportsThinking: false,
    isDownloaded: false,
    isAvailable: false,
    description: 'Meta\'s Llama 3.2 1B parameter model',
  },
  // STT Models
  {
    id: 'whisper-tiny',
    name: 'Whisper Tiny',
    category: ModelCategory.SpeechRecognition,
    compatibleFrameworks: [LLMFramework.WhisperKit],
    preferredFramework: LLMFramework.WhisperKit,
    downloadSize: 39 * 1024 * 1024,
    memoryRequired: 100 * 1024 * 1024,
    supportsThinking: false,
    isDownloaded: true,
    isAvailable: true,
    description: 'Smallest Whisper model, fastest inference',
  },
  {
    id: 'whisper-base',
    name: 'Whisper Base',
    category: ModelCategory.SpeechRecognition,
    compatibleFrameworks: [LLMFramework.WhisperKit],
    preferredFramework: LLMFramework.WhisperKit,
    downloadSize: 74 * 1024 * 1024,
    memoryRequired: 200 * 1024 * 1024,
    supportsThinking: false,
    isDownloaded: false,
    isAvailable: false,
    description: 'Balanced Whisper model for general use',
  },
  // TTS Models
  {
    id: 'piper-en-us-lessac',
    name: 'Piper TTS - US English Lessac',
    category: ModelCategory.SpeechSynthesis,
    compatibleFrameworks: [LLMFramework.PiperTTS],
    preferredFramework: LLMFramework.PiperTTS,
    downloadSize: 65 * 1024 * 1024,
    memoryRequired: 150 * 1024 * 1024,
    supportsThinking: false,
    isDownloaded: true,
    isAvailable: true,
    description: 'High-quality US English voice',
  },
  {
    id: 'piper-en-gb-alba',
    name: 'Piper TTS - British English Alba',
    category: ModelCategory.SpeechSynthesis,
    compatibleFrameworks: [LLMFramework.PiperTTS],
    preferredFramework: LLMFramework.PiperTTS,
    downloadSize: 65 * 1024 * 1024,
    memoryRequired: 150 * 1024 * 1024,
    supportsThinking: false,
    isDownloaded: false,
    isAvailable: false,
    description: 'British English voice',
  },
];

/**
 * Mock frameworks
 */
export const MOCK_FRAMEWORKS: FrameworkInfo[] = [
  {
    framework: LLMFramework.LlamaCpp,
    displayName: 'llama.cpp',
    isAvailable: true,
    modalities: [ModelModality.LLM],
    iconName: 'cube-outline',
    color: '#FF6B35',
  },
  {
    framework: LLMFramework.WhisperKit,
    displayName: 'WhisperKit',
    isAvailable: true,
    modalities: [ModelModality.STT],
    iconName: 'mic-outline',
    color: '#00C853',
  },
  {
    framework: LLMFramework.PiperTTS,
    displayName: 'Piper TTS',
    isAvailable: true,
    modalities: [ModelModality.TTS],
    iconName: 'volume-high-outline',
    color: '#E91E63',
  },
  {
    framework: LLMFramework.FoundationModels,
    displayName: 'Foundation Models',
    isAvailable: false,
    unavailableReason: 'Requires iOS 26+',
    modalities: [ModelModality.LLM],
    iconName: 'sparkles-outline',
    color: '#AF52DE',
  },
  {
    framework: LLMFramework.CoreML,
    displayName: 'Core ML',
    isAvailable: true,
    modalities: [ModelModality.LLM, ModelModality.VLM],
    iconName: 'hardware-chip-outline',
    color: '#FF9500',
  },
];

/**
 * Mock device info
 */
export const MOCK_DEVICE_INFO: DeviceInfo = {
  modelName: 'iPhone 15 Pro',
  chipName: 'A17 Pro',
  totalMemory: 8 * 1024 * 1024 * 1024, // 8GB
  availableMemory: 4 * 1024 * 1024 * 1024, // 4GB
  hasNeuralEngine: true,
  osVersion: '17.5',
};

/**
 * Mock storage info
 */
export const MOCK_STORAGE_INFO: StorageInfo = {
  totalStorage: 256 * 1024 * 1024 * 1024, // 256GB
  appStorage: 2 * 1024 * 1024 * 1024, // 2GB
  modelsStorage: 1.5 * 1024 * 1024 * 1024, // 1.5GB
  cacheSize: 50 * 1024 * 1024, // 50MB
  freeSpace: 100 * 1024 * 1024 * 1024, // 100GB
};

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Simulate async delay
 */
const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Generate a random ID
 */
const generateId = (): string => Math.random().toString(36).substring(2, 15);

// ============================================================================
// Mock State
// ============================================================================

let currentLLMModel: ModelInfo | null = null;
let currentSTTModel: ModelInfo | null = null;
let currentTTSModel: ModelInfo | null = null;
let isInitialized = false;

// ============================================================================
// Mock SDK Service
// ============================================================================

/**
 * Mock SDK for development
 *
 * TODO: Replace all methods with actual RunAnywhere SDK calls
 */
export const MockSDK = {
  // ============================================================================
  // Initialization
  // ============================================================================

  /**
   * Initialize the SDK
   * TODO: Replace with RunAnywhere.initialize()
   */
  async initialize(apiKey: string, baseURL?: string): Promise<void> {
    console.log('[MockSDK] Initializing...');
    await delay(500);
    isInitialized = true;
    console.log('[MockSDK] Initialized');
  },

  /**
   * Check if SDK is initialized
   * TODO: Replace with RunAnywhere.isInitialized()
   */
  isInitialized(): boolean {
    return isInitialized;
  },

  /**
   * Reset SDK state
   * TODO: Replace with RunAnywhere.reset()
   */
  async reset(): Promise<void> {
    console.log('[MockSDK] Resetting...');
    await delay(200);
    currentLLMModel = null;
    currentSTTModel = null;
    currentTTSModel = null;
    isInitialized = false;
    console.log('[MockSDK] Reset complete');
  },

  // ============================================================================
  // Model Management
  // ============================================================================

  /**
   * Get available models
   * TODO: Replace with RunAnywhere.availableModels()
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    await delay(100);
    return MOCK_MODELS;
  },

  /**
   * Get models by category
   */
  async getModelsByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    await delay(100);
    return MOCK_MODELS.filter((m) => m.category === category);
  },

  /**
   * Get models by modality
   */
  async getModelsByModality(modality: ModelModality): Promise<ModelInfo[]> {
    await delay(100);
    const categoryMap: Record<ModelModality, ModelCategory> = {
      [ModelModality.LLM]: ModelCategory.Language,
      [ModelModality.STT]: ModelCategory.SpeechRecognition,
      [ModelModality.TTS]: ModelCategory.SpeechSynthesis,
      [ModelModality.VLM]: ModelCategory.Vision,
    };
    return MOCK_MODELS.filter((m) => m.category === categoryMap[modality]);
  },

  /**
   * Load a model
   * TODO: Replace with RunAnywhere.loadModel()
   */
  async loadModel(modelId: string): Promise<void> {
    console.log(`[MockSDK] Loading model: ${modelId}`);
    const model = MOCK_MODELS.find((m) => m.id === modelId);
    if (!model) {
      throw new Error(`Model not found: ${modelId}`);
    }
    if (!model.isDownloaded) {
      throw new Error(`Model not downloaded: ${modelId}`);
    }

    // Simulate loading time
    await delay(2000);

    // Set as current model based on category
    switch (model.category) {
      case ModelCategory.Language:
        currentLLMModel = model;
        break;
      case ModelCategory.SpeechRecognition:
        currentSTTModel = model;
        break;
      case ModelCategory.SpeechSynthesis:
        currentTTSModel = model;
        break;
    }

    console.log(`[MockSDK] Model loaded: ${modelId}`);
  },

  /**
   * Get current LLM model
   */
  getCurrentLLMModel(): ModelInfo | null {
    return currentLLMModel;
  },

  /**
   * Get current STT model
   */
  getCurrentSTTModel(): ModelInfo | null {
    return currentSTTModel;
  },

  /**
   * Get current TTS model
   */
  getCurrentTTSModel(): ModelInfo | null {
    return currentTTSModel;
  },

  /**
   * Download a model
   * TODO: Replace with RunAnywhere.downloadModel()
   */
  async downloadModel(
    modelId: string,
    onProgress?: (progress: number) => void
  ): Promise<void> {
    console.log(`[MockSDK] Downloading model: ${modelId}`);
    const model = MOCK_MODELS.find((m) => m.id === modelId);
    if (!model) {
      throw new Error(`Model not found: ${modelId}`);
    }

    // Simulate download progress
    for (let i = 0; i <= 100; i += 10) {
      await delay(300);
      onProgress?.(i / 100);
    }

    // Mark as downloaded
    model.isDownloaded = true;
    model.isAvailable = true;

    console.log(`[MockSDK] Model downloaded: ${modelId}`);
  },

  /**
   * Delete a model
   * TODO: Replace with RunAnywhere.deleteModel()
   */
  async deleteModel(modelId: string): Promise<void> {
    console.log(`[MockSDK] Deleting model: ${modelId}`);
    await delay(500);

    const model = MOCK_MODELS.find((m) => m.id === modelId);
    if (model) {
      model.isDownloaded = false;
      model.isAvailable = false;
    }

    // Unload if currently loaded
    if (currentLLMModel?.id === modelId) currentLLMModel = null;
    if (currentSTTModel?.id === modelId) currentSTTModel = null;
    if (currentTTSModel?.id === modelId) currentTTSModel = null;

    console.log(`[MockSDK] Model deleted: ${modelId}`);
  },

  // ============================================================================
  // Text Generation
  // ============================================================================

  /**
   * Generate text response
   * TODO: Replace with RunAnywhere.generate()
   */
  async generate(
    prompt: string,
    options?: {
      maxTokens?: number;
      temperature?: number;
      systemPrompt?: string;
    }
  ): Promise<{
    text: string;
    tokensUsed: number;
    latencyMs: number;
    tokensPerSecond: number;
  }> {
    if (!currentLLMModel) {
      throw new Error('No LLM model loaded');
    }

    console.log(`[MockSDK] Generating response for: "${prompt.slice(0, 50)}..."`);
    await delay(1500);

    // Generate mock response
    const mockResponses = [
      "I'm an AI assistant running on your device. How can I help you today?",
      'That\'s a great question! Let me think about it...',
      'Based on my understanding, here\'s what I can tell you about that topic.',
      'I\'d be happy to help you with that. Here\'s my response.',
      'Interesting question! From my training, I know that...',
    ];

    const text = mockResponses[Math.floor(Math.random() * mockResponses.length)];
    const tokensUsed = Math.floor(text.split(' ').length * 1.3);
    const latencyMs = 1500;
    const tokensPerSecond = (tokensUsed / latencyMs) * 1000;

    return {
      text,
      tokensUsed,
      latencyMs,
      tokensPerSecond,
    };
  },

  /**
   * Generate streaming text response
   * TODO: Replace with RunAnywhere.generateStream()
   */
  async *generateStream(
    prompt: string,
    options?: {
      maxTokens?: number;
      temperature?: number;
    }
  ): AsyncGenerator<string, void, unknown> {
    if (!currentLLMModel) {
      throw new Error('No LLM model loaded');
    }

    const mockResponse =
      "I'm an AI assistant running on your device. I can help you with various tasks including answering questions, writing text, and more. What would you like to know?";
    const words = mockResponse.split(' ');

    for (const word of words) {
      await delay(100);
      yield word + ' ';
    }
  },

  // ============================================================================
  // Speech-to-Text
  // ============================================================================

  /**
   * Transcribe audio
   * TODO: Replace with RunAnywhere.transcribe()
   */
  async transcribe(audioData: string): Promise<STTResult> {
    if (!currentSTTModel) {
      throw new Error('No STT model loaded');
    }

    console.log('[MockSDK] Transcribing audio...');
    await delay(1000);

    return {
      text: 'This is a mock transcription of the audio input.',
      segments: [
        {
          text: 'This is a mock transcription of the audio input.',
          startTime: 0,
          endTime: 3.5,
          confidence: 0.95,
        },
      ],
      language: 'en',
      confidence: 0.95,
      duration: 3.5,
      processingTime: 1000,
    };
  },

  // ============================================================================
  // Text-to-Speech
  // ============================================================================

  /**
   * Synthesize speech
   * TODO: Replace with RunAnywhere.synthesize()
   */
  async synthesize(
    text: string,
    config?: TTSConfiguration
  ): Promise<TTSResult> {
    if (!currentTTSModel) {
      throw new Error('No TTS model loaded');
    }

    console.log(`[MockSDK] Synthesizing: "${text.slice(0, 50)}..."`);
    await delay(800);

    return {
      audioData: 'mock_base64_audio_data',
      duration: text.length * 0.08, // Rough estimate
      sampleRate: 22050,
      generationTime: 800,
    };
  },

  // ============================================================================
  // Device & Storage
  // ============================================================================

  /**
   * Get device info
   */
  async getDeviceInfo(): Promise<DeviceInfo> {
    await delay(100);
    return MOCK_DEVICE_INFO;
  },

  /**
   * Get available frameworks
   */
  async getAvailableFrameworks(): Promise<FrameworkInfo[]> {
    await delay(100);
    return MOCK_FRAMEWORKS;
  },

  /**
   * Get storage info
   */
  async getStorageInfo(): Promise<StorageInfo> {
    await delay(100);
    return MOCK_STORAGE_INFO;
  },

  /**
   * Get stored models
   */
  async getStoredModels(): Promise<StoredModel[]> {
    await delay(100);
    return MOCK_MODELS.filter((m) => m.isDownloaded).map((m) => ({
      id: m.id,
      name: m.name,
      framework: m.preferredFramework || LLMFramework.LlamaCpp,
      sizeOnDisk: m.downloadSize || 0,
      downloadedAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), // 7 days ago
      lastUsed: new Date(),
    }));
  },

  /**
   * Clear cache
   */
  async clearCache(): Promise<void> {
    console.log('[MockSDK] Clearing cache...');
    await delay(500);
    console.log('[MockSDK] Cache cleared');
  },

  /**
   * Clear all data
   */
  async clearAllData(): Promise<void> {
    console.log('[MockSDK] Clearing all data...');
    await delay(1000);
    currentLLMModel = null;
    currentSTTModel = null;
    currentTTSModel = null;
    // Reset downloaded states
    MOCK_MODELS.forEach((m) => {
      if (m.id !== 'smollm2-360m' && m.id !== 'whisper-tiny' && m.id !== 'piper-en-us-lessac') {
        m.isDownloaded = false;
        m.isAvailable = false;
      }
    });
    console.log('[MockSDK] All data cleared');
  },

  // ============================================================================
  // Settings
  // ============================================================================

  /**
   * Get settings
   */
  async getSettings(): Promise<AppSettings> {
    await delay(100);
    return DEFAULT_SETTINGS;
  },

  /**
   * Save settings
   */
  async saveSettings(settings: Partial<AppSettings>): Promise<void> {
    console.log('[MockSDK] Saving settings:', settings);
    await delay(200);
    console.log('[MockSDK] Settings saved');
  },
};

export default MockSDK;
