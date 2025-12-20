/**
 * VoiceAgentCapability.ts
 *
 * Voice Agent capability that orchestrates VAD, STT, LLM, and TTS capabilities.
 * Implements CompositeCapability - delegates lifecycle management to child capabilities.
 *
 * Key iOS parity:
 * - VoiceAgent does NOT have its own ManagedLifecycle
 * - VoiceAgent delegates model loading to child capabilities
 * - Smart model reuse: checks if model already loaded before reloading
 * - Pipeline event emission via EventPublisher
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { CompositeCapability } from '../../Core/Capabilities/CapabilityProtocols';
import { CapabilityError } from '../../Core/Capabilities/CapabilityProtocols';
import { EventPublisher } from '../../Infrastructure/Events/EventPublisher';
import {
  createVoicePipelineStartedEvent,
  createVoicePipelineCompletedEvent,
  createVoicePipelineFailedEvent,
  createSpeechDetectedEvent,
  createSpeechEndedEvent,
} from '../../Infrastructure/Events/CommonEvents';
import type { VoiceAgentConfiguration } from './VoiceAgentConfiguration';
import type {
  VoiceAgentResult,
  VoiceAgentComponentStates,
  VoiceAgentStreamEvent,
} from './VoiceAgentModels';
import {
  VoiceAgentError,
  notLoadedState,
  loadingComponentState,
  loadedComponentState,
  errorComponentState,
  isVoiceAgentFullyReady,
} from './VoiceAgentModels';
import { STTCapability } from '../STT/STTCapability';
import { LLMCapability } from '../LLM/LLMCapability';
import { TTSCapability } from '../TTS/TTSCapability';
import { VADCapability, type VADInput } from '../VAD/VADCapability';
import type { STTConfiguration } from '../STT/STTConfiguration';
import type { LLMConfiguration } from '../LLM/LLMConfiguration';
import type { TTSConfiguration } from '../TTS/TTSConfiguration';
import type { VADConfiguration } from '../VAD/VADConfiguration';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

// ============================================================================
// Voice Agent Capability
// ============================================================================

/**
 * Voice Agent capability - a composite capability that orchestrates
 * VAD, STT, LLM, and TTS capabilities for a complete voice AI pipeline.
 *
 * Implements CompositeCapability:
 * - Does NOT have its own ManagedLifecycle
 * - Delegates model loading to child capabilities
 * - Tracks isConfigured flag for initialization state
 *
 * Initialization order: VAD → STT → LLM → TTS
 */
export class VoiceAgentCapability implements CompositeCapability {
  // ============================================================================
  // Static Properties
  // ============================================================================

  public static readonly componentType: SDKComponent = SDKComponent.VoiceAgent;

  // ============================================================================
  // Private Properties
  // ============================================================================

  private readonly logger = new SDKLogger('VoiceAgent');
  private readonly eventPublisher = EventPublisher.shared;

  // Child capabilities (owned by VoiceAgent)
  private vadCapability: VADCapability | null = null;
  private sttCapability: STTCapability | null = null;
  private llmCapability: LLMCapability | null = null;
  private ttsCapability: TTSCapability | null = null;

  // Configuration
  private readonly configuration: VoiceAgentConfiguration;

  // State (matches iOS: only tracks isConfigured flag)
  private isConfigured = false;
  private isProcessing = false;

  // ============================================================================
  // Constructor
  // ============================================================================

  /**
   * Create a VoiceAgentCapability with child capabilities.
   *
   * @param configuration - Full voice agent configuration including all child configs
   */
  constructor(configuration: VoiceAgentConfiguration) {
    this.configuration = configuration;
  }

  // ============================================================================
  // CompositeCapability Conformance
  // ============================================================================

  /**
   * Whether the voice agent is fully initialized and ready to process.
   * Matches iOS CompositeCapability.isReady
   */
  public get isReady(): boolean {
    return this.isConfigured;
  }

