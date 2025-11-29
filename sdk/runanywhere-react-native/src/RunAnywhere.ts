/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * The clean, event-based RunAnywhere SDK for React Native.
 * Single entry point with both event-driven and async/await patterns.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { EventBus } from './events';
import { requireNativeModule, isNativeModuleAvailable } from './native';
import { SDKEnvironment } from './types';
import type {
  GenerationOptions,
  GenerationResult,
  LLMFramework,
  ModelInfo,
  SDKInitOptions,
  STTOptions,
  STTResult,
  TTSConfiguration,
} from './types';

// ============================================================================
// Conversation Helper
// ============================================================================

/**
 * Simple conversation manager for multi-turn conversations
 * Reference: Conversation class in RunAnywhere.swift
 */
export class Conversation {
  private messages: string[] = [];

  /**
   * Send a message and get response
   */
  async send(message: string): Promise<string> {
    this.messages.push(`User: ${message}`);

    const contextPrompt = this.messages.join('\n') + '\nAssistant:';
    const result = await RunAnywhere.generate(contextPrompt);

    this.messages.push(`Assistant: ${result.text}`);
    return result.text;
  }

  /**
   * Get conversation history
   */
  get history(): string[] {
    return [...this.messages];
  }

  /**
   * Clear conversation
   */
  clear(): void {
    this.messages = [];
  }
}

// ============================================================================
// RunAnywhere SDK
// ============================================================================

/**
 * The RunAnywhere SDK for React Native
 *
 * Provides on-device AI capabilities with intelligent routing between
 * on-device and cloud execution for optimal cost and privacy.
 *
 * @example
 * ```typescript
 * // Initialize the SDK
 * await RunAnywhere.initialize({
 *   apiKey: 'your-api-key',
 *   baseURL: 'https://api.runanywhere.com',
 *   environment: SDKEnvironment.Production,
 * });
 *
 * // Simple chat
 * const response = await RunAnywhere.chat('Hello, how are you?');
 *
 * // With options
 * const result = await RunAnywhere.generate('Explain quantum computing', {
 *   maxTokens: 200,
 *   temperature: 0.7,
 * });
 *
 * // Subscribe to events
 * const unsubscribe = RunAnywhere.events.onGeneration((event) => {
 *   console.log('Generation event:', event);
 * });
 * ```
 */
