/**
 * RunAnywhere Web SDK - VoicePipeline Extension
 *
 * High-level streaming voice orchestrator: STT -> LLM (streaming) -> TTS.
 *
 * Unlike VoiceAgent (which uses the C API for a batch pipeline), VoicePipeline
 * composes the existing TypeScript SDK extensions (STT, TextGeneration, TTS)
 * and provides streaming callbacks so the UI can update in real-time as each
 * stage progresses.
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
 *
 * The pipeline does NOT handle audio capture, VAD, or playback — those are
 * app-level concerns (mic control, VAD thresholds, speaker output).
 */

import { STT } from './RunAnywhere+STT';
import { TextGeneration } from './RunAnywhere+TextGeneration';
import { TTS } from './RunAnywhere+TTS';
import { SDKLogger } from '../../Foundation/SDKLogger';
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

/**
 * Streaming voice pipeline that orchestrates STT -> LLM -> TTS.
 *
 * Create one instance and reuse it across conversation turns. Each call to
 * `processTurn()` runs the full pipeline once and returns the result.
 *
 * The LLM step uses streaming generation, so the `onResponseToken` callback
 * fires for each token — enabling real-time UI updates.
 */
export class VoicePipeline {
  private _cancelGeneration: (() => void) | null = null;
  private _state: PipelineState = PipelineState.Idle;

  /** Current pipeline state. */
  get state(): PipelineState {
    return this._state;
  }

  /**
   * Run a complete voice turn: audio in -> transcription -> LLM response -> TTS audio.
   *
   * @param audioData  Float32Array of PCM samples (mono, typically 16 kHz).
   * @param options    LLM / TTS / STT configuration for this turn.
   * @param callbacks  Streaming callbacks for real-time UI updates.
   * @returns          The full turn result once all stages complete.
   */
  async processTurn(
    audioData: Float32Array,
    options?: VoicePipelineOptions,
    callbacks?: VoicePipelineCallbacks,
  ): Promise<VoicePipelineTurnResult> {
    const opts = { ...DEFAULT_OPTIONS, ...options };
    const totalStart = performance.now();

    // ── Step 1: STT ────────────────────────────────────────────────────
    this.transition(PipelineState.ProcessingSTT, callbacks);

    const sttStart = performance.now();
    logger.info(`STT: ${(audioData.length / opts.sampleRate).toFixed(1)}s of audio`);

    const sttResult = await STT.transcribe(audioData, {
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

    // ── Step 2: LLM (streaming) ────────────────────────────────────────
    this.transition(PipelineState.GeneratingResponse, callbacks);

    const llmStart = performance.now();
    const { stream, result: llmResultPromise, cancel } = await TextGeneration.generateStream(
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

    // ── Step 3: TTS ────────────────────────────────────────────────────
    this.transition(PipelineState.PlayingTTS, callbacks);

    const ttsStart = performance.now();
    const ttsResult = await TTS.synthesize(fullResponse.trim(), {
      speed: opts.ttsSpeed,
    });
    const ttsMs = performance.now() - ttsStart;

    logger.info(`TTS complete: ${ttsResult.durationMs}ms audio in ${ttsResult.processingTimeMs}ms`);
    callbacks?.onSynthesisComplete?.(ttsResult.audioData, ttsResult.sampleRate, ttsResult);

    // ── Done ───────────────────────────────────────────────────────────
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

  /**
   * Cancel in-progress LLM generation.
   * Safe to call at any time — no-ops if nothing is in progress.
   */
  cancel(): void {
    if (this._cancelGeneration) {
      this._cancelGeneration();
      this._cancelGeneration = null;
      logger.info('Generation cancelled');
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  private transition(newState: PipelineState, callbacks?: VoicePipelineCallbacks): void {
    this._state = newState;
    callbacks?.onStateChange?.(newState);
  }
}