  /**
   * Clean up all child capabilities.
   * Matches iOS CompositeCapability.cleanup()
   */
  public async cleanup(): Promise<void> {
    this.logger.info('Cleaning up voice agent...');
    this.isProcessing = false;
    this.isConfigured = false;

    // Cleanup all child capabilities in parallel (errors are caught individually)
    const cleanupTasks = [
      this.safeCleanup(this.vadCapability, 'VAD'),
      this.safeCleanup(this.sttCapability, 'STT'),
      this.safeCleanup(this.llmCapability, 'LLM'),
      this.safeCleanup(this.ttsCapability, 'TTS'),
    ];

    await Promise.all(cleanupTasks);

    // Release references
    this.vadCapability = null;
    this.sttCapability = null;
    this.llmCapability = null;
    this.ttsCapability = null;

    this.logger.info('Voice agent cleanup complete');
  }

  private async safeCleanup(
    capability: { cleanup(): Promise<void> } | null,
    name: string
  ): Promise<void> {
    if (!capability) return;
    try {
      await capability.cleanup();
    } catch (error) {
      this.logger.warning(`${name} cleanup failed: ${error}`);
    }
  }

  // ============================================================================
  // Initialization Methods (iOS Parity)
  // ============================================================================

  /**
   * Initialize with full configuration.
   * Matches iOS: initialize(_ config: VoiceAgentConfiguration)
   *
   * @param config - Optional override configuration (uses constructor config if not provided)
   */
  public async initialize(config?: VoiceAgentConfiguration): Promise<void> {
    const cfg = config ?? this.configuration;

    this.logger.info('Initializing voice agent with full configuration...');

    try {
      // Create child capabilities
      this.vadCapability = new VADCapability(cfg.vadConfig as VADConfiguration);
      this.sttCapability = new STTCapability(cfg.sttConfig);
      this.llmCapability = new LLMCapability(cfg.llmConfig);
      this.ttsCapability = new TTSCapability(cfg.ttsConfig);

      // Initialize in order: VAD → STT → LLM → TTS
      await this.initializeVAD(cfg.vadConfig);
      await this.initializeSTT(cfg.sttConfig);
      await this.initializeLLM(cfg.llmConfig);
      await this.initializeTTS(cfg.ttsConfig);

      // Verify all components ready
      this.verifyAllComponentsReady();

      this.isConfigured = true;
      this.logger.info('Voice agent initialization complete');
    } catch (error) {
      this.logger.error(`Voice agent initialization failed: ${error}`);
      throw error;
    }
  }

  /**
   * Initialize with model IDs (convenience method).
   * Matches iOS: initialize(sttModelId:llmModelId:ttsVoice:)
   *
   * @param sttModelId - STT model identifier
   * @param llmModelId - LLM model identifier
   * @param ttsVoice - TTS voice identifier (optional)
   */
  public async initializeWithModelIds(
    sttModelId: string,
    llmModelId: string,
    ttsVoice = ''
  ): Promise<void> {
    this.logger.info(`Initializing voice agent with models: STT=${sttModelId}, LLM=${llmModelId}, TTS=${ttsVoice || 'default'}`);

    try {
      // Create child capabilities if not already created
      if (!this.vadCapability) {
        this.vadCapability = new VADCapability(this.configuration.vadConfig as VADConfiguration);
      }
      if (!this.sttCapability) {
        this.sttCapability = new STTCapability(this.configuration.sttConfig);
      }
      if (!this.llmCapability) {
        this.llmCapability = new LLMCapability(this.configuration.llmConfig);
      }
      if (!this.ttsCapability) {
        this.ttsCapability = new TTSCapability(this.configuration.ttsConfig);
      }

      // Initialize VAD first
      await this.initializeVAD(this.configuration.vadConfig);

      // Load models with smart reuse
      await this.loadSTTWithReuse(sttModelId);
      await this.loadLLMWithReuse(llmModelId);
      if (ttsVoice) {
        await this.loadTTSWithReuse(ttsVoice);
      }

      // Verify all components ready
      this.verifyAllComponentsReady();

      this.isConfigured = true;
      this.logger.info('Voice agent initialization complete');
    } catch (error) {
      this.logger.error(`Voice agent initialization failed: ${error}`);
      throw error;
    }
  }

