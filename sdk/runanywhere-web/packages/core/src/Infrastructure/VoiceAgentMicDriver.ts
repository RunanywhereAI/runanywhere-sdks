/**
 * Browser microphone ingress for the voice agent.
 *
 * The C ABI owns NO microphone access (`rac_voice_agent.h` Audio-Ingress
 * Contract): this driver captures raw mic frames and pushes them continuously
 * into the owning commons instance via `rac_voice_agent_feed_audio_proto`
 * (`feedVoiceAgentAudio`). Commons performs energy-based utterance
 * segmentation, barge-in, and the STT → LLM → TTS turn pipeline, returning
 * the synthesized reply inline for playback.
 *
 * This driver is therefore a thin capture → feed → play loop with NO SDK-side
 * VAD, hangover, pre-roll, or end-of-utterance policy. Mirrors Swift/Kotlin/RN
 * `VoiceAgentMicDriver`. Frames captured while a turn is processing are
 * dropped by the core (and the bounded queue here) so the device's own TTS
 * playout is not re-fed.
 *
 * Continuous mic feed requires a native voice-agent handle on a single WASM
 * heap (`providerKind === 'wasm-handle'`). Cross-WASM composition cannot own a
 * shared handle across heaps — `feedVoiceAgentAudio` fails explicitly rather
 * than silently reimplementing segmentation in TypeScript.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';
import { SDKException } from '../Foundation/SDKException.js';
import {
  feedVoiceAgentAudio,
  supportsVoiceAgentFeedAudio,
} from '../Public/Extensions/RunAnywhere+VoiceAgent.js';
import { float32ToPcm16 } from '../Public/Extensions/RunAnywhere+AudioConvert.js';
import type { VoiceAgentResult } from '@runanywhere/proto-ts/voice_agent_service';
import { AudioCapture } from './AudioCapture.js';
import { AudioPlayback } from './AudioPlayback.js';
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';

const logger = new SDKLogger('VoiceAgentMicDriver');

const SAMPLE_RATE_HZ = audioCaptureDefaults.micSampleRateHz;
/** Bounded backlog so a slow turn cannot grow the queue without limit. */
const CHANNEL_CAPACITY = 128;
/** Poll interval when no captured frames are pending. */
const FEED_IDLE_SLEEP_MS = 20;

/**
 * `speaking` is reported only while a reply is actually audible. The voice-agent
 * provider emits `PLAYING_TTS` before synthesis even starts and hands the audio
 * back for this driver to play, so its pipeline states describe intent, not
 * sound; only this layer knows when audio is leaving the speaker. Mirrors
 * Swift/Kotlin `VoiceAgentMicDriver.onPlaybackPhase`.
 */
export type VoiceAgentMicPhase = 'listening' | 'processing' | 'speaking';

export interface VoiceAgentMicTurn {
  userText: string;
  assistantText: string;
}

export interface VoiceAgentMicCallbacks {
  onTurn?: (turn: VoiceAgentMicTurn) => void | Promise<void>;
  onPhase?: (phase: VoiceAgentMicPhase) => void;
  onLevel?: (level: number) => void;
  onError?: (error: Error) => void;
  /**
   * Reserved for API parity with earlier barge-in UI hooks. Commons owns
   * barge-in detection inside `rac_voice_agent_feed_audio_proto` and surfaces
   * it on the voice-event stream; this callback is not driven by host RMS.
   */
  onBargeIn?: () => void;
}

export interface VoiceAgentMicOptions extends VoiceAgentMicCallbacks {
  /** Play synthesized replies through the browser speaker. Defaults to true. */
  autoPlayTts?: boolean;
  /** Keep capturing after each turn. Defaults to true. */
  continuousMode?: boolean;
}

export class VoiceAgentMicDriver {
  private readonly capture = new AudioCapture({
    sampleRate: SAMPLE_RATE_HZ,
    chunkSize: 1600,
    channels: 1,
  });
  private readonly playback = new AudioPlayback();

  private callbacks: VoiceAgentMicCallbacks = {};
  private autoPlayTts = true;
  private continuousMode = true;
  private stopped = true;
  private sessionEpoch = 0;
  private queue: Float32Array[] = [];
  private playoutPromise: Promise<void> | null = null;
  private playoutGeneration = 0;

  get isRunning(): boolean {
    return !this.stopped && this.capture.isCapturing;
  }

