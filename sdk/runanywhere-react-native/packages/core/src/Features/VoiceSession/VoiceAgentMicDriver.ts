/**
 * VoiceAgentMicDriver.ts — microphone audio ingress for the RN voice agent.
 *
 * The commons C ABI owns NO microphone (rac_voice_agent.h "audio-ingress
 * contract"): subscribing to `streamVoiceAgent()` alone is dead air. The
 * platform SDK must capture mic audio and push utterances into the core, or
 * the pipeline never sees PCM → VAD/STT get nothing → the LLM has no input →
 * no reply. This driver closes that gap for RN.
 *
 * Mirrors the Kotlin/Flutter `VoiceAgentMicDriver`: capture 16 kHz mono PCM16
 * via {@link AudioCaptureManager}, segment utterances with energy-based
 * endpointing, and run each utterance through `processVoiceTurn` (the one-shot
 * VAD→STT→LLM→TTS C entry, which on this build also re-runs the loaded VAD
 * model over the submitted buffer). The transcription + assistant response are
 * surfaced via {@link VoiceAgentMicCallbacks.onTurn}, and the synthesized TTS
 * reply is played through {@link AudioPlaybackManager}.
 *
 * The endpointing is intentionally coarse — it only decides where one
 * utterance ends; the C++ pipeline VADs each submitted buffer. Mic chunks that
 * arrive while a turn is processing (or while the reply is playing) are
 * dropped: the pipeline is strictly turn-taking (no barge-in), which also
 * avoids transcribing the device's own TTS output.
 */

import { AudioCaptureManager } from './AudioCaptureManager';
import { AudioPlaybackManager } from './AudioPlaybackManager';
import { processVoiceTurn } from '../../Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('VoiceAgentMicDriver');

/** A completed turn: what the user said and how the agent replied. */
export interface VoiceAgentMicTurn {
  userText: string;
  assistantText: string;
}

/** Coarse pipeline phase, for UI status. */
export type VoiceAgentMicPhase = 'listening' | 'processing' | 'speaking';

export interface VoiceAgentMicCallbacks {
  /** A turn finished: user transcription + assistant reply. */
  onTurn?: (turn: VoiceAgentMicTurn) => void;
  /** Coarse phase transitions (listening / processing / speaking). */
  onPhase?: (phase: VoiceAgentMicPhase) => void;
  /** A non-fatal turn error (capture continues). */
  onError?: (error: Error) => void;
}

const SAMPLE_RATE_HZ = 16000;
const BYTES_PER_SAMPLE = 2;

/** Absolute floor for the adaptive speech threshold (normalized RMS). */
const SPEECH_RMS_THRESHOLD = 0.015;
/** Speech must exceed this multiple of the tracked ambient noise floor. */
const SPEECH_FLOOR_MULTIPLIER = 2.2;
/** Per-chunk rate at which the ambient floor creeps toward louder ambient. */
const NOISE_FLOOR_RISE = 0.05;
/** Trailing silence that closes an utterance. */
const END_OF_UTTERANCE_SILENCE_MS = 800;
/** Utterances with less accumulated speech than this are discarded as noise. */
const MIN_SPEECH_MS = 300;
/** Hard cap so a noisy room cannot grow an unbounded buffer. */
const MAX_UTTERANCE_MS = 15000;
/** Leading chunks kept so the utterance onset is not clipped. */
const PRE_ROLL_CHUNKS = 3;

export class VoiceAgentMicDriver {
  private readonly capture = new AudioCaptureManager();
  private readonly playback = new AudioPlaybackManager();
  private callbacks: VoiceAgentMicCallbacks = {};

  private stopped = false;
  private processing = false;

  // Segmentation state.
  private preRoll: Uint8Array[] = [];
  private utterance: Uint8Array[] = [];
  private utteranceBytes = 0;
  private inSpeech = false;
  private speechMs = 0;
  private silenceMs = 0;
  private noiseFloor = SPEECH_RMS_THRESHOLD;

  /**
   * Request mic permission and begin capture. Returns `false` if the
   * permission was denied (caller should surface it); throws on capture
   * failure.
   */
  async start(callbacks: VoiceAgentMicCallbacks = {}): Promise<boolean> {
    this.callbacks = callbacks;
    this.stopped = false;

    const granted = await this.capture.requestPermission();
    if (!granted) {
      return false;
    }

    // The voice agent runs a single full-duplex (.playAndRecord) session for the
    // whole turn-taking loop so TTS replies can play through the speaker while
    // the mic session stays live. Activate it BEFORE startRecording so capture
    // reuses it instead of forcing the output-only .record session — under
    // .record, playback cannot claim the output and trips
    // AVAudioSessionErrorInsufficientPriority ('!pri', OSStatus 561017449).
    // Mirrors the iOS Swift driver's configureVoiceAudioSession(); no-op on
    // Android.
    await this.capture.activateAudioSession();
    await this.capture.startRecording((chunk) => this.onChunk(chunk));
    this.callbacks.onPhase?.('listening');
    logger.info('Voice-agent mic capture started');
    return true;
  }

