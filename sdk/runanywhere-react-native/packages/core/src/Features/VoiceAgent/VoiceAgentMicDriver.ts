/**
 * VoiceAgentMicDriver.ts
 *
 * Audio ingress for the voice agent. The C ABI owns NO microphone access
 * (rac_voice_agent.h "Audio-Ingress Contract"): the platform SDK must capture
 * mic audio and push complete utterances into the C core, or the session is
 * dead-air. This driver implements ingress mode 1 (per-utterance turns):
 * capture 16 kHz mono PCM16 via {@link AudioCaptureManager}, segment utterances
 * with energy-based endpointing, and submit each utterance through
 * `rac_voice_agent_process_voice_turn_proto` (`voiceAgentProcessTurnProto`).
 * Turn VoiceEvents fan out to the handle callback, so
 * `RunAnywhere.streamVoiceAgent()` collectors observe them without extra wiring.
 *
 * Mirrors `sdk/runanywhere-swift/.../VoiceAgentMicDriver.swift` and
 * `sdk/runanywhere-kotlin/.../VoiceAgentMicDriver.kt`. Endpointing is
 * energy-based; mic chunks that arrive while a turn is processing are discarded
 * (strict turn-taking, no barge-in — also avoids transcribing the device's own
 * TTS output).
 */

import { AudioCaptureManager } from '../VoiceSession/AudioCaptureManager';
import { AudioPlaybackManager } from '../VoiceSession/AudioPlaybackManager';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule } from '../../native';
import { arrayBufferToBytes } from '../../services/ProtoBytes';
import { VoiceAgentResult as VoiceAgentResultMessage } from '@runanywhere/proto-ts/voice_agent_service';

const SAMPLE_RATE_HZ = 16_000;
const BYTES_PER_SAMPLE = 2;
/** Absolute floor for the adaptive speech threshold (normalized RMS). */
const SPEECH_RMS_THRESHOLD = 0.015;
/** Speech must exceed this multiple of the tracked ambient noise floor. */
const SPEECH_FLOOR_MULTIPLIER = 2.2;
/** Per-chunk rate at which the ambient floor creeps up toward louder ambient. */
const NOISE_FLOOR_RISE = 0.05;
/** Trailing silence that closes an utterance. */
const END_OF_UTTERANCE_SILENCE_MS = 800;
/** Utterances with less accumulated speech than this are noise. */
const MIN_SPEECH_MS = 300;
/** Hard cap so a noisy room cannot grow an unbounded buffer. */
const MAX_UTTERANCE_MS = 15_000;
/** Leading chunks kept so the utterance onset is not clipped. */
const PRE_ROLL_CHUNKS = 3;

/**
 * Captures mic audio and drives per-utterance voice-agent turns. {@link start}
 * runs until {@link stop} is called. Segmentation runs synchronously inside the
 * capture callback; an utterance end kicks off an async turn, during which
 * incoming chunks are dropped (the `processing` gate) so the mic stays gated
 * while the device thinks / speaks.
 */
export class VoiceAgentMicDriver {
  private readonly logger = new SDKLogger('VoiceAgentMic');
  private readonly capture = new AudioCaptureManager();
  private readonly playback = new AudioPlaybackManager();

  private stopped = false;
  private processing = false;

  // Segmentation state.
  private preRoll: Uint8Array[] = [];
  private utterance: Uint8Array[] = [];
  private inSpeech = false;
  private speechMs = 0;
  private silenceMs = 0;
  private noiseFloor = SPEECH_RMS_THRESHOLD;

  /** Begin mic capture + segmentation. Resolves once capture has started. */
  async start(): Promise<void> {
    const granted = await this.capture.requestPermission();
    if (!granted) {
      throw new Error('Microphone permission denied');
    }
    this.stopped = false;
    // The voice agent runs a single full-duplex (.playAndRecord) session for the
    // whole turn-taking loop so TTS replies can play through the speaker while the
    // mic stays live. Activate it BEFORE startRecording so capture reuses it
    // instead of forcing the output-only .record session (which silences replies
    // and trips cannotStartPlaying). Mirrors the iOS Swift driver's
    // configureVoiceAudioSession(); no-op on Android.
    await this.capture.activateAudioSession();
    await this.capture.startRecording((chunk) => this.onChunk(chunk));
    this.logger.info('Voice-agent mic capture started');
  }

  /** Stop capture + playback and reset segmentation state. */
  async stop(): Promise<void> {
    if (this.stopped) return;
    this.stopped = true;
    try {
      this.capture.stopRecording();
    } catch {
      /* noop */
    }
    try {
      this.playback.stop();
    } catch {
      /* noop */
    }
    this.preRoll = [];
    this.utterance = [];
    this.inSpeech = false;
    this.logger.info('Voice-agent mic capture stopped');
  }