  /**
   * Initialize using already-loaded models from child capabilities.
   * Matches iOS: initializeWithLoadedModels()
   *
   * Use this when child capabilities are already configured with loaded models.
   */
  public async initializeWithLoadedModels(): Promise<void> {
    this.logger.info('Initializing voice agent with pre-loaded models...');

    if (!this.sttCapability || !this.llmCapability || !this.ttsCapability || !this.vadCapability) {
      throw VoiceAgentError.notInitialized();
    }

    // Verify models are loaded
    if (!this.sttCapability.isModelLoaded) {
      throw VoiceAgentError.componentFailed('STT', new Error('STT model not loaded'));
    }
    if (!this.llmCapability.isModelLoaded) {
      throw VoiceAgentError.componentFailed('LLM', new Error('LLM model not loaded'));
    }
    if (!this.ttsCapability.isModelLoaded) {
      throw VoiceAgentError.componentFailed('TTS', new Error('TTS model not loaded'));
    }

    this.verifyAllComponentsReady();
    this.isConfigured = true;
    this.logger.info('Voice agent initialization with pre-loaded models complete');
  }

  // ============================================================================
  // Smart Model Reuse (iOS Parity)
  // ============================================================================

  /**
   * Load STT model with smart reuse.
   * If the same model is already loaded, reuses it.
   */
  private async loadSTTWithReuse(modelId: string): Promise<void> {
    if (!this.sttCapability) return;

    const currentModelId = this.sttCapability.currentModelId;
    const isLoaded = this.sttCapability.isModelLoaded;

    if (isLoaded && currentModelId === modelId) {
      this.logger.info(`STT model already loaded: ${modelId} - reusing`);
      return;
    }

    this.logger.info(`Loading STT model: ${modelId}`);
    await this.sttCapability.loadModel(modelId);
  }

  /**
   * Load LLM model with smart reuse.
   * If the same model is already loaded, reuses it.
   */
  private async loadLLMWithReuse(modelId: string): Promise<void> {
    if (!this.llmCapability) return;

    const currentModelId = this.llmCapability.currentModelId;
    const isLoaded = this.llmCapability.isModelLoaded;

    if (isLoaded && currentModelId === modelId) {
      this.logger.info(`LLM model already loaded: ${modelId} - reusing`);
      return;
    }

    this.logger.info(`Loading LLM model: ${modelId}`);
    await this.llmCapability.loadModel(modelId);
  }

  /**
   * Load TTS voice with smart reuse.
   * If the same voice is already loaded, reuses it.
   */
  private async loadTTSWithReuse(voiceId: string): Promise<void> {
    if (!this.ttsCapability) return;

    const currentVoiceId = this.ttsCapability.currentModelId;
    const isLoaded = this.ttsCapability.isModelLoaded;

    if (isLoaded && currentVoiceId === voiceId) {
      this.logger.info(`TTS voice already loaded: ${voiceId} - reusing`);
      return;
    }

    this.logger.info(`Loading TTS voice: ${voiceId}`);
    await this.ttsCapability.loadModel(voiceId);
  }

  // ============================================================================
  // Component Initialization Helpers
  // ============================================================================

  private async initializeVAD(config: VADConfiguration): Promise<void> {
    if (!this.vadCapability) return;
    this.logger.debug('Initializing VAD...');
    await this.vadCapability.initialize();
  }

  private async initializeSTT(config: STTConfiguration): Promise<void> {
    if (!this.sttCapability) return;
    this.logger.debug('Initializing STT...');
    await this.sttCapability.initialize();
    if (config.modelId) {
      await this.loadSTTWithReuse(config.modelId);
    }
  }

