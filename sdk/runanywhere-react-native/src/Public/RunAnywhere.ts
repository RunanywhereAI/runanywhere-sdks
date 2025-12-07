/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * The clean, event-based RunAnywhere SDK for React Native.
 * Single entry point with both event-driven and async/await patterns.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { EventBus } from './Events';
import { requireNativeModule, isNativeModuleAvailable, NativeRunAnywhere, requireFileSystemModule } from '../native';
import { SDKEnvironment, ExecutionTarget, HardwareAcceleration } from '../types';
import { ModelRegistry } from '../services/ModelRegistry';
import type {
  GenerationOptions,
  GenerationResult,
  SDKInitOptions,
  STTOptions,
  STTResult,
  TTSConfiguration,
  TTSResult,
  ModelInfo,
} from '../types';

// ============================================================================
// Internal State
// ============================================================================

interface SDKState {
  initialized: boolean;
  environment: SDKEnvironment | null;
  backendType: string | null;
}

const state: SDKState = {
  initialized: false,
  environment: null,
  backendType: null,
};

// Track active downloads for cancellation
const activeDownloads = new Map<string, number>();

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
 * const result = await RunAnywhere.generate('Hello, how are you?');
 * console.log(result.text);
 *
 * // Subscribe to generation events
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
  // SDK State
  // ============================================================================

  /**
   * Check if SDK is initialized
   */
  get isSDKInitialized(): boolean {
    return state.initialized;
  },

  /**
   * Get current environment
   */
  get currentEnvironment(): SDKEnvironment | null {
    return state.environment;
  },

  // ============================================================================
  // SDK Initialization
  // ============================================================================

  /**
   * Initialize the RunAnywhere SDK
   *
   * This method performs simple, fast initialization:
   *
   * 1. **Validation**: Validate API key and parameters
   * 2. **Backend**: Create the native backend (ONNX by default)
   * 3. **Configuration**: Pass configuration to native layer
   * 4. **State**: Mark SDK as initialized
   *
   * @param options - SDK initialization options
   * @throws Error if initialization fails
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

    // Publish initialization started event
    EventBus.publish('Initialization', { type: 'started' });

    // Check if native module is available
    if (!isNativeModuleAvailable()) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        console.warn(
          '[RunAnywhere] Native module not available. ' +
            'Running in limited development mode.'
        );
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        return;
      }
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();

    // Create the backend
    // Use llamacpp for LLM text generation (GGUF models), which also supports other capabilities
    const backendName = 'llamacpp';
    try {
      const backendCreated = native.createBackend(backendName);
      if (!backendCreated) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          console.warn('[RunAnywhere] Failed to create backend, running in limited mode');
          state.initialized = true;
          state.environment = environment;
          state.backendType = null;
          EventBus.publish('Initialization', { type: 'completed' });
          return;
        }
        throw new Error('Failed to create backend');
      }
      state.backendType = backendName;
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        console.warn('[RunAnywhere] Backend creation error:', error);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        return;
      }
      throw error;
    }

    // Initialize with configuration
    try {
      const configJson = JSON.stringify({
        apiKey: options.apiKey,
        baseURL: options.baseURL,
        environment: environment,
      });

      const result = native.initialize(configJson);
      if (!result) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          console.warn('[RunAnywhere] Native initialize returned false, continuing in dev mode');
          state.initialized = true;
          state.environment = environment;
          EventBus.publish('Initialization', { type: 'completed' });
          return;
        }
        throw new Error('Failed to initialize SDK');
      }
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        console.warn('[RunAnywhere] Initialize error:', error);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        return;
      }
      throw error;
    }

    // Register framework providers (same pattern as Swift SDK)
    // This must happen BEFORE ModelRegistry.initialize() so models can be registered
    console.log('[RunAnywhere] Registering framework providers...');
    try {
      // Register LlamaCPP provider for GGUF models
      const { LlamaCppProvider } = require('../Providers/LlamaCppProvider');
      LlamaCppProvider.register();
      console.log('[RunAnywhere] LlamaCPP provider registered');
    } catch (error) {
      console.warn('[RunAnywhere] Failed to register LlamaCPP provider:', error);
    }

    try {
      // Register ONNX providers for STT/TTS models (mirrors Swift SDK's ONNXAdapter.register())
      const { registerONNXProviders } = require('../Providers/ONNXProvider');
      registerONNXProviders();
      console.log('[RunAnywhere] ONNX providers registered');
    } catch (error) {
      console.warn('[RunAnywhere] Failed to register ONNX providers:', error);
    }

    // Initialize the Model Registry (same pattern as Swift SDK)
    // This loads the catalog models AND models provided by registered providers
    try {
      await ModelRegistry.initialize();
      console.log('[RunAnywhere] Model Registry initialized successfully');
    } catch (error) {
      console.warn('[RunAnywhere] Model Registry initialization failed (non-critical):', error);
      // Don't fail SDK initialization if model registry fails
      // Models can still be added manually via addModelFromURL
    }

    state.initialized = true;
    state.environment = environment;
    EventBus.publish('Initialization', { type: 'completed' });
  },

  /**
   * Destroy SDK and release resources
   */
  async destroy(): Promise<void> {
    if (!isNativeModuleAvailable()) {
      state.initialized = false;
      state.environment = null;
      state.backendType = null;
      return;
    }

    const native = requireNativeModule();
    await native.destroy();
    state.initialized = false;
    state.environment = null;
    state.backendType = null;
  },

  /**
   * Check if SDK is initialized (async version for native query)
   */
  async isInitialized(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return state.initialized;
    }
    const native = requireNativeModule();
    return native.isInitialized();
  },

  /**
   * Get SDK version
   */
  async getVersion(): Promise<string> {
    // Version is managed at the JS layer
    return '0.1.0';
  },

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /**
   * Load a text generation model
   *
   * @param modelPath - Path to the model file
   * @param config - Optional configuration
   */
  async loadTextModel(modelPath: string, config?: Record<string, unknown>): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      console.warn('[RunAnywhere] Native module not available for loadTextModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadTextModel(modelPath, config ? JSON.stringify(config) : undefined);
  },

  /**
   * Check if a text model is loaded
   */
  async isTextModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isTextModelLoaded();
  },

  /**
   * Unload the current text model
   */
  async unloadTextModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadTextModel();
  },

  /**
   * Simple chat - returns just the text response
   * Matches Swift SDK: RunAnywhere.chat(_:)
   *
   * @param prompt - The chat prompt
   * @returns The generated text response
   *
   * @example
   * ```typescript
   * const response = await RunAnywhere.chat('Hello, how are you?');
   * console.log(response);
   * ```
   */
  async chat(prompt: string): Promise<string> {
    const result = await this.generate(prompt);
    return result.text;
  },

  /**
   * Text generation with options and full metrics
   * Matches Swift SDK: RunAnywhere.generate(_:options:)
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
   * ```
   */
  async generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    // Build options JSON for native generateText
    const optionsJson = JSON.stringify({
      max_tokens: options?.maxTokens ?? 256,
      temperature: options?.temperature ?? 0.7,
      system_prompt: options?.systemPrompt ?? null,
    });

    const resultJson = await native.generate(prompt, optionsJson);

    try {
      const result = JSON.parse(resultJson);
      return {
        text: result.text ?? '',
        thinkingContent: result.thinkingContent,
        tokensUsed: result.tokensUsed ?? 0,
        modelUsed: result.modelUsed ?? 'unknown',
        latencyMs: result.latencyMs ?? 0,
        executionTarget: result.executionTarget ?? 0,
        savedAmount: result.savedAmount ?? 0,
        framework: result.framework,
        hardwareUsed: result.hardwareUsed ?? 0,
        memoryUsed: result.memoryUsed ?? 0,
        performanceMetrics: {
          timeToFirstTokenMs: result.performanceMetrics?.timeToFirstTokenMs,
          tokensPerSecond: result.performanceMetrics?.tokensPerSecond,
          inferenceTimeMs: result.performanceMetrics?.inferenceTimeMs ?? result.latencyMs ?? 0,
        },
        thinkingTokens: result.thinkingTokens,
        responseTokens: result.responseTokens ?? result.tokensUsed ?? 0,
      };
    } catch {
      // If parsing fails, treat as error message
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        text: resultJson,
        tokensUsed: 0,
        modelUsed: 'unknown',
        latencyMs: 0,
        executionTarget: ExecutionTarget.OnDevice,
        savedAmount: 0,
        hardwareUsed: HardwareAcceleration.CPU,
        memoryUsed: 0,
        performanceMetrics: {
          inferenceTimeMs: 0,
        },
        responseTokens: 0,
      };
    }
  },

  /**
   * Streaming text generation
   *
   * Starts a streaming generation session. Tokens are delivered via events.
   *
   * @param prompt - The text prompt
   * @param options - Generation options
   * @param onToken - Callback for each token
   *
   * @example
   * ```typescript
   * RunAnywhere.generateStream('Tell me a story', {}, (token) => {
   *   process.stdout.write(token);
   * });
   * ```
   */
  generateStream(
    prompt: string,
    options?: GenerationOptions,
    onToken?: (token: string) => void
  ): void {
    if (!isNativeModuleAvailable()) {
      EventBus.publish('Generation', { type: 'failed', error: 'Native module not available' });
      return;
    }
    const native = requireNativeModule();

    const maxTokens = options?.maxTokens ?? 256;
    const temperature = options?.temperature ?? 0.7;
    const systemPrompt = options?.systemPrompt ?? null;

    // Subscribe to generation events if callback provided
    if (onToken) {
      const unsubscribe = EventBus.onGeneration((event) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const evt = event as any;
        if (evt.type === 'tokenGenerated' && evt.token) {
          onToken(evt.token);
        } else if (evt.type === 'completed' || evt.type === 'failed') {
          unsubscribe();
        }
      });
    }

    native.generateStream(prompt, systemPrompt, maxTokens, temperature);
  },

  /**
   * Cancel ongoing text generation
   */
  cancelGeneration(): void {
    if (!isNativeModuleAvailable()) {
      return;
    }
    const native = requireNativeModule();
    native.cancelGeneration();
  },

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  /**
   * Load an STT model
   *
   * @param modelPath - Path to the model file
   * @param modelType - Model type (e.g., 'whisper', 'sherpa')
   * @param config - Optional configuration
   */
  async loadSTTModel(
    modelPath: string,
    modelType: string = 'whisper',
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      console.warn('[RunAnywhere] Native module not available for loadSTTModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadSTTModel(modelPath, modelType, config ? JSON.stringify(config) : undefined);
  },

  /**
   * Check if an STT model is loaded
   */
  async isSTTModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isSTTModelLoaded();
  },

  /**
   * Unload the current STT model
   */
  async unloadSTTModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadSTTModel();
  },

  /**
   * Transcribe audio data
   *
   * @param audioData - Audio data (base64 encoded or ArrayBuffer)
   * @param options - STT options
   * @returns Transcription result
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.transcribe(audioBase64, { language: 'en' });
   * console.log('Transcript:', result.text);
   * ```
   */
  async transcribe(
    audioData: string | ArrayBuffer,
    options?: STTOptions
  ): Promise<STTResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    // Convert ArrayBuffer to base64 if needed
    let audioBase64: string;
    if (typeof audioData === 'string') {
      audioBase64 = audioData;
    } else {
      const bytes = new Uint8Array(audioData);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]!);
      }
      audioBase64 = btoa(binary);
    }

    const sampleRate = options?.sampleRate ?? 16000;
    const language = options?.language;

    const resultJson = await native.transcribe(audioBase64, sampleRate, language);

    try {
      const result = JSON.parse(resultJson);
      return {
        text: result.text ?? '',
        segments: result.segments ?? [],
        language: result.language,
        confidence: result.confidence ?? 1.0,
        duration: result.duration ?? 0,
        alternatives: result.alternatives ?? [],
      };
    } catch {
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        text: resultJson,
        segments: [],
        confidence: 1.0,
        duration: 0,
        alternatives: [],
      };
    }
  },

  /**
   * Transcribe audio from a file path.
   * Automatically handles format conversion to 16kHz mono PCM.
   * Supports various audio formats (M4A, AAC, WAV, CAF, etc.)
   *
   * @param filePath - Path to the audio file
   * @param options - STT options (language, etc.)
   * @returns Transcription result
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.transcribeFile('/path/to/audio.m4a', { language: 'en' });
   * console.log('Transcript:', result.text);
   * ```
   */
  async transcribeFile(
    filePath: string,
    options?: STTOptions
  ): Promise<STTResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    const language = options?.language ?? null;
    const resultJson = await native.transcribeFile(filePath, language);

    try {
      const result = JSON.parse(resultJson);
      if (result.error) {
        throw new Error(result.error);
      }
      return {
        text: result.text ?? '',
        segments: result.segments ?? [],
        language: result.language,
        confidence: result.confidence ?? 1.0,
        duration: result.duration ?? 0,
        alternatives: result.alternatives ?? [],
      };
    } catch (e) {
      if (resultJson.includes('error')) {
        const errorMatch = resultJson.match(/"error":\s*"([^"]+)"/);
        throw new Error(errorMatch ? errorMatch[1] : resultJson);
      }
      return {
        text: resultJson,
        segments: [],
        confidence: 1.0,
        duration: 0,
        alternatives: [],
      };
    }
  },

  // ============================================================================
  // Streaming STT (Real-time transcription with AVAudioEngine)
  // ============================================================================

  /**
   * Start streaming speech-to-text transcription
   *
   * Uses AVAudioEngine for real-time audio capture at 16kHz mono.
   * Transcription results are delivered via events:
   * - onSTTPartial: Partial results as audio is processed
   * - onSTTFinal: Final result when streaming stops
   * - onSTTError: Error during transcription
   *
   * @param language - Language code (e.g., 'en')
   * @param onPartial - Callback for partial transcription results
   * @param onFinal - Callback for final transcription result
   * @param onError - Callback for errors
   * @returns true if streaming started successfully
   *
   * @example
   * ```typescript
   * await RunAnywhere.startStreamingSTT('en',
   *   (text) => console.log('Partial:', text),
   *   (text) => console.log('Final:', text),
   *   (error) => console.error('Error:', error)
   * );
   * // ... user speaks ...
   * await RunAnywhere.stopStreamingSTT();
   * ```
   */
  async startStreamingSTT(
    language: string = 'en',
    onPartial?: (text: string, confidence: number) => void,
    onFinal?: (text: string, confidence: number) => void,
    onError?: (error: string) => void
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      console.warn('[RunAnywhere] Native module not available for startStreamingSTT');
      return false;
    }
    const native = requireNativeModule();

    // Subscribe to Voice/STT events
    if (onPartial || onFinal || onError) {
      EventBus.onVoice((event) => {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const evt = event as any;
        if (evt.type === 'sttPartialResult' && onPartial) {
          onPartial(evt.text || '', evt.confidence || 0);
        } else if (evt.type === 'sttCompleted' && onFinal) {
          onFinal(evt.text || '', evt.confidence || 0);
        } else if (evt.type === 'sttFailed' && onError) {
          onError(evt.error || 'Unknown error');
        }
      });
    }

    return native.startStreamingSTT(language);
  },

  /**
   * Stop streaming speech-to-text transcription
   *
   * Stops audio capture and processing. Any remaining audio will be
   * transcribed and delivered via the onSTTFinal event.
   *
   * @returns true if streaming was stopped successfully
   */
  async stopStreamingSTT(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.stopStreamingSTT();
  },

  /**
   * Check if streaming STT is currently active
   *
   * @returns true if streaming is active
   */
  async isStreamingSTT(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isStreamingSTT();
  },

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  /**
   * Load a TTS model
   *
   * @param modelPath - Path to the model file
   * @param modelType - Model type (e.g., 'piper', 'vits')
   * @param config - Optional configuration
   */
  async loadTTSModel(
    modelPath: string,
    modelType: string = 'piper',
    config?: Record<string, unknown>
  ): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      console.warn('[RunAnywhere] Native module not available for loadTTSModel');
      return false;
    }
    const native = requireNativeModule();
    return native.loadTTSModel(modelPath, modelType, config ? JSON.stringify(config) : undefined);
  },

  /**
   * Check if a TTS model is loaded
   */
  async isTTSModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isTTSModelLoaded();
  },

  /**
   * Unload the current TTS model
   */
  async unloadTTSModel(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.unloadTTSModel();
  },

  /**
   * Synthesize text to speech
   *
   * @param text - Text to synthesize
   * @param configuration - TTS configuration
   * @returns TTS result with audio data
   *
   * @example
   * ```typescript
   * const result = await RunAnywhere.synthesize('Hello, world!', {
   *   voice: 'en-US-default',
   *   rate: 1.0,
   * });
   * // result.audio is base64 encoded audio
   * ```
   */
  async synthesize(text: string, configuration?: TTSConfiguration): Promise<TTSResult> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }
    const native = requireNativeModule();

    const voiceId = configuration?.voice ?? null;
    const speedRate = configuration?.rate ?? 1.0;
    const pitchShift = configuration?.pitch ?? 1.0;

    const resultJson = await native.synthesize(text, voiceId, speedRate, pitchShift);

    try {
      const result = JSON.parse(resultJson);
      return {
        audio: result.audio ?? '',
        sampleRate: result.sampleRate ?? 22050,
        numSamples: result.numSamples ?? 0,
        duration: result.numSamples ? result.numSamples / result.sampleRate : 0,
      };
    } catch {
      if (resultJson.includes('error')) {
        throw new Error(resultJson);
      }
      return {
        audio: resultJson,
        sampleRate: 22050,
        numSamples: 0,
        duration: 0,
      };
    }
  },

  /**
   * Get available TTS voices
   */
  async getTTSVoices(): Promise<string[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    const voicesJson = await native.getTTSVoices();
    try {
      return JSON.parse(voicesJson);
    } catch {
      return voicesJson ? [voicesJson] : [];
    }
  },

  /**
   * Cancel ongoing TTS synthesis
   */
  cancelTTS(): void {
    if (!isNativeModuleAvailable()) {
      return;
    }
    const native = requireNativeModule();
    native.cancelTTS();
  },

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  /**
   * Load a VAD model
   */
  async loadVADModel(modelPath: string, config?: Record<string, unknown>): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.loadVADModel(modelPath, config ? JSON.stringify(config) : undefined);
  },

  /**
   * Check if a VAD model is loaded
   */
  async isVADModelLoaded(): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.isVADModelLoaded();
  },

  /**
   * Process audio for voice activity detection
   */
  async processVAD(
    audioData: string | ArrayBuffer,
    sampleRate: number = 16000
  ): Promise<{ isSpeech: boolean; probability: number }> {
    if (!isNativeModuleAvailable()) {
      return { isSpeech: false, probability: 0 };
    }
    const native = requireNativeModule();

    let audioBase64: string;
    if (typeof audioData === 'string') {
      audioBase64 = audioData;
    } else {
      const bytes = new Uint8Array(audioData);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) {
        binary += String.fromCharCode(bytes[i]!);
      }
      audioBase64 = btoa(binary);
    }

    const resultJson = await native.processVAD(audioBase64, sampleRate);
    try {
      return JSON.parse(resultJson);
    } catch {
      return { isSpeech: false, probability: 0 };
    }
  },

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Get last error message from native layer
   */
  async getLastError(): Promise<string> {
    if (!isNativeModuleAvailable()) {
      return '';
    }
    const native = requireNativeModule();
    return native.getLastError();
  },

  /**
   * Get backend info
   */
  async getBackendInfo(): Promise<Record<string, unknown>> {
    if (!isNativeModuleAvailable()) {
      return {};
    }
    const native = requireNativeModule();
    const infoJson = await native.getBackendInfo();
    try {
      return JSON.parse(infoJson);
    } catch {
      return {};
    }
  },

  /**
   * Get supported capabilities
   */
  async getCapabilities(): Promise<number[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    return native.getCapabilities();
  },

  /**
   * Check if a capability is supported
   */
  async supportsCapability(capability: number): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }
    const native = requireNativeModule();
    return native.supportsCapability(capability);
  },

  // ============================================================================
  // Model Registry
  // ============================================================================

  /**
   * Get available models from the catalog
   *
   * This uses the JavaScript ModelRegistry service (same pattern as Swift SDK)
   * and does not require native module calls.
   *
   * @returns Array of model info objects
   *
   * @example
   * ```typescript
   * const models = await RunAnywhere.getAvailableModels();
   * const sttModels = models.filter(m => m.modality === 'stt');
   * ```
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    return ModelRegistry.getAvailableModels();
  },

  /**
   * Get available frameworks
   *
   * Returns an array of frameworks that have registered providers.
   * This matches the Swift SDK's getAvailableFrameworks() API.
   *
   * @returns Array of available frameworks
   *
   * @example
   * ```typescript
   * const frameworks = RunAnywhere.getAvailableFrameworks();
   * console.log('Available frameworks:', frameworks);
   * ```
   */
  getAvailableFrameworks(): import('../types').LLMFramework[] {
    const { ModuleRegistry } = require('../Core/ModuleRegistry');

    // Get all registered LLM providers
    const llmProviders = ModuleRegistry.shared.allLLMProviders();

    // Extract unique frameworks from models provided by each provider
    const frameworksSet = new Set<import('../types').LLMFramework>();

    for (const provider of llmProviders) {
      if (provider.getProvidedModels) {
        const models = provider.getProvidedModels();
        for (const model of models) {
          // Add all compatible frameworks
          for (const framework of model.compatibleFrameworks) {
            frameworksSet.add(framework);
          }
          // Also add preferred framework if specified
          if (model.preferredFramework) {
            frameworksSet.add(model.preferredFramework);
          }
        }
      }
    }

    return Array.from(frameworksSet);
  },

  /**
   * Get models for a specific framework
   *
   * This matches the Swift SDK's getModelsForFramework() API.
   *
   * @param framework - The framework to query
   * @returns Array of models compatible with the framework
   *
   * @example
   * ```typescript
   * const llamaCppModels = RunAnywhere.getModelsForFramework(LLMFramework.LlamaCpp);
   * ```
   */
  async getModelsForFramework(framework: import('../types').LLMFramework): Promise<ModelInfo[]> {
    const allModels = await ModelRegistry.getAvailableModels();
    return allModels.filter(model =>
      model.compatibleFrameworks.includes(framework) ||
      model.preferredFramework === framework
    );
  },

  /**
   * Get info for a specific model
   *
   * @param modelId - Model ID
   * @returns Model info or null if not found
   */
  async getModelInfo(modelId: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) {
      return null;
    }
    const native = requireNativeModule();
    const infoJson = await native.getModelInfo(modelId);
    try {
      const result = JSON.parse(infoJson);
      return result === 'null' ? null : result;
    } catch {
      return null;
    }
  },

  /**
   * Check if a model is downloaded
   *
   * @param modelId - Model ID
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    const { JSDownloadService } = require('../services/JSDownloadService');
    return JSDownloadService.isModelDownloaded(modelId);
  },

  /**
   * Get local path for a downloaded model
   *
   * @param modelId - Model ID
   * @returns Path or null if not downloaded
   */
  async getModelPath(modelId: string): Promise<string | null> {
    const { JSDownloadService } = require('../services/JSDownloadService');
    return JSDownloadService.getModelPath(modelId);
  },

  /**
   * Get list of downloaded models
   *
   * @returns Array of downloaded model info objects
   */
  async getDownloadedModels(): Promise<ModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }
    const native = requireNativeModule();
    const modelsJson = await native.getDownloadedModels();
    try {
      return JSON.parse(modelsJson);
    } catch {
      return [];
    }
  },

  // ============================================================================
  // Model Download
  // ============================================================================

  /**
   * Download a model
   *
   * Uses native OkHttp (Android) / URLSession (iOS) for maximum download speed.
   * Bypasses the React Native JS bridge for direct native file transfer.
   *
   * @param modelId - Model ID to download
   * @param onProgress - Optional progress callback
   * @returns Promise that resolves to local file path when complete
   *
   * @example
   * ```typescript
   * const localPath = await RunAnywhere.downloadModel('smollm2-360m-q8-0', (progress) => {
   *   console.log(`Progress: ${(progress.progress * 100).toFixed(1)}%`);
   * });
   * console.log('Model downloaded to:', localPath);
   * ```
   */
  async downloadModel(
    modelId: string,
    onProgress?: (progress: DownloadProgress) => void
  ): Promise<string> {
    // Get model info from registry
    const modelInfo = await ModelRegistry.getModel(modelId);
    if (!modelInfo) {
      throw new Error(`Model not found: ${modelId}`);
    }

    if (!modelInfo.downloadURL) {
      throw new Error(`Model has no download URL: ${modelId}`);
    }

    // Get native file system module for fast downloads (bypasses JS bridge)
    const fs = requireFileSystemModule();

    // Determine file name with extension
    const extension = modelInfo.downloadURL.includes('.gguf') ? '.gguf' : '';
    const fileName = `${modelId}${extension}`;

    console.log('[RunAnywhere] Starting native download (OkHttp/URLSession):', {
      modelId,
      url: modelInfo.downloadURL,
    });

    // Track download state
    activeDownloads.set(modelId, 1);
    let lastLoggedProgress = -1;

    try {
      // Use native module for maximum download speed
      // Android: OkHttp with HTTP/1.1 (faster than HTTP/2 for large files)
      // iOS: URLSession with native download task
      await fs.downloadModel(
        fileName,
        modelInfo.downloadURL,
        (progress: number) => {
          // Only log every 10% to reduce noise
          const progressPct = Math.round(progress * 100);
          if (progressPct - lastLoggedProgress >= 10) {
            console.log(`[RunAnywhere] Download progress: ${progressPct}%`);
            lastLoggedProgress = progressPct;
          }

          if (onProgress) {
            onProgress({
              modelId,
              bytesDownloaded: Math.round(progress * (modelInfo.downloadSize || 0)),
              totalBytes: modelInfo.downloadSize || 0,
              progress,
            });
          }
        }
      );

      // Get the actual path where model was downloaded
      const destPath = await fs.getModelPath(fileName);

      console.log('[RunAnywhere] Download completed:', {
        modelId,
        destPath,
      });

      // Update model registry
      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: destPath,
        isDownloaded: true,
      };
      await ModelRegistry.registerModel(updatedModel);

      return destPath;
    } finally {
      activeDownloads.delete(modelId);
    }
  },

  /**
   * Cancel an ongoing download
   *
   * @param modelId - Model ID being downloaded
   */
  async cancelDownload(modelId: string): Promise<boolean> {
    // Note: Native cancellation requires additional implementation
    if (activeDownloads.has(modelId)) {
      activeDownloads.delete(modelId);
      console.log('[RunAnywhere] Marked download as cancelled:', modelId);
      return true;
    }
    return false;
  },

  /**
   * Delete a downloaded model
   *
   * @param modelId - Model ID to delete
   */
  async deleteModel(modelId: string): Promise<boolean> {
    try {
      const fs = requireFileSystemModule();

      // Get model info to find the file name
      const modelInfo = await ModelRegistry.getModel(modelId);
      const extension = modelInfo?.downloadURL?.includes('.gguf') ? '.gguf' : '';
      const fileName = `${modelId}${extension}`;

      // Check if model exists and delete via native module
      const exists = await fs.modelExists(fileName);
      if (exists) {
        await fs.deleteModel(fileName);
        console.log('[RunAnywhere] Deleted model:', modelId);
      }

      // Also try without extension
      const existsPlain = await fs.modelExists(modelId);
      if (existsPlain) {
        await fs.deleteModel(modelId);
      }

      // Update registry
      if (modelInfo) {
        const updatedModel: ModelInfo = {
          ...modelInfo,
          localPath: undefined,
          isDownloaded: false,
        };
        await ModelRegistry.registerModel(updatedModel);
      }

      return true;
    } catch (error) {
      console.error('[RunAnywhere] Delete model error:', error);
      return false;
    }
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

// ============================================================================
// Types for Model Registry/Download
// ============================================================================

/**
 * Model information from the catalog
 * Re-exported from types/models.ts
 */
export type { ModelInfo } from '../types/models';

/**
 * Download progress information
 */
export interface DownloadProgress {
  modelId: string;
  bytesDownloaded: number;
  totalBytes: number;
  progress: number;
}

// Default export
export default RunAnywhere;