  async start(options: VoiceAgentMicOptions = {}): Promise<void> {
    if (this.isRunning) return;
    if (!supportsVoiceAgentFeedAudio()) {
      throw SDKException.backendNotAvailable(
        'VoiceAgentMicDriver',
        'Continuous mic feed requires rac_voice_agent_feed_audio_proto on the '
        + 'WASM module that owns the voice-agent handle. Cross-WASM voice '
        + 'composition cannot share that handle across heaps — co-locate STT/'
        + 'LLM/TTS on one commons instance (wasm-handle provider) or stop the '
        + 'session. Host-side segmentation is not a permitted fallback.',
      );
    }

    const { autoPlayTts, continuousMode, ...callbacks } = options;
    this.callbacks = callbacks;
    this.autoPlayTts = autoPlayTts ?? true;
    this.continuousMode = continuousMode ?? true;

    const epoch = ++this.sessionEpoch;
    this.stopped = false;
    this.queue = [];
    await this.capture.start(
      (chunk) => this.enqueueChunk(chunk),
      (level) => this.callbacks.onLevel?.(level),
    );
    if (this.stopped || epoch !== this.sessionEpoch) {
      if (this.stopped) {
        this.capture.stop();
        this.capture.clearBuffer();
      }
      return;
    }
    this.callbacks.onPhase?.('listening');
    logger.info('Voice-agent mic capture started');
    void this.feedLoop(epoch);
  }

  stop(): void {
    if (this.stopped) return;
    this.sessionEpoch += 1;
    this.stopped = true;
    this.capture.stop();
    this.capture.clearBuffer();
    this.cancelPlayout();
    this.playback.dispose();
    this.queue = [];
    logger.info('Voice-agent mic capture stopped');
  }

  /**
   * Stop the in-flight reply's playback (if any). Used by
   * `VoiceSession.interrupt()` — unlike `stop()`, the microphone keeps
   * capturing afterward. Commons owns whether buffered frames are barge-in
   * speech or echo; the driver only cuts the speaker.
   */
  async interruptCurrentTurn(): Promise<void> {
    this.cancelPlayout();
    const pending = this.playoutPromise;
    if (pending) {
      await pending.catch(() => { /* phase already restored in finally */ });
    }
  }

  private enqueueChunk(chunk: Float32Array): void {
    this.capture.clearBuffer();
    if (this.stopped || chunk.length === 0) return;
    this.queue.push(chunk);
    if (this.queue.length > CHANNEL_CAPACITY) {
      this.queue.splice(0, this.queue.length - CHANNEL_CAPACITY);
    }
  }

  private drainChunks(): Float32Array[] {
    if (this.queue.length === 0) return [];
    const drained = this.queue;
    this.queue = [];
    return drained;
  }

  /**
   * Drains captured frames and feeds them to the owning commons instance.
   * A non-empty `synthesizedAudio` means the core closed an utterance and ran
   * a full turn; playout starts concurrently so barge-in frames keep flowing.
   */
  private async feedLoop(epoch: number): Promise<void> {
    while (!this.stopped && epoch === this.sessionEpoch) {
      const chunks = this.drainChunks();
      if (chunks.length === 0) {
        await sleep(FEED_IDLE_SLEEP_MS);
        continue;
      }

      for (const chunk of chunks) {
        if (this.stopped || epoch !== this.sessionEpoch) return;
        try {
          const result = await feedVoiceAgentAudio(float32ToPcm16(chunk));
          if (this.stopped || epoch !== this.sessionEpoch) return;
          if (!result) continue; // utterance still open

          const turnError = result.finalState?.error;
          if (turnError) {
            logger.warning(`Voice turn failed: ${turnError.message}`);
            this.callbacks.onError?.(new Error(turnError.message));
          }

          await this.callbacks.onTurn?.({
            userText: result.transcription?.trim() ?? '',
            assistantText: result.assistantResponse?.trim() ?? '',
          });

          if (this.autoPlayTts && result.synthesizedAudio && result.synthesizedAudio.byteLength > 0) {
            // Frames buffered while the turn was computing predate playout —
            // commons also drops its own backlog; mirror that here.
            this.queue = [];
            this.startPlayout(result, epoch);
          }

          if (!this.continuousMode) {
            this.stop();
            return;
          }
        } catch (error) {
          const normalized = error instanceof Error ? error : new Error(String(error));
          if (this.stopped || epoch !== this.sessionEpoch) {
            logger.debug(`Discarded cancelled voice feed: ${normalized.message}`);
            return;
          }
          logger.warning(`Voice feed threw: ${normalized.message}`);
          this.callbacks.onError?.(normalized);
        }
      }
    }
  }

  private startPlayout(result: VoiceAgentResult, epoch: number): void {
    const bytes = result.synthesizedAudio;
    if (!bytes || bytes.byteLength === 0) return;
    const generation = ++this.playoutGeneration;
    this.callbacks.onPhase?.('speaking');
    this.playoutPromise = (async () => {
      try {
        await this.playback.playEncoded(bytes);
      } catch (error) {
        logger.warning(
          `Agent reply playback failed: ${error instanceof Error ? error.message : String(error)}`,
        );
      } finally {
        if (generation === this.playoutGeneration && epoch === this.sessionEpoch && !this.stopped) {
          this.callbacks.onPhase?.('listening');
        }
        if (generation === this.playoutGeneration) {
          this.playoutPromise = null;
        }
      }
    })();
  }

  private cancelPlayout(): void {
    this.playoutGeneration += 1;
    this.playback.stop();
    this.playoutPromise = null;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
