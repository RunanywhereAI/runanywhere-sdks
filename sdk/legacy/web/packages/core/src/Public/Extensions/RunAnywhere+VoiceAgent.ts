/**
 * RunAnywhere Web SDK - VoiceAgent Extension
 *
 * Orchestrates the complete voice pipeline: VAD -> STT -> LLM -> TTS.
 * Uses the RACommons rac_voice_agent_* C API for pipeline management.
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/
 *
 * Usage:
 *   import { VoiceAgent } from '@runanywhere/web';
 *
 *   const agent = await VoiceAgent.create();
 *   await agent.loadModels({ stt: '/models/whisper.bin', llm: '/models/llama.gguf', tts: '/models/piper.onnx' });
 *   const result = await agent.processVoiceTurn(audioData);
 *   console.log('Transcription:', result.transcription);
 *   console.log('Response:', result.response);
 */

import { RunAnywhere } from '../RunAnywhere';
import { SDKError } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import type { VoiceAgentModels, VoiceTurnResult } from './VoiceAgentTypes';

export { PipelineState } from './VoiceAgentTypes';
export type { VoiceAgentModels, VoiceTurnResult, VoiceAgentEventData, VoiceAgentEventCallback } from './VoiceAgentTypes';

const logger = new SDKLogger('VoiceAgent');

// ---------------------------------------------------------------------------
// VoiceAgent Instance
// ---------------------------------------------------------------------------

/**
 * VoiceAgentSession orchestrates the complete voice pipeline (VAD → STT → LLM → TTS).
 *
 * TODO: Refactor to use the ExtensionPoint/provider pattern.
 * The previous implementation called rac_voice_agent_* C functions via WASMBridge,
 * which has been removed from the core package. Each backend package (e.g.
 * @runanywhere/web-llamacpp) should register a VoiceAgent provider through
 * ExtensionPoint so that this session can delegate to it.
 */
export class VoiceAgentSession {
  private _handle: number;

  constructor(handle: number) {
    this._handle = handle;
  }

  /**
   * Load models for all components.
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  async loadModels(models: VoiceAgentModels): Promise<void> {
    if (models.stt) logger.info(`Loading STT model: ${models.stt.id}`);
    if (models.llm) logger.info(`Loading LLM model: ${models.llm.id}`);
    if (models.tts) logger.info(`Loading TTS voice: ${models.tts.id}`);

    // TODO: Invoke backend-specific voice agent provider to load models.
    throw SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package (e.g. @runanywhere/web-llamacpp)');
  }

  /**
   * Process a complete voice turn (audio in → text response + audio out).
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  async processVoiceTurn(_audioData: Uint8Array): Promise<VoiceTurnResult> {
    // TODO: Invoke backend-specific voice agent provider.
    throw SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package (e.g. @runanywhere/web-llamacpp)');
  }

  /**
   * Check if the voice agent is ready.
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  get isReady(): boolean {
    // TODO: Query backend provider readiness.
    return false;
  }

  /**
   * Transcribe audio without the full pipeline.
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  async transcribe(_audioData: Uint8Array): Promise<string> {
    // TODO: Invoke backend-specific STT provider.
    throw SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package (e.g. @runanywhere/web-llamacpp)');
  }

  /**
   * Generate LLM response without the full pipeline.
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  async generateResponse(_prompt: string): Promise<string> {
    // TODO: Invoke backend-specific LLM provider.
    throw SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package (e.g. @runanywhere/web-llamacpp)');
  }

  /** Get the native handle (used by backend providers). */
  get handle(): number {
    return this._handle;
  }

  /**
   * Destroy the voice agent session.
   *
   * TODO: Delegate cleanup to backend provider via ExtensionPoint.
   */
  destroy(): void {
    // TODO: Invoke backend-specific cleanup.
    this._handle = 0;
  }
}

// ---------------------------------------------------------------------------
// VoiceAgent Factory
// ---------------------------------------------------------------------------

export const VoiceAgent = {
  /**
   * Create a standalone VoiceAgent session.
   * The agent manages its own STT, LLM, TTS, and VAD components.
   *
   * TODO: Delegate to backend provider via ExtensionPoint.
   */
  async create(): Promise<VoiceAgentSession> {
    if (!RunAnywhere.isInitialized) {
      throw SDKError.notInitialized();
    }

    // TODO: Look up a registered VoiceAgent provider from ExtensionPoint
    // and delegate session creation to it.
    throw SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package (e.g. @runanywhere/web-llamacpp)');
  },
};
