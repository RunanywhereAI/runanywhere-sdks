/**
 * RunAnywhere Web SDK - VoicePipeline Extension
 *
 * High-level streaming voice orchestrator: STT -> LLM (streaming) -> TTS.
 *
 * Uses runtime capability lookups via ExtensionPoint, so it doesn't import
 * backend packages directly. Requires both @runanywhere/web-llamacpp and
 * @runanywhere/web-onnx to be registered.
 *
 * Usage:
 *   ```typescript
 *   import { VoicePipeline } from '@runanywhere/web';
 *
 *   const pipeline = new VoicePipeline();
 *   const result = await pipeline.processTurn(audioData, {
 *     maxTokens: 150,
 *     systemPrompt: 'You are a helpful voice assistant.',
 *   }, {
 *     onTranscription: (text) => updateUI('You said: ' + text),
 *     onResponseToken: (_tok, acc) => updateUI('Assistant: ' + acc),
 *     onSynthesisComplete: (audio, sr) => playAudio(audio, sr),
 *   });
 *   ```
 */

import { SDKLogger } from '../../Foundation/SDKLogger';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import type { LLMProvider, STTProvider, TTSProvider } from '../../Infrastructure/ProviderTypes';
import { PipelineState } from './VoiceAgentTypes';
import type {
  VoicePipelineCallbacks,
  VoicePipelineOptions,
  VoicePipelineTurnResult,
} from './VoicePipelineTypes';

export { PipelineState } from './VoiceAgentTypes';
export type {
  VoicePipelineCallbacks,
  VoicePipelineOptions,
  VoicePipelineTurnResult,
} from './VoicePipelineTypes';

const logger = new SDKLogger('VoicePipeline');

// ---------------------------------------------------------------------------
// Dynamic backend access helpers (typed via ExtensionPoint provider registry)
// ---------------------------------------------------------------------------

function requireSTT(): STTProvider {
  return ExtensionPoint.requireProvider('stt', '@runanywhere/web-onnx');
}

function requireTextGeneration(): LLMProvider {
  return ExtensionPoint.requireProvider('llm', '@runanywhere/web-llamacpp');
}

function requireTTS(): TTSProvider {
  return ExtensionPoint.requireProvider('tts', '@runanywhere/web-onnx');
}

// ---------------------------------------------------------------------------
// Default options
// ---------------------------------------------------------------------------

const DEFAULT_OPTIONS: Required<VoicePipelineOptions> = {
  maxTokens: 60,
  temperature: 0.7,
  systemPrompt:
    'You are a helpful voice assistant. Keep responses concise — 1-2 sentences max.',
  ttsSpeed: 1.0,
  sampleRate: 16000,
};

// ---------------------------------------------------------------------------
// VoicePipeline
// ---------------------------------------------------------------------------

export class VoicePipeline {
  private _cancelGeneration: (() => void) | null = null;
  private _state: PipelineState = PipelineState.Idle;

  get state(): PipelineState {
    return this._state;
  }

  async processTurn(
    audioData: Float32Array,
    options?: VoicePipelineOptions,
    callbacks?: VoicePipelineCallbacks,
  ): Promise<VoicePipelineTurnResult> {
    // Validate all providers upfront so a missing TTS doesn't surface
    // only after STT + LLM have already completed.
    const stt = requireSTT();
    const textGen = requireTextGeneration();
    const tts = requireTTS();

    const opts = { ...DEFAULT_OPTIONS, ...options };
    const totalStart = performance.now();

    // Step 1: STT
    this.transition(PipelineState.ProcessingSTT, callbacks);

    const sttStart = performance.now();
    logger.info(`STT: ${(audioData.length / opts.sampleRate).toFixed(1)}s of audio`);
    const sttResult = await stt.transcribe(audioData, {
      sampleRate: opts.sampleRate,
    });
    const sttMs = performance.now() - sttStart;
    const userText = sttResult.text.trim();

    logger.info(`STT complete: "${userText}" (${sttMs.toFixed(0)}ms)`);
    callbacks?.onTranscription?.(userText, sttResult);

    if (!userText) {
      this.transition(PipelineState.Idle, callbacks);
      return {
        transcription: '',
        response: '',
        timing: { sttMs, llmMs: 0, ttsMs: 0, totalMs: performance.now() - totalStart },
      };
    }

    // Step 2: LLM (streaming)
    this.transition(PipelineState.GeneratingResponse, callbacks);

    const llmStart = performance.now();
    const { stream, result: llmResultPromise, cancel } = await textGen.generateStream(
      userText,
      {
        maxTokens: opts.maxTokens,
        temperature: opts.temperature,
        systemPrompt: opts.systemPrompt,
      },
    );
    this._cancelGeneration = cancel;

    let accumulated = '';
    for await (const token of stream) {
      accumulated += token;
      callbacks?.onResponseToken?.(token, accumulated);
    }
    this._cancelGeneration = null;

    const llmResult = await llmResultPromise;
    const fullResponse = llmResult.text || accumulated;
    const llmMs = performance.now() - llmStart;

    logger.info(`LLM complete: ${llmResult.tokensUsed} tokens, ${llmResult.tokensPerSecond.toFixed(1)} tok/s (${llmMs.toFixed(0)}ms)`);
    callbacks?.onResponseComplete?.(fullResponse, llmResult);

    if (!fullResponse.trim()) {
      this.transition(PipelineState.Idle, callbacks);
      return {
        transcription: userText,
        response: '',
        timing: { sttMs, llmMs, ttsMs: 0, totalMs: performance.now() - totalStart },
        llmResult,
      };
    }

    // Step 3: TTS
    this.transition(PipelineState.PlayingTTS, callbacks);

    const ttsStart = performance.now();
    const ttsResult = await tts.synthesize(fullResponse.trim(), {
      speed: opts.ttsSpeed,
    });
    const ttsMs = performance.now() - ttsStart;

    logger.info(`TTS complete: ${ttsResult.durationMs}ms audio in ${ttsResult.processingTimeMs}ms`);
    callbacks?.onSynthesisComplete?.(ttsResult.audioData, ttsResult.sampleRate, ttsResult);

    // Done
    this.transition(PipelineState.Idle, callbacks);

    return {
      transcription: userText,
      response: fullResponse,
      synthesizedAudio: ttsResult.audioData,
      sampleRate: ttsResult.sampleRate,
      timing: {
        sttMs,
        llmMs,
        ttsMs,
        totalMs: performance.now() - totalStart,
      },
      llmResult,
    };
  }

  cancel(): void {
    if (this._cancelGeneration) {
      this._cancelGeneration();
      this._cancelGeneration = null;
      logger.info('Generation cancelled');
    }
  }

  private transition(newState: PipelineState, callbacks?: VoicePipelineCallbacks): void {
    this._state = newState;
    callbacks?.onStateChange?.(newState);
  }
}