  private async initializeLLM(config: LLMConfiguration): Promise<void> {
    if (!this.llmCapability) return;
    this.logger.debug('Initializing LLM...');
    await this.llmCapability.initialize();
    if (config.modelId) {
      await this.loadLLMWithReuse(config.modelId);
    }
  }

  private async initializeTTS(config: TTSConfiguration): Promise<void> {
    if (!this.ttsCapability) return;
    this.logger.debug('Initializing TTS...');
    await this.ttsCapability.initialize();
    if (config.voice) {
      await this.loadTTSWithReuse(config.voice);
    }
  }

  private verifyAllComponentsReady(): void {
    const states = this.componentStates;
    if (!isVoiceAgentFullyReady(states)) {
      const missing = [];
      if (states.stt.type !== 'loaded') missing.push('STT');
      if (states.llm.type !== 'loaded') missing.push('LLM');
      if (states.tts.type !== 'loaded') missing.push('TTS');
      if (!states.vadReady) missing.push('VAD');

      throw CapabilityError.compositeComponentFailed(
        'VoiceAgent',
        new Error(`Components not ready: ${missing.join(', ')}`)
      );
    }
  }

  // ============================================================================
  // Component State Access
  // ============================================================================

  /**
   * Get the current state of all components.
   * Useful for UI binding and status display.
   * Matches iOS VoiceAgentComponentStates.
   */
  public get componentStates(): VoiceAgentComponentStates {
    return {
      stt: this.getSTTState(),
      llm: this.getLLMState(),
      tts: this.getTTSState(),
      vadReady: this.vadCapability?.isReady ?? false,
    };
  }

  private getSTTState() {
    if (!this.sttCapability) return notLoadedState();
    if (this.sttCapability.isModelLoaded && this.sttCapability.currentModelId) {
      return loadedComponentState(this.sttCapability.currentModelId);
    }
    return notLoadedState();
  }

  private getLLMState() {
    if (!this.llmCapability) return notLoadedState();
    if (this.llmCapability.isModelLoaded && this.llmCapability.currentModelId) {
      return loadedComponentState(this.llmCapability.currentModelId);
    }
    return notLoadedState();
  }

  private getTTSState() {
    if (!this.ttsCapability) return notLoadedState();
    if (this.ttsCapability.isModelLoaded && this.ttsCapability.currentModelId) {
      return loadedComponentState(this.ttsCapability.currentModelId);
    }
    return notLoadedState();
  }

  // ============================================================================
  // Pipeline Processing
  // ============================================================================

