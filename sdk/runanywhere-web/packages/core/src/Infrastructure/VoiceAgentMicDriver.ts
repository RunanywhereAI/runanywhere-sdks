/**
 * Browser microphone ingress for the split-WASM voice agent.
 *
 * AudioCapture supplies 16 kHz mono Float32 chunks. This driver performs only
 * coarse endpointing, then submits the completed utterance through the public
 * one-call `processVoiceTurn` SDK surface. STT, LLM, TTS, model routing, and
 * event production remain owned by the SDK provider.
 *
 * Turn-taking is half-duplex for *capture* — frames arriving while the STT →
 * LLM → TTS pass runs are not buffered into an utterance, so the device's own
 * playout can never be re-fed as user speech. It is NOT half-duplex for
 * *listening*: while a reply is audible those frames still run through a
 * dedicated barge-in gate (`evaluateBargeIn`), so speaking over the agent cuts
 * the reply instead of forcing the user to wait it out. The gate is separate
 * from the turn segmenter on purpose — it needs a far more conservative
 * threshold, because the reply itself leaks into the microphone.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';
import { processVoiceTurn } from '../Public/Extensions/RunAnywhere+VoiceAgent.js';
import type { VoiceAgentResult } from '@runanywhere/proto-ts/voice_agent_service';
import { AudioCapture } from './AudioCapture.js';
import { AudioPlayback } from './AudioPlayback.js';
import { voiceAgentDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';

const logger = new SDKLogger('VoiceAgentMicDriver');

const SAMPLE_RATE_HZ = audioCaptureDefaults.micSampleRateHz;
const SPEECH_RMS_THRESHOLD = voiceAgentDefaults.speechRmsThreshold;
const SPEECH_FLOOR_MULTIPLIER = voiceAgentDefaults.speechFloorMultiplier;
const NOISE_FLOOR_RISE = 0.05;
const END_OF_UTTERANCE_SILENCE_MS = 800;
const MIN_SPEECH_MS = 300;
const MAX_UTTERANCE_MS = 15_000;
const PRE_ROLL_CHUNKS = 3;

// ---------------------------------------------------------------------------
// Barge-in gate (active only while a reply is audible)
// ---------------------------------------------------------------------------

/**
 * Frames from the first moments of playout are ignored. `getUserMedia` is
 * opened with `echoCancellation: true`, and the browser's AEC needs a short
 * window to converge on the new far-end signal; the room's reverb tail of the
 * user's own just-finished utterance also lands here.
 */
const BARGE_IN_GRACE_MS = 300;
/**
 * Consecutive loud audio required before the reply is cut. One chunk is 100 ms,
 * so this is three frames — long enough that a door, a keystroke, or one AEC
 * residual burst cannot take the turn, short enough to feel immediate.
 */
const BARGE_IN_MIN_SPEECH_MS = 300;
/**
 * Absolute floor for a barge-in, as a multiple of the normal speech threshold.
 * Deliberately far above it: a false trigger truncates the answer the user
 * asked for, which is worse than a barge-in that needs to be said louder.
 */
const BARGE_IN_THRESHOLD_MULTIPLIER = 3;
/** Barge-in must also stand this far above the measured echo residual. */
const BARGE_IN_ECHO_MULTIPLIER = 2.5;
/** How fast the echo-residual estimate tracks the frames it is measured from. */
const ECHO_FLOOR_RISE = 0.2;

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
   * The user spoke over an audible reply and playout was cut. Distinct from a
   * phase change so a UI can say why the answer stopped short.
   */
  onBargeIn?: () => void;
}

export interface VoiceAgentMicOptions extends VoiceAgentMicCallbacks {
  silenceDurationMs?: number;
  speechThreshold?: number;
  maxRecordingDurationMs?: number;
  autoPlayTts?: boolean;
  continuousMode?: boolean;
  /**
   * Cut an audible reply when the user speaks over it. On by default; set
   * false for a strictly half-duplex session (e.g. a shared speakerphone where
   * echo would keep re-triggering it).
   */
  bargeInEnabled?: boolean;
}

export class VoiceAgentMicDriver {
  private readonly capture = new AudioCapture({
    sampleRate: SAMPLE_RATE_HZ,
    chunkSize: 1600,
    channels: 1,
  });
  private readonly playback = new AudioPlayback();