  /** Stop capture + playback and reset segmentation. */
  stop(): void {
    if (this.stopped) return;
    this.stopped = true;
    try {
      this.capture.stopRecording();
    } catch (e) {
      logger.warning(`stopRecording failed: ${String(e)}`);
    }
    this.playback.stop();
    this.resetSegmentation();
    logger.info('Voice-agent mic capture stopped');
  }

  private onChunk(chunk: Uint8Array): void {
    // Drop chunks while a turn is processing or the reply is playing
    // (turn-taking, no barge-in, no self-transcription).
    if (this.stopped || this.processing || chunk.length === 0) return;

    const chunkMs = (chunk.length * 1000) / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE);
    const level = this.rms(chunk);

    // Adaptive endpointing: track the ambient floor (drop instantly to any
    // quieter level, creep up only while not in speech) and require a chunk to
    // rise clearly above that floor to count as speech.
    const speechThreshold = Math.max(
      SPEECH_RMS_THRESHOLD,
      this.noiseFloor * SPEECH_FLOOR_MULTIPLIER
    );
    const isSpeech = level >= speechThreshold;
    if (level < this.noiseFloor) {
      this.noiseFloor = level;
    } else if (!isSpeech) {
      this.noiseFloor += (level - this.noiseFloor) * NOISE_FLOOR_RISE;
    }

    if (!this.inSpeech) {
      this.preRoll.push(chunk);
      while (this.preRoll.length > PRE_ROLL_CHUNKS) {
        this.preRoll.shift();
      }
      if (isSpeech) {
        this.inSpeech = true;
        this.speechMs = chunkMs;
        this.silenceMs = 0;
        this.utterance = [...this.preRoll];
        this.utteranceBytes = this.preRoll.reduce((n, c) => n + c.length, 0);
        this.preRoll = [];
      }
      return;
    }

    this.utterance.push(chunk);
    this.utteranceBytes += chunk.length;
    if (isSpeech) {
      this.speechMs += chunkMs;
      this.silenceMs = 0;
    } else {
      this.silenceMs += chunkMs;
    }

    const utteranceMs =
      (this.utteranceBytes * 1000) / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE);
    if (
      this.silenceMs >= END_OF_UTTERANCE_SILENCE_MS ||
      utteranceMs >= MAX_UTTERANCE_MS
    ) {
      const audio = this.concatUtterance();
      const hadSpeech = this.speechMs >= MIN_SPEECH_MS;
      this.resetSegmentation();
      if (hadSpeech) {
        void this.processTurn(audio);
      } else {
        logger.debug(
          `Utterance discarded (${this.speechMs}ms speech < ${MIN_SPEECH_MS}ms)`
        );
      }
    }
  }

  private concatUtterance(): Uint8Array {
    const out = new Uint8Array(this.utteranceBytes);
    let offset = 0;
    for (const c of this.utterance) {
      out.set(c, offset);
      offset += c.length;
    }
    return out;
  }

  private resetSegmentation(): void {
    this.inSpeech = false;
    this.speechMs = 0;
    this.silenceMs = 0;
    this.utterance = [];
    this.utteranceBytes = 0;
    this.preRoll = [];
  }

  private async processTurn(audio: Uint8Array): Promise<void> {
    this.processing = true;
    this.callbacks.onPhase?.('processing');
    logger.info(`Submitting voice turn (${audio.length} bytes)`);
    try {
      const result = await processVoiceTurn(audio);

      const userText = (result.transcription ?? '').trim();
      const assistantText = (result.assistantResponse ?? '').trim();
      if (userText.length > 0 || assistantText.length > 0) {
        this.callbacks.onTurn?.({ userText, assistantText });
      }

      const wav = result.synthesizedAudio;
      if (wav && wav.byteLength > 0 && !this.stopped) {
        this.callbacks.onPhase?.('speaking');
        // `synthesizedAudio` is a complete WAV blob (commons emits WAV, header
        // included), so play it directly — NOT through play(), which would
        // treat the RIFF header + int16 samples as raw float32 PCM and re-wrap
        // it (→ fast/noisy garbage). Copy into a fresh ArrayBuffer-backed view
        // in case the source spans a larger or shared buffer.
        const copy = new Uint8Array(wav.byteLength);
        copy.set(wav);
        try {
          await this.playback.playWav(copy.buffer);
        } catch (e) {
          logger.warning(`Agent reply playback failed: ${String(e)}`);
        }
      }
    } catch (e) {
      const err = e instanceof Error ? e : new Error(String(e));
      logger.warning(`Voice turn failed: ${err.message}`);
      this.callbacks.onError?.(err);
    } finally {
      this.processing = false;
      this.resetSegmentation();
      if (!this.stopped) {
        this.callbacks.onPhase?.('listening');
      }
    }
  }

  private rms(chunk: Uint8Array): number {
    const samples = Math.floor(chunk.length / BYTES_PER_SAMPLE);
    if (samples === 0) return 0;
    const view = new DataView(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    let sum = 0;
    for (let i = 0; i < samples; i++) {
      const sample = view.getInt16(i * BYTES_PER_SAMPLE, true);
      sum += sample * sample;
    }
    return Math.sqrt(sum / samples) / 32767;
  }
}