  /**
   * Process audio through the full pipeline.
   * Matches iOS: processVoiceTurn(_ audioData: Data)
   *
   * Pipeline: Audio → VAD → STT → LLM → TTS
   */
  public async processVoiceTurn(audioData: Buffer | Uint8Array): Promise<VoiceAgentResult> {
    if (!this.isConfigured) {
      throw VoiceAgentError.notInitialized();
    }

    const startTime = Date.now();
    this.isProcessing = true;

    // Emit pipeline started event
    this.eventPublisher.track(createVoicePipelineStartedEvent());

    try {
      const result: VoiceAgentResult = {
        speechDetected: false,
        transcription: null,
        response: null,
        synthesizedAudio: null,
      };

      // VAD Processing
      if (this.vadCapability) {
        const vadInput = this.createVADInput(audioData);
        const vadOutput = await this.vadCapability.process(vadInput);
        result.speechDetected = vadOutput.isSpeech;

        if (vadOutput.isSpeech) {
          this.eventPublisher.track(createSpeechDetectedEvent());
        }

        if (!vadOutput.isSpeech) {
          // Emit pipeline completed (short-circuit)
          const durationMs = Date.now() - startTime;
          this.eventPublisher.track(createVoicePipelineCompletedEvent(durationMs));
          return result;
        }
      }

      // STT Processing
      if (this.sttCapability) {
        const transcription = await this.sttCapability.transcribe(audioData);
        result.transcription = transcription.text;

        if (!result.transcription || result.transcription.trim() === '') {
          throw VoiceAgentError.emptyTranscription();
        }
      }

      // LLM Processing
      if (this.llmCapability && result.transcription) {
        const response = await this.llmCapability.generate(result.transcription);
        result.response = response.text;
      }

      // TTS Processing
      if (this.ttsCapability && result.response) {
        const ttsOutput = await this.ttsCapability.synthesize(result.response);
        result.synthesizedAudio = ttsOutput.audioData;
      }

      // Emit pipeline completed
      const durationMs = Date.now() - startTime;
      this.eventPublisher.track(createVoicePipelineCompletedEvent(durationMs));

      return result;
    } catch (error) {
      // Emit pipeline failed
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.eventPublisher.track(createVoicePipelineFailedEvent(errorMessage));
      throw error;
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Process audio stream for continuous conversation.
   * Matches iOS: processStream(_ audioStream: AsyncStream<Data>)
   */
  public async *processStream(
    audioStream: AsyncIterable<Buffer | Uint8Array>
  ): AsyncGenerator<VoiceAgentStreamEvent, void, unknown> {
    for await (const audioData of audioStream) {
      try {
        const result = await this.processVoiceTurn(audioData);
        yield { type: 'processed', result };

        // Yield intermediate events
        if (result.speechDetected) {
          yield { type: 'vadTriggered', isSpeech: true };
        }
        if (result.transcription) {
          yield { type: 'transcriptionAvailable', text: result.transcription };
        }
        if (result.response) {
          yield { type: 'responseGenerated', text: result.response };
        }
        if (result.synthesizedAudio) {
          yield { type: 'audioSynthesized', data: result.synthesizedAudio };
        }
      } catch (error) {
        yield { type: 'error', error: error instanceof Error ? error : new Error(String(error)) };
      }
    }
  }

  // ============================================================================
  // Individual Component Access
  // ============================================================================

  /**
   * Process only through VAD.
   * Matches iOS: detectSpeech(_ samples: [Float])
   */
  public async detectSpeech(audioData: Buffer | Uint8Array): Promise<boolean> {
    if (!this.vadCapability) {
      return true; // Default to true if VAD not available
    }

    const vadInput = this.createVADInput(audioData);
    const vadOutput = await this.vadCapability.process(vadInput);
    return vadOutput.isSpeech;
  }

  /**
   * Process only through STT.
   * Matches iOS: transcribe(_ audioData: Data)
   */
  public async transcribe(audioData: Buffer | Uint8Array): Promise<string> {
    if (!this.sttCapability) {
      throw VoiceAgentError.componentFailed('STT', new Error('STT not initialized'));
    }

    const result = await this.sttCapability.transcribe(audioData);
    return result.text;
  }

  /**
   * Process only through LLM.
   * Matches iOS: generateResponse(_ prompt: String)
   */
  public async generateResponse(prompt: string): Promise<string> {
    if (!this.llmCapability) {
      throw VoiceAgentError.componentFailed('LLM', new Error('LLM not initialized'));
    }

    const result = await this.llmCapability.generate(prompt);
    return result.text;
  }

  /**
   * Process only through TTS.
   * Matches iOS: synthesizeSpeech(_ text: String)
   */
  public async synthesizeSpeech(text: string): Promise<Buffer | Uint8Array> {
    if (!this.ttsCapability) {
      throw VoiceAgentError.componentFailed('TTS', new Error('TTS not initialized'));
    }

    const result = await this.ttsCapability.synthesize(text);
    return result.audioData;
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /**
   * Create VADInput from audio data.
   * Converts buffer to base64-encoded audio data string.
   */
  private createVADInput(data: Buffer | Uint8Array): VADInput {
    const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const audioData = buffer.toString('base64');
    return {
      audioData,
      sampleRate: this.configuration.vadConfig?.sampleRate ?? 16000,
      validate: () => {},
    };
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/**
 * Create a VoiceAgentCapability with the given configuration.
 */
export function createVoiceAgentCapability(configuration: VoiceAgentConfiguration): VoiceAgentCapability {
  return new VoiceAgentCapability(configuration);
}