  private callbacks: VoiceAgentMicCallbacks = {};
  private options: Required<Pick<VoiceAgentMicOptions,
    'silenceDurationMs' | 'speechThreshold' | 'maxRecordingDurationMs' |
    'autoPlayTts' | 'continuousMode' | 'bargeInEnabled'>> = {
      silenceDurationMs: END_OF_UTTERANCE_SILENCE_MS,
      speechThreshold: SPEECH_RMS_THRESHOLD,
      maxRecordingDurationMs: MAX_UTTERANCE_MS,
      autoPlayTts: true,
      continuousMode: true,
      bargeInEnabled: true,
    };
  private stopped = true;
  private processing = false;
  private sessionEpoch = 0;
  private preRoll: Float32Array[] = [];
  private utterance: Float32Array[] = [];
  private utteranceSamples = 0;
  private inSpeech = false;
  private speechMs = 0;
  private silenceMs = 0;
  private noiseFloor = SPEECH_RMS_THRESHOLD;
  private currentTurnPromise: Promise<void> | null = null;
  /** True only while reply audio is actually leaving the speaker. */
  private replyAudible = false;
  private playoutMs = 0;
  private echoFloor = 0;
  private bargeMs = 0;
  private bargeInFired = false;
  private bargeFrames: Float32Array[] = [];
  /** Confirmed barge-in speech, handed to the next utterance's pre-roll. */
  private pendingBargePreRoll: Float32Array[] = [];

  get isRunning(): boolean {
    return !this.stopped && this.capture.isCapturing;
  }

  async start(options: VoiceAgentMicOptions = {}): Promise<void> {
    if (this.isRunning) return;
    const {
      silenceDurationMs,
      speechThreshold,
      maxRecordingDurationMs,
      autoPlayTts,
      continuousMode,
      bargeInEnabled,
      ...callbacks
    } = options;
    this.callbacks = callbacks;
    this.options = {
      silenceDurationMs: positiveOr(silenceDurationMs, END_OF_UTTERANCE_SILENCE_MS),
      speechThreshold: positiveOr(speechThreshold, SPEECH_RMS_THRESHOLD),
      maxRecordingDurationMs: positiveOr(maxRecordingDurationMs, MAX_UTTERANCE_MS),
      autoPlayTts: autoPlayTts ?? true,
      continuousMode: continuousMode ?? true,
      bargeInEnabled: bargeInEnabled ?? true,
    };
    const epoch = ++this.sessionEpoch;
    this.stopped = false;
    this.processing = false;
    this.noiseFloor = this.options.speechThreshold;
    this.resetBargeInGate();
    this.resetSegmentation();
    await this.capture.start(
      (chunk) => this.onChunk(chunk),
      (level) => this.callbacks.onLevel?.(level),
    );
    if (this.stopped || epoch !== this.sessionEpoch) {
      // Permission may have resolved after stop() or a newer start(). The
      // capture invalidates stale starts itself. Only stop again when no newer
      // session owns the capture.
      if (this.stopped) {
        this.capture.stop();
        this.capture.clearBuffer();
      }
      return;
    }
    this.callbacks.onPhase?.('listening');
    logger.info('Voice-agent mic capture started');
  }

  stop(): void {
    if (this.stopped) return;
    this.sessionEpoch += 1;
    this.stopped = true;
    this.capture.stop();
    this.capture.clearBuffer();
    // Release the playback AudioContext as well as the active source. The
    // driver can be started again because AudioPlayback lazily recreates its
    // context on the next turn; retaining it here leaked one context each
    // time the Talk view was unmounted and reconstructed.
    this.playback.dispose();
    this.processing = false;
    this.pendingBargePreRoll = [];
    this.resetBargeInGate();
    this.resetSegmentation();
    logger.info('Voice-agent mic capture stopped');
  }