  private onChunk(chunk: Uint8Array): void {
    // Drop chunks while a turn is in flight (no barge-in) or after stop().
    if (this.stopped || this.processing || chunk.byteLength === 0) return;

    const chunkMs =
      (chunk.byteLength * 1000) / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE);
    // Adaptive endpointing: a fixed RMS threshold misses the end-of-utterance
    // pause on devices whose mic noise floor sits above the constant. Track the
    // ambient floor — drop instantly to any quieter level, creep up only while
    // not in speech — and require a chunk to rise clearly above it.
    const level = VoiceAgentMicDriver.rms(chunk);
    const speechThreshold = Math.max(
      SPEECH_RMS_THRESHOLD,
      this.noiseFloor * SPEECH_FLOOR_MULTIPLIER
    );
    const isSpeech = level >= speechThreshold;
    if (!this.inSpeech) {
      if (level < this.noiseFloor) {
        this.noiseFloor = level;
      } else if (!isSpeech) {
        this.noiseFloor += (level - this.noiseFloor) * NOISE_FLOOR_RISE;
      }
    }

    if (!this.inSpeech) {
      this.preRoll.push(chunk);
      if (this.preRoll.length > PRE_ROLL_CHUNKS) {
        this.preRoll.shift();
      }
      if (isSpeech) {
        this.inSpeech = true;
        this.speechMs = chunkMs;
        this.silenceMs = 0;
        this.utterance = [...this.preRoll];
        this.preRoll = [];
      }
      return;
    }

    this.utterance.push(chunk);
    if (isSpeech) {
      this.speechMs += chunkMs;
      this.silenceMs = 0;
    } else {
      this.silenceMs += chunkMs;
    }

    const utteranceBytes = this.utterance.reduce((n, c) => n + c.byteLength, 0);
    const utteranceMs =
      (utteranceBytes * 1000) / (SAMPLE_RATE_HZ * BYTES_PER_SAMPLE);
    if (
      this.silenceMs >= END_OF_UTTERANCE_SILENCE_MS ||
      utteranceMs >= MAX_UTTERANCE_MS
    ) {
      const speechMs = this.speechMs;
      const audio = VoiceAgentMicDriver.concat(this.utterance);
      this.inSpeech = false;
      this.utterance = [];
      this.speechMs = 0;
      this.silenceMs = 0;
      if (speechMs >= MIN_SPEECH_MS) {
        // Gate the mic for the duration of the turn (and TTS playback) so the
        // device does not transcribe its own reply. `processing` is cleared
        // once the turn + playback finish.
        this.processing = true;
        void this.processTurn(audio).finally(() => {
          this.processing = false;
        });
      } else {
        this.logger.debug(
          `Utterance discarded (${Math.round(speechMs)}ms speech < ${MIN_SPEECH_MS}ms)`
        );
      }
    }
  }

  private async processTurn(audio: Uint8Array): Promise<void> {
    if (this.stopped || audio.byteLength === 0) return;
    this.logger.info(`Submitting voice turn (${audio.byteLength} bytes)`);
    try {
      const native = requireNativeModule();
      const resultBytes = await native.voiceAgentProcessTurnProto(
        VoiceAgentMicDriver.toArrayBuffer(audio)
      );
      if (this.stopped) return;
      const bytes = arrayBufferToBytes(resultBytes);
      if (bytes.byteLength === 0) {
        this.logger.warning('Voice turn returned an empty result');
        return;
      }
      const result = VoiceAgentResultMessage.decode(bytes);
      if (result.errorMessage && result.errorMessage.length > 0) {
        this.logger.warning(`Voice turn failed: ${result.errorMessage}`);
      }
      await this.playReply(result);
    } catch (error) {
      this.logger.warning(
        `Voice turn threw: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Play the turn's synthesized reply through the shared playback sink. Runs
   * while `processing` is still set, so the mic stays gated while the device
   * speaks (no self-transcription). Commons returns `synthesized_audio` as a
   * complete WAV (`rac_audio_float32_to_wav`), so the bytes are handed to the
   * native player as-is — not re-encoded.
   */
  private async playReply(
    result: ReturnType<typeof VoiceAgentResultMessage.decode>
  ): Promise<void> {
    const audio = result.synthesizedAudio;
    if (!audio || audio.byteLength === 0) return;

    const wav = VoiceAgentMicDriver.toArrayBuffer(audio);
    this.logger.info(`Playing agent reply (${audio.byteLength} WAV bytes)`);
    try {
      await this.playback.playWav(wav);
    } catch (error) {
      this.logger.warning(
        `Agent reply playback failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /** Normalized RMS of a 16 kHz mono Int16-LE chunk (0..1). */
  private static rms(chunk: Uint8Array): number {
    const sampleCount = Math.floor(chunk.byteLength / BYTES_PER_SAMPLE);
    if (sampleCount === 0) return 0;
    const view = new DataView(
      chunk.buffer,
      chunk.byteOffset,
      sampleCount * BYTES_PER_SAMPLE
    );
    let sum = 0;
    for (let i = 0; i < sampleCount; i++) {
      const sample = view.getInt16(i * BYTES_PER_SAMPLE, true);
      sum += sample * sample;
    }
    return Math.sqrt(sum / sampleCount) / 32767;
  }

  private static concat(chunks: Uint8Array[]): Uint8Array {
    const total = chunks.reduce((n, c) => n + c.byteLength, 0);
    const out = new Uint8Array(total);
    let offset = 0;
    for (const c of chunks) {
      out.set(c, offset);
      offset += c.byteLength;
    }
    return out;
  }

  private static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    return bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength
    ) as ArrayBuffer;
  }
}
