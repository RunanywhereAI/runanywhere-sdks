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
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';
import { PipelineState } from './VoiceAgentTypes';
import type { VoiceAgentModels, VoiceTurnResult, VoiceAgentEventData, VoiceAgentEventCallback } from './VoiceAgentTypes';

export { PipelineState } from './VoiceAgentTypes';
export type { VoiceAgentModels, VoiceTurnResult, VoiceAgentEventData, VoiceAgentEventCallback } from './VoiceAgentTypes';

const logger = new SDKLogger('VoiceAgent');

// ---------------------------------------------------------------------------
// VoiceAgent Instance
// ---------------------------------------------------------------------------

export class VoiceAgentSession {
  private handle: number;
  private eventCallbackPtr = 0;

  constructor(handle: number) {
    this.handle = handle;
  }

  /**
   * Load models for all components.
   */
  async loadModels(models: VoiceAgentModels): Promise<void> {
    const bridge = WASMBridge.shared;
    const m = bridge.module;

    if (models.stt) {
      logger.info(`Loading STT model: ${models.stt.id}`);
      const pathPtr = bridge.allocString(models.stt.path);
      const idPtr = bridge.allocString(models.stt.id);
      const namePtr = bridge.allocString(models.stt.name ?? models.stt.id);
      try {
        const r = m.ccall(
          'rac_voice_agent_load_stt_model', 'number',
          ['number', 'number', 'number', 'number'],
          [this.handle, pathPtr, idPtr, namePtr],
        ) as number;
        bridge.checkResult(r, 'rac_voice_agent_load_stt_model');
      } finally {
        bridge.free(pathPtr); bridge.free(idPtr); bridge.free(namePtr);
      }
    }

    if (models.llm) {
      logger.info(`Loading LLM model: ${models.llm.id}`);
      const pathPtr = bridge.allocString(models.llm.path);
      const idPtr = bridge.allocString(models.llm.id);
      const namePtr = bridge.allocString(models.llm.name ?? models.llm.id);
      try {
        const r = m.ccall(
          'rac_voice_agent_load_llm_model', 'number',
          ['number', 'number', 'number', 'number'],
          [this.handle, pathPtr, idPtr, namePtr],
        ) as number;
        bridge.checkResult(r, 'rac_voice_agent_load_llm_model');
      } finally {
        bridge.free(pathPtr); bridge.free(idPtr); bridge.free(namePtr);
      }
    }

    if (models.tts) {
      logger.info(`Loading TTS voice: ${models.tts.id}`);
      const pathPtr = bridge.allocString(models.tts.path);
      const idPtr = bridge.allocString(models.tts.id);
      const namePtr = bridge.allocString(models.tts.name ?? models.tts.id);
      try {
        const r = m.ccall(
          'rac_voice_agent_load_tts_voice', 'number',
          ['number', 'number', 'number', 'number'],
          [this.handle, pathPtr, idPtr, namePtr],
        ) as number;
        bridge.checkResult(r, 'rac_voice_agent_load_tts_voice');
      } finally {
        bridge.free(pathPtr); bridge.free(idPtr); bridge.free(namePtr);
      }
    }

    // Initialize with loaded models
    const initResult = m.ccall(
      'rac_voice_agent_initialize_with_loaded_models', 'number',
      ['number'], [this.handle],
    ) as number;
    bridge.checkResult(initResult, 'rac_voice_agent_initialize_with_loaded_models');

    logger.info('VoiceAgent initialized with loaded models');
  }

  /**
   * Process a complete voice turn (audio in -> text response + audio out).
   */
  async processVoiceTurn(audioData: Uint8Array): Promise<VoiceTurnResult> {
    const bridge = WASMBridge.shared;
    const m = bridge.module;

    const audioPtr = m._malloc(audioData.length);
    bridge.writeBytes(audioData, audioPtr);

    // rac_voice_agent_result_t: { speech_detected, transcription, response, synthesized_audio, audio_size }
    const resultSize = m._rac_wasm_sizeof_voice_agent_result();
    const resultPtr = m._malloc(resultSize);

    try {
      const r = m.ccall(
        'rac_voice_agent_process_voice_turn', 'number',
        ['number', 'number', 'number', 'number'],
        [this.handle, audioPtr, audioData.length, resultPtr],
      ) as number;
      bridge.checkResult(r, 'rac_voice_agent_process_voice_turn');

      const speechDetected = m.getValue(resultPtr, 'i32') === 1;
      const transcriptionPtr = m.getValue(resultPtr + 4, '*');
      const responsePtr = m.getValue(resultPtr + 8, '*');
      const audioDataPtr = m.getValue(resultPtr + 12, '*');
      const audioSize = m.getValue(resultPtr + 16, 'i32');

      const result: VoiceTurnResult = {
        speechDetected,
        transcription: transcriptionPtr ? bridge.readString(transcriptionPtr) : undefined,
        response: responsePtr ? bridge.readString(responsePtr) : undefined,
      };

      if (audioDataPtr && audioSize > 0) {
        const numSamples = audioSize / 4;
        result.synthesizedAudio = bridge.readFloat32Array(audioDataPtr, numSamples);
      }

      // Free C result
      m.ccall('rac_voice_agent_result_free', null, ['number'], [resultPtr]);

      EventBus.shared.emit('voice.turnCompleted', SDKEventType.Voice, {
        speechDetected,
        transcription: result.transcription,
        response: result.response,
      });

      return result;
    } finally {
      m._free(audioPtr);
    }
  }