  private onChunk(chunk: Float32Array): void {
    // AudioCapture also exposes an optional accumulated buffer. The mic
    // driver owns its own bounded utterance buffers, so discard that copy on
    // every callback instead of retaining an entire long-running session.
    this.capture.clearBuffer();
    if (this.stopped || chunk.length === 0) return;

    const chunkMs = (chunk.length * 1000) / SAMPLE_RATE_HZ;
    const level = rms(chunk);

    // While a reply is audible the frame is still examined — just by the
    // barge-in gate rather than the turn segmenter, whose threshold would
    // happily accept the reply's own echo as user speech.
    if (this.replyAudible) {
      this.evaluateBargeIn(chunk, level, chunkMs);
      return;
    }
    // Strict turn-taking for capture: frames arriving while the STT -> LLM ->
    // TTS pass runs (before any audio exists to interrupt) are not buffered.
    if (this.processing) return;
    const threshold = Math.max(
      this.options.speechThreshold,
      this.noiseFloor * SPEECH_FLOOR_MULTIPLIER,
    );
    const isSpeech = level >= threshold;

    if (level < this.noiseFloor) {
      this.noiseFloor = level;
    } else if (!isSpeech) {
      this.noiseFloor += (level - this.noiseFloor) * NOISE_FLOOR_RISE;
    }

    if (!this.inSpeech) {
      this.preRoll.push(chunk);
      while (this.preRoll.length > PRE_ROLL_CHUNKS) this.preRoll.shift();
      if (isSpeech) {
        this.inSpeech = true;
        this.speechMs = chunkMs;
        this.silenceMs = 0;
        this.utterance = [...this.preRoll];
        this.utteranceSamples = this.preRoll.reduce((sum, item) => sum + item.length, 0);
        this.preRoll = [];
      }
      return;
    }

    this.utterance.push(chunk);
    this.utteranceSamples += chunk.length;
    if (isSpeech) {
      this.speechMs += chunkMs;
      this.silenceMs = 0;
    } else {
      this.silenceMs += chunkMs;
    }

    const utteranceMs = (this.utteranceSamples * 1000) / SAMPLE_RATE_HZ;
    if (
      this.silenceMs >= this.options.silenceDurationMs
      || utteranceMs >= this.options.maxRecordingDurationMs
    ) {
      const audio = this.concatUtterance();
      const hadSpeech = this.speechMs >= MIN_SPEECH_MS;
      this.resetSegmentation();
      if (hadSpeech) this.currentTurnPromise = this.processTurn(audio);
    }
  }

  /**
   * Decide whether this frame, captured while a reply is audible, is the user
   * taking the turn back.
   *
   * Two independent bars must both be cleared, for a sustained run of frames:
   * an absolute one well above the ordinary speech threshold, and a relative
   * one above the echo residual actually measured on this device during this
   * playout. The relative bar is what makes the gate safe without a full AEC
   * guarantee: the reply's own leakage raises the floor it has to beat, so the
   * agent cannot interrupt itself no matter how loud the speaker is.
   */
  private evaluateBargeIn(chunk: Float32Array, level: number, chunkMs: number): void {
    this.playoutMs += chunkMs;
    if (!this.options.bargeInEnabled || this.bargeInFired) return;
    if (this.playoutMs <= BARGE_IN_GRACE_MS) {
      // Still converging: use the window to seed the echo estimate rather than
      // to judge anything.
      this.echoFloor = Math.max(this.echoFloor, level);
      return;
    }

    const threshold = Math.max(
      this.options.speechThreshold * BARGE_IN_THRESHOLD_MULTIPLIER,
      this.echoFloor * BARGE_IN_ECHO_MULTIPLIER,
    );
    if (level < threshold) {
      this.bargeMs = 0;
      this.bargeFrames = [];
      // Only quiet-enough frames update the estimate, so sustained user speech
      // cannot inflate the very floor it has to clear.
      this.echoFloor += (level - this.echoFloor) * ECHO_FLOOR_RISE;
      return;
    }

    this.bargeMs += chunkMs;
    this.bargeFrames.push(chunk);
    while (this.bargeFrames.length > PRE_ROLL_CHUNKS) this.bargeFrames.shift();
    if (this.bargeMs < BARGE_IN_MIN_SPEECH_MS) return;
    this.bargeInFired = true;
    logger.info(
      `Barge-in at ${Math.round(this.playoutMs)} ms of playout `
      + `(level=${level.toFixed(4)}, threshold=${threshold.toFixed(4)})`,
    );
    // The frames that cleared the gate are the user's own voice by
    // construction, so carry them into the next utterance's pre-roll: without
    // them the words that took the turn back would be missing from the
    // transcript. Handed over through `resetSegmentation`, which runs after
    // this turn unwinds and would otherwise clear the pre-roll.
    this.pendingBargePreRoll = this.bargeFrames;
    this.bargeFrames = [];
    // Stop playout synchronously so the speaker goes quiet on this frame; the
    // turn's own `finally` restores the listening phase.
    this.playback.stop();
    this.callbacks.onBargeIn?.();
  }

