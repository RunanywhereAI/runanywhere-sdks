/**
 * Browser microphone ingress for the split-WASM voice agent.
 *
 * AudioCapture supplies 16 kHz mono Float32 chunks. This driver performs only
 * coarse endpointing, then submits the completed utterance through the public
 * one-call `processVoiceTurn` SDK surface. It also holds capture in the
 * processing phase until reply playback finishes, preventing acoustic
 * feedback. STT, LLM, TTS, model routing, and event production remain owned
 * by the SDK provider.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';
import { processVoiceTurn } from '../Public/Extensions/RunAnywhere+VoiceAgent.js';
import type { VoiceAgentResult } from '@runanywhere/proto-ts/voice_agent_service';
import { AudioEncoding } from '@runanywhere/proto-ts/voice_events';
import { AudioCapture } from './AudioCapture.js';
import { AudioPlayback } from './AudioPlayback.js';

const logger = new SDKLogger('VoiceAgentMicDriver');

const SAMPLE_RATE_HZ = 16_000;
const SPEECH_RMS_THRESHOLD = 0.015;
const SPEECH_FLOOR_MULTIPLIER = 2.2;
const NOISE_FLOOR_RISE = 0.05;
const END_OF_UTTERANCE_SILENCE_MS = 800;
const MIN_SPEECH_MS = 300;
const MAX_UTTERANCE_MS = 15_000;
const PRE_ROLL_CHUNKS = 3;

export type VoiceAgentMicPhase = 'listening' | 'processing';

export interface VoiceAgentMicTurn {
  userText: string;
  assistantText: string;
}

export interface VoiceAgentMicCallbacks {
  onTurn?: (turn: VoiceAgentMicTurn) => void | Promise<void>;
  onPhase?: (phase: VoiceAgentMicPhase) => void;
  onLevel?: (level: number) => void;
  onError?: (error: Error) => void;
}

export interface VoiceAgentMicOptions extends VoiceAgentMicCallbacks {
  silenceDurationMs?: number;
  speechThreshold?: number;
  maxRecordingDurationMs?: number;
  autoPlayTts?: boolean;
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
  private options: Required<Pick<VoiceAgentMicOptions,
    'silenceDurationMs' | 'speechThreshold' | 'maxRecordingDurationMs' |
    'autoPlayTts' | 'continuousMode'>> = {
      silenceDurationMs: END_OF_UTTERANCE_SILENCE_MS,
      speechThreshold: SPEECH_RMS_THRESHOLD,
      maxRecordingDurationMs: MAX_UTTERANCE_MS,
      autoPlayTts: true,
      continuousMode: true,
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
      ...callbacks
    } = options;
    this.callbacks = callbacks;
    this.options = {
      silenceDurationMs: positiveOr(silenceDurationMs, END_OF_UTTERANCE_SILENCE_MS),
      speechThreshold: positiveOr(speechThreshold, SPEECH_RMS_THRESHOLD),
      maxRecordingDurationMs: positiveOr(maxRecordingDurationMs, MAX_UTTERANCE_MS),
      autoPlayTts: autoPlayTts ?? true,
      continuousMode: continuousMode ?? true,
    };
    const epoch = ++this.sessionEpoch;
    this.stopped = false;
    this.processing = false;
    this.noiseFloor = this.options.speechThreshold;
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
    this.resetSegmentation();
    logger.info('Voice-agent mic capture stopped');
  }

  private onChunk(chunk: Float32Array): void {
    // AudioCapture also exposes an optional accumulated buffer. The mic
    // driver owns its own bounded utterance buffers, so discard that copy on
    // every callback instead of retaining an entire long-running session.
    this.capture.clearBuffer();
    // Strict turn-taking: avoid buffering microphone/TTS feedback while the
    // STT -> LLM -> TTS pass is running.
    if (this.stopped || this.processing || chunk.length === 0) return;

    const chunkMs = (chunk.length * 1000) / SAMPLE_RATE_HZ;
    const level = rms(chunk);
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
      if (hadSpeech) void this.processTurn(audio);
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
    this.preRoll = [];
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
        if (!this.stopped) this.callbacks.onPhase?.('listening');
      }
    }
  }

  private async playResultAudio(result: VoiceAgentResult): Promise<void> {
    const bytes = result.synthesizedAudio;
    const sampleRate = result.synthesizedAudioSampleRateHz;
    if (!bytes || bytes.byteLength === 0 || sampleRate <= 0) return;
    const samples = decodeAudio(bytes, result.synthesizedAudioEncoding);
    if (samples.length > 0) await this.playback.play(samples, sampleRate);
  }
}

function positiveOr(value: number | undefined, fallback: number): number {
  return value != null && value > 0 ? value : fallback;
}

function decodeAudio(bytes: Uint8Array, encoding: AudioEncoding): Float32Array {
  if (encoding === AudioEncoding.AUDIO_ENCODING_PCM_S16_LE) {
    const count = Math.floor(bytes.byteLength / 2);
    const view = new DataView(bytes.buffer, bytes.byteOffset, count * 2);
    const samples = new Float32Array(count);
    for (let index = 0; index < count; index += 1) {
      samples[index] = view.getInt16(index * 2, true) / 0x8000;
    }
    return samples;
  }
  if (encoding === AudioEncoding.AUDIO_ENCODING_PCM_F32_LE) {
    const count = Math.floor(bytes.byteLength / 4);
    const view = new DataView(bytes.buffer, bytes.byteOffset, count * 4);
    const samples = new Float32Array(count);
    for (let index = 0; index < count; index += 1) {
      samples[index] = view.getFloat32(index * 4, true);
    }
    return samples;
  }
  return new Float32Array(0);
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