export const RunAnywhere = {
  // ============================================================================
  // Event Access
  // ============================================================================

  /**
   * Access to all SDK events for subscription-based patterns
   */
  events: EventBus,

  // ============================================================================
  // SDK Initialization
  // ============================================================================

  /**
   * Initialize the RunAnywhere SDK
   *
   * This method performs simple, fast initialization:
   *
   * 1. **Validation**: Validate API key and parameters
   * 2. **Logging**: Initialize logging system based on environment
   * 3. **Storage**: Store parameters locally
   * 4. **State**: Mark SDK as initialized
   *
   * Device registration happens lazily on first API call.
   *
   * @param options - SDK initialization options
   * @throws SDKError if initialization fails
   *
   * @example
   * ```typescript
   * await RunAnywhere.initialize({
   *   apiKey: 'your-api-key',
   *   baseURL: 'https://api.runanywhere.com',
   *   environment: SDKEnvironment.Production,
   * });
   * ```
   */
  async initialize(options: SDKInitOptions): Promise<void> {
    const environment = options.environment ?? SDKEnvironment.Production;

    // Check if native module is available and has the initialize method
    if (!isNativeModuleAvailable()) {
      // In development mode without native module, just log and continue
      // This allows the app to run in a limited capacity for development
      if (__DEV__) {
        console.warn(
          '[RunAnywhere] Native module not available. ' +
            'Running in limited development mode. ' +
            'Build the native module for full functionality.'
        );
      }
      // Store initialization state in JS for development
      (this as any)._initialized = true;
      (this as any)._environment = environment;
      return;
    }

    // Get native module and check if required methods exist
    const native = requireNativeModule();
    if (typeof native.createBackend !== 'function' || typeof native.initialize !== 'function') {
      // Native module exists but required methods are not available
      // This can happen with TurboModules that aren't fully set up
      if (__DEV__) {
        console.warn(
          '[RunAnywhere] Native module found but required methods not available. ' +
            'Running in limited development mode.'
        );
      }
      (this as any)._initialized = true;
      (this as any)._environment = environment;
      return;
    }

    // First, create the ONNX backend
    // The native initialize method requires a backend to exist
    const backendCreated = await native.createBackend('onnx');
    if (!backendCreated) {
      if (__DEV__) {
        console.warn('[RunAnywhere] Failed to create backend, running in limited mode');
        (this as any)._initialized = true;
        (this as any)._environment = environment;
        return;
      }
      throw new Error('Failed to create backend');
    }

    // Native initialize expects JSON config string
    const configJson = JSON.stringify({
      apiKey: options.apiKey,
      baseURL: options.baseURL,
      environment: environment,
    });

    const result = await native.initialize(configJson);
    if (!result) {
      if (__DEV__) {
        // In development mode, continue even if initialize returns false
        // This allows testing without full backend setup
        console.warn('[RunAnywhere] Native initialize returned false, continuing in dev mode');
        (this as any)._initialized = true;
        (this as any)._environment = environment;
        return;
      }
      throw new Error('Failed to initialize SDK');
    }

    (this as any)._initialized = true;
    (this as any)._environment = environment;
  },

  /**
   * Reset SDK state
   * Clears all initialization state and cached data
   */
  async reset(): Promise<void> {
    const native = requireNativeModule();
    await native.reset();
  },

  /**
   * Check if SDK is initialized
   */
  async isInitialized(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isInitialized();
  },

  /**
   * Check if SDK is active and ready for use
   */
  async isActive(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isActive();
  },

  // ============================================================================
  // Identity
  // ============================================================================

  /**
   * Get current user ID
   */
  async getUserId(): Promise<string | null> {
    const native = requireNativeModule();
    return native.getUserId();
  },

  /**
   * Get current organization ID
   */
  async getOrganizationId(): Promise<string | null> {
    const native = requireNativeModule();
    return native.getOrganizationId();
  },

  /**
   * Get device ID
   */
  async getDeviceId(): Promise<string | null> {
    const native = requireNativeModule();
    return native.getDeviceId();
  },

  /**
   * Get SDK version
   */
  async getSDKVersion(): Promise<string> {
    const native = requireNativeModule();
    return native.getSDKVersion();
  },

  /**
   * Get current environment
   */
  async getCurrentEnvironment(): Promise<SDKEnvironment | null> {
    const native = requireNativeModule();
    return native.getCurrentEnvironment();
  },

  /**
   * Check if device is registered
   */
  async isDeviceRegistered(): Promise<boolean> {
    const native = requireNativeModule();
    return native.isDeviceRegistered();
  },

  // ============================================================================
  // Text Generation
  // ============================================================================

  /**
   * Simple text generation
   *
   * @param prompt - The text prompt
   * @returns Generated response (text only)
   *
   * @example
   * ```typescript
   * const response = await RunAnywhere.chat('Hello, how are you?');
   * console.log(response);
   * ```
   */
  async chat(prompt: string): Promise<string> {
    const native = requireNativeModule();
    return native.chat(prompt);
  },

  /**
   * Text generation with options and full metrics
   *
   * @param prompt - The text prompt
   * @param options - Generation options
   * @returns GenerationResult with full metrics
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.generate('Explain quantum computing', {
   *   maxTokens: 200,
   *   temperature: 0.7,
   * });
   * console.log('Text:', result.text);
   * console.log('Tokens:', result.tokensUsed);
   * console.log('Speed:', result.performanceMetrics.tokensPerSecond, 'tok/s');
   * ```
   */
  async generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult> {
    const native = requireNativeModule();
    return native.generate(prompt, options);
  },

  /**
   * Streaming text generation
   *
   * Starts a streaming generation session. Tokens are delivered via events.
   *
   * @param prompt - The text prompt
   * @param options - Generation options
   * @returns Session ID for the stream
   *
   * @example
   * ```typescript
   * // Subscribe to token events
   * const unsubscribe = RunAnywhere.events.onGeneration((event) => {
   *   if (event.type === 'tokenGenerated') {
   *     process.stdout.write(event.token);
   *   }
   *   if (event.type === 'completed') {
   *     console.log('\nDone!');
   *   }
   * });
   *
   * // Start streaming
   * const sessionId = await RunAnywhere.generateStream('Tell me a story');
   *
   * // Later: cancel if needed
   * await RunAnywhere.cancelStream(sessionId);
   * ```
   */
  async generateStream(prompt: string, options?: GenerationOptions): Promise<string> {
    const native = requireNativeModule();
    return native.generateStreamStart(prompt, options);
  },

  /**
   * Cancel a streaming generation session
   */
  async cancelStream(sessionId: string): Promise<void> {
    const native = requireNativeModule();
    return native.generateStreamCancel(sessionId);
  },

  // ============================================================================
  // Model Management
  // ============================================================================

  /**
   * Load a model by ID
   *
   * @param modelId - The model identifier
   *
   * @example
   * ```typescript
   * await RunAnywhere.loadModel('llama-3.2-1b');
   * ```
   */
  async loadModel(modelId: string): Promise<void> {
    const native = requireNativeModule();
    return native.loadModel(modelId);
  },

  /**
   * Get available models
   *
   * @returns Array of available models
   */
  async availableModels(): Promise<ModelInfo[]> {
    const native = requireNativeModule();
    return native.availableModels();
  },

  /**
   * Get currently loaded model
   */
  async currentModel(): Promise<ModelInfo | null> {
    const native = requireNativeModule();
    return native.currentModel();
  },

  /**
   * Download a model
   *
   * Progress is reported via model events.
   *
   * @param modelId - The model identifier
   *
   * @example
   * ```typescript
   * // Subscribe to download progress
   * RunAnywhere.events.onModel((event) => {
   *   if (event.type === 'downloadProgress') {
   *     console.log(`Downloading: ${event.progress * 100}%`);
   *   }
   * });
   *
   * await RunAnywhere.downloadModel('llama-3.2-1b');
   * ```
   */
  async downloadModel(modelId: string): Promise<void> {
    const native = requireNativeModule();
    return native.downloadModel(modelId);
  },

  /**
   * Delete a downloaded model
   *
   * @param modelId - The model identifier
   */
  async deleteModel(modelId: string): Promise<void> {
    const native = requireNativeModule();
    return native.deleteModel(modelId);
  },

  /**
   * Get available adapters for a model
   *
   * @param modelId - The model identifier
   * @returns Array of framework types that can handle this model
   */
  async availableAdapters(modelId: string): Promise<LLMFramework[]> {
    const native = requireNativeModule();
    return native.availableAdapters(modelId);
  },

  // ============================================================================
  // Voice Operations
  // ============================================================================

  /**
   * Transcribe audio data
   *
   * @param audioData - Audio data (base64 encoded or ArrayBuffer)
   * @param options - STT options
   * @returns Transcription result
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.transcribe(audioBase64);
   * console.log('Transcript:', result.text);
   * ```
   */
  async transcribe(
    audioData: string | ArrayBuffer,
    options?: STTOptions
  ): Promise<STTResult> {
    const native = requireNativeModule();

    // Convert ArrayBuffer to base64 if needed
    let audioBase64: string;
    if (typeof audioData === 'string') {
      audioBase64 = audioData;
    } else {
      // Convert ArrayBuffer to base64
      const bytes = new Uint8Array(audioData);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]!);
      }
      audioBase64 = btoa(binary);
    }

    return native.transcribe(audioBase64, options);
  },

  /**
   * Load an STT (Speech-to-Text) model
   *
   * @param modelId - The model identifier
   */
  async loadSTTModel(modelId: string): Promise<void> {
    const native = requireNativeModule();
    return native.loadSTTModel(modelId);
  },

  /**
   * Load a TTS (Text-to-Speech) model
   *
   * @param modelId - The model/voice identifier
   */
  async loadTTSModel(modelId: string): Promise<void> {
    const native = requireNativeModule();
    return native.loadTTSModel(modelId);
  },

  /**
   * Synthesize text to speech
   *
   * @param text - Text to synthesize
   * @param configuration - TTS configuration
   * @returns Base64 encoded audio data
   *
   * @example
   * ```typescript
   * const audioBase64 = await RunAnywhere.synthesize('Hello, world!', {
   *   voice: 'en-US-default',
   *   rate: 1.0,
   * });
   * ```
   */
  async synthesize(text: string, configuration?: TTSConfiguration): Promise<string> {
    const native = requireNativeModule();
    return native.synthesize(text, configuration);
  },

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Estimate token count in text
   *
   * @param text - The text to analyze
   * @returns Estimated number of tokens
   *
   * @example
   * ```typescript
   * const tokenCount = await RunAnywhere.estimateTokenCount('Hello world');
   * console.log('Tokens:', tokenCount);
   * ```
   */
  async estimateTokenCount(text: string): Promise<number> {
    const native = requireNativeModule();
    return native.estimateTokenCount(text);
  },

  // ============================================================================
  // Factory Methods
  // ============================================================================

  /**
   * Create a new conversation
   *
   * @returns A new Conversation instance
   *
   * @example
   * ```typescript
   * const conversation = RunAnywhere.conversation();
   * const response1 = await conversation.send('Hello!');
   * const response2 = await conversation.send('What did I just say?');
   * ```
   */
  conversation(): Conversation {
    return new Conversation();
  },
};

// Default export
export default RunAnywhere;