  private resetBargeInGate(): void {
    this.replyAudible = false;
    this.playoutMs = 0;
    this.echoFloor = 0;
    this.bargeMs = 0;
    this.bargeInFired = false;
    this.bargeFrames = [];
  }

  /**
   * Stop the in-flight reply's playback (if any) and await the turn that was
   * producing it. Used by `VoiceSession.interrupt()` — unlike `stop()`, the
   * microphone keeps capturing afterward.
   */
  async interruptCurrentTurn(): Promise<void> {
    this.playback.stop();
    const pending = this.currentTurnPromise;
    if (pending) {
      await pending.catch(() => { /* already reported through onError */ });
    }
  }

  private concatUtterance(): Float32Array {
    const output = new Float32Array(this.utteranceSamples);
    let offset = 0;
    for (const chunk of this.utterance) {
      output.set(chunk, offset);
      offset += chunk.length;
    }
    return output;
  }

  private resetSegmentation(): void {
    // A barge-in's confirmed speech survives the reset that follows the
    // interrupted turn — it is the opening of the next utterance, not stale
    // state from the previous one.
    this.preRoll = this.pendingBargePreRoll;
    this.pendingBargePreRoll = [];
    this.utterance = [];
    this.utteranceSamples = 0;
    this.inSpeech = false;
    this.speechMs = 0;
    this.silenceMs = 0;
  }

  private async processTurn(audio: Float32Array): Promise<void> {
    const epoch = this.sessionEpoch;
    this.processing = true;
    this.callbacks.onPhase?.('processing');
    try {
      const result = await processVoiceTurn(audio);
      if (this.stopped || epoch !== this.sessionEpoch) return;

      await this.callbacks.onTurn?.({
        userText: result.transcription?.trim() ?? '',
        assistantText: result.assistantResponse?.trim() ?? '',
      });

      if (this.options.autoPlayTts) {
        await this.playResultAudio(result);
      }

      if (this.stopped || epoch !== this.sessionEpoch) return;
      if (!this.options.continuousMode) {
        this.stop();
      }
    } catch (error) {
      const normalized = error instanceof Error ? error : new Error(String(error));
      if (this.stopped || epoch !== this.sessionEpoch) {
        logger.debug(`Discarded cancelled voice turn: ${normalized.message}`);
        return;
      }
      logger.warning(`Voice turn failed: ${normalized.message}`);
      this.callbacks.onError?.(normalized);
    } finally {
      if (epoch === this.sessionEpoch) {
        this.processing = false;
        this.resetSegmentation();
        this.currentTurnPromise = null;
        if (!this.stopped) this.callbacks.onPhase?.('listening');
      }
    }
  }

  private async playResultAudio(result: VoiceAgentResult): Promise<void> {
    // `synthesizedAudio` is a self-describing WAV container (commons wraps
    // the raw TTS PCM before returning it), so no separate sample-rate/
    // encoding fields are needed to play it back.
    const bytes = result.synthesizedAudio;
    if (!bytes || bytes.byteLength === 0) return;
    // The `finally` restores the processing phase even when playout is cut short
    // by an interrupt, so the panel cannot latch on "Speaking" over a silent
    // speaker; `processTurn`'s own `finally` then returns it to listening.
    this.callbacks.onPhase?.('speaking');
    // Arm the barge-in gate for exactly the window in which sound is leaving
    // the speaker. Outside it, `onChunk` runs the ordinary segmenter.
    this.resetBargeInGate();
    this.replyAudible = true;
    try {
      await this.playback.playEncoded(bytes);
    } finally {
      this.replyAudible = false;
      this.callbacks.onPhase?.('processing');
    }
  }
}

function positiveOr(value: number | undefined, fallback: number): number {
  return value != null && value > 0 ? value : fallback;
}

function rms(samples: Float32Array): number {
  if (samples.length === 0) return 0;
  let sum = 0;
  for (let i = 0; i < samples.length; i += 1) {
    const sample = samples[i] ?? 0;
    sum += sample * sample;
  }
  return Math.sqrt(sum / samples.length);
}
