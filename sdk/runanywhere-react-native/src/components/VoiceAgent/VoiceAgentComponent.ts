/**
 * VoiceAgentComponent.ts
 *
 * Voice Agent component that orchestrates VAD, STT, LLM, and TTS components
 * Can be used as a complete pipeline or with individual components
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { VoiceAgentConfiguration } from './VoiceAgentConfiguration';
import type { VoiceAgentResult } from './VoiceAgentModels';
import { STTComponent } from '../STT/STTComponent';
import { LLMComponent } from '../LLM/LLMComponent';
import { TTSComponent } from '../TTS/TTSComponent';
// VADComponent will be imported from the existing location for now
import { VADComponent } from '../../components/VAD/VADComponent';

/**
 * Voice Agent Service (wrapper since it doesn't have an external service)
 */
class VoiceAgentService {
  constructor() {}
}

/**
 * Voice Agent Service Wrapper
 */
export class VoiceAgentServiceWrapper {
  public wrappedService: VoiceAgentService | null = null;

  constructor(service: VoiceAgentService | null = null) {
    this.wrappedService = service;
  }
}

/**
 * Voice Agent component
 */
export class VoiceAgentComponent extends BaseComponent<VoiceAgentServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.VoiceAgent;

  // Individual components (accessible for custom orchestration)
  private vadComponent: VADComponent | null = null;
  private sttComponent: STTComponent | null = null;
  private llmComponent: LLMComponent | null = null;
  private ttsComponent: TTSComponent | null = null;

  // Configuration
  private readonly agentParams: VoiceAgentConfiguration;

  // State
  private isProcessing = false;

  // MARK: - Initialization

  constructor(configuration: VoiceAgentConfiguration) {
    super(configuration);
    this.agentParams = configuration;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<VoiceAgentServiceWrapper> {
    // Voice agent doesn't need an external service, it orchestrates other components
    return new VoiceAgentServiceWrapper(new VoiceAgentService());
  }

  protected override async initializeService(): Promise<void> {
    // Initialize all components
    await this.initializeComponents();
  }

  private async initializeComponents(): Promise<void> {
    // Initialize VAD (required)
    this.vadComponent = new VADComponent(this.agentParams.vadConfig as any);
    await this.vadComponent.initialize();

    // Initialize STT (required)
    this.sttComponent = new STTComponent(this.agentParams.sttConfig);
    await this.sttComponent.initialize();

    // Initialize LLM (required)
    this.llmComponent = new LLMComponent(this.agentParams.llmConfig);
    await this.llmComponent.initialize();

    // Initialize TTS (required)
    this.ttsComponent = new TTSComponent(this.agentParams.ttsConfig);
    await this.ttsComponent.initialize();
  }

  // MARK: - Pipeline Processing

  /**
   * Process audio through the full pipeline
   */
  public async processAudio(audioData: Buffer | Uint8Array): Promise<VoiceAgentResult> {
    if (this.state !== 'Ready') {
      throw SDKError.notInitialized();
    }

    this.isProcessing = true;

    try {
      const result: VoiceAgentResult = {
        speechDetected: false,
        transcription: null,
        response: null,
        synthesizedAudio: null,
      };

      // VAD Processing
      if (this.vadComponent) {
        // Convert audio data to float array for VAD
        const floatData = this.convertDataToFloatArray(audioData);
        const vadService = this.vadComponent.getService();
        if (vadService && 'processAudioData' in vadService) {
          const isSpeech = (vadService as any).processAudioData(floatData);
          result.speechDetected = isSpeech;

          if (!isSpeech) {
            return result; // No speech, return early
          }
        }
      }

      // STT Processing
      if (this.sttComponent) {
        const transcription = await this.sttComponent.transcribe(audioData);
        result.transcription = transcription.text;
      }

      // LLM Processing
      if (this.llmComponent && result.transcription) {
        const response = await this.llmComponent.generate(result.transcription);
        result.response = response.text;
      }

      // TTS Processing
      if (this.ttsComponent && result.response) {
        const ttsOutput = await this.ttsComponent.synthesize(result.response);
        result.synthesizedAudio = ttsOutput.audioData;
      }

      return result;
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * Process audio stream for continuous conversation
   */
  public async *processStream(
    audioStream: AsyncIterable<Buffer | Uint8Array>
  ): AsyncGenerator<VoiceAgentResult, void, unknown> {
    for await (const audioData of audioStream) {
      try {
        const result = await this.processAudio(audioData);
        yield result;
      } catch (error) {
        // Continue processing on error
        yield {
          speechDetected: false,
          transcription: null,
          response: null,
          synthesizedAudio: null,
        };
      }
    }
  }

  // MARK: - Individual Component Access

  /**
   * Process only through VAD
   */
  public detectVoiceActivity(audioData: Buffer | Uint8Array): boolean {
    if (!this.vadComponent) {
      return true; // Default to true if VAD not available
    }

    const floatData = this.convertDataToFloatArray(audioData);
    const vadService = this.vadComponent.getService();
    if (vadService && 'processAudioData' in vadService) {
      return (vadService as any).processAudioData(floatData);
    }
    return true;
  }

  /**
   * Process only through STT
   */
  public async transcribe(audioData: Buffer | Uint8Array): Promise<string | null> {
    if (!this.sttComponent) {
      return null;
    }

    try {
      const result = await this.sttComponent.transcribe(audioData);
      return result.text;
    } catch {
      return null;
    }
  }

  /**
   * Process only through LLM
   */
  public async generateResponse(prompt: string): Promise<string | null> {
    if (!this.llmComponent) {
      return null;
    }

    try {
      const result = await this.llmComponent.generate(prompt);
      return result.text;
    } catch {
      return null;
    }
  }

  /**
   * Process only through TTS
   */
  public async synthesizeSpeech(text: string): Promise<Buffer | Uint8Array | null> {
    if (!this.ttsComponent) {
      return null;
    }

    try {
      const result = await this.ttsComponent.synthesize(text);
      return result.audioData;
    } catch {
      return null;
    }
  }

  // MARK: - Cleanup

  protected override async performCleanup(): Promise<void> {
    this.isProcessing = false;

    try {
      await this.vadComponent?.cleanup();
    } catch {
      // Ignore cleanup errors
    }

    try {
      await this.sttComponent?.cleanup();
    } catch {
      // Ignore cleanup errors
    }

    try {
      await this.llmComponent?.cleanup();
    } catch {
      // Ignore cleanup errors
    }

    try {
      await this.ttsComponent?.cleanup();
    } catch {
      // Ignore cleanup errors
    }

    this.vadComponent = null;
    this.sttComponent = null;
    this.llmComponent = null;
    this.ttsComponent = null;
  }

  // MARK: - Helper Methods

  /**
   * Convert audio data to float array
   */
  private convertDataToFloatArray(data: Buffer | Uint8Array): number[] {
    const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const floatArray: number[] = [];
    for (let i = 0; i < buffer.length; i += 4) {
      if (i + 3 < buffer.length) {
        floatArray.push(buffer.readFloatLE(i));
      }
    }
    return floatArray;
  }
}