  /** Check if the voice agent is ready. */
  get isReady(): boolean {
    const m = WASMBridge.shared.module;
    const outPtr = m._malloc(4);
    try {
      m.ccall('rac_voice_agent_is_ready', 'number', ['number', 'number'], [this.handle, outPtr]);
      return m.getValue(outPtr, 'i32') === 1;
    } finally {
      m._free(outPtr);
    }
  }

  /** Transcribe audio without the full pipeline. */
  async transcribe(audioData: Uint8Array): Promise<string> {
    const bridge = WASMBridge.shared;
    const m = bridge.module;

    const audioPtr = m._malloc(audioData.length);
    bridge.writeBytes(audioData, audioPtr);
    const outPtr = m._malloc(4);

    try {
      const r = m.ccall(
        'rac_voice_agent_transcribe', 'number',
        ['number', 'number', 'number', 'number'],
        [this.handle, audioPtr, audioData.length, outPtr],
      ) as number;
      bridge.checkResult(r, 'rac_voice_agent_transcribe');
      const textPtr = m.getValue(outPtr, '*');
      const text = bridge.readString(textPtr);
      if (textPtr) m._free(textPtr);
      return text;
    } finally {
      m._free(audioPtr);
      m._free(outPtr);
    }
  }

  /** Generate LLM response without the full pipeline. */
  async generateResponse(prompt: string): Promise<string> {
    const bridge = WASMBridge.shared;
    const m = bridge.module;

    const promptPtr = bridge.allocString(prompt);
    const outPtr = m._malloc(4);

    try {
      const r = m.ccall(
        'rac_voice_agent_generate_response', 'number',
        ['number', 'number', 'number'],
        [this.handle, promptPtr, outPtr],
      ) as number;
      bridge.checkResult(r, 'rac_voice_agent_generate_response');
      const textPtr = m.getValue(outPtr, '*');
      const text = bridge.readString(textPtr);
      if (textPtr) m._free(textPtr);
      return text;
    } finally {
      bridge.free(promptPtr);
      m._free(outPtr);
    }
  }

  /** Destroy the voice agent session. */
  destroy(): void {
    if (this.eventCallbackPtr !== 0) {
      try { WASMBridge.shared.module.removeFunction(this.eventCallbackPtr); } catch { /* ignore */ }
      this.eventCallbackPtr = 0;
    }
    if (this.handle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_voice_agent_destroy', null, ['number'], [this.handle],
        );
      } catch { /* ignore */ }
      this.handle = 0;
    }
  }
}

// ---------------------------------------------------------------------------
// VoiceAgent Factory
// ---------------------------------------------------------------------------

export const VoiceAgent = {
  /**
   * Create a standalone VoiceAgent session.
   * The agent manages its own STT, LLM, TTS, and VAD components.
   */
  async create(): Promise<VoiceAgentSession> {
    if (!RunAnywhere.isInitialized) {
      throw SDKError.notInitialized();
    }

    const m = WASMBridge.shared.module;
    const handlePtr = m._malloc(4);

    const result = m.ccall(
      'rac_voice_agent_create_standalone', 'number',
      ['number'], [handlePtr],
    ) as number;

    if (result !== 0) {
      m._free(handlePtr);
      throw SDKError.fromRACResult(result, 'rac_voice_agent_create_standalone');
    }

    const handle = m.getValue(handlePtr, 'i32');
    m._free(handlePtr);

    logger.info('VoiceAgent session created');
    return new VoiceAgentSession(handle);
  },
};
