/**
 * VoiceAgentMicDriver.ts
 *
 * Audio ingress for the voice agent. The C ABI owns NO microphone access
 * (rac_voice_agent.h "Audio-Ingress Contract"): the platform SDK captures raw
 * mic frames and pushes them continuously into the C core via
 * `rac_voice_agent_feed_audio_proto` (`voiceAgentFeedAudioProto`). The core
 * performs energy-based utterance segmentation and runs the STT -> LLM -> TTS
 * turn pipeline itself, returning the synthesized reply inline for playback.
 * This driver is therefore a thin capture -> feed -> play loop with NO SDK-side
 * VAD. Turn VoiceEvents fan out through the handle callback, so
 * `RunAnywhere.streamVoiceAgent()` collectors observe them without extra wiring.
 *
 * Mirrors `sdk/runanywhere-swift/.../VoiceAgentMicDriver.swift` and
 * `sdk/runanywhere-kotlin/.../VoiceAgentMicDriver.kt`. Segmentation/endpointing
 * lives in the C core; frames captured while a turn is processing are dropped
 * by the core (and the bounded queue here) so the device's own TTS playout is
 * not re-fed (strict turn-taking, no barge-in).
 */

import { AudioCaptureManager } from '../VoiceSession/AudioCaptureManager';
import { AudioPlaybackManager } from '../VoiceSession/AudioPlaybackManager';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule } from '../../native';
import { arrayBufferToBytes } from '../../services/ProtoBytes';
import { VoiceAgentResult as VoiceAgentResultMessage } from '@runanywhere/proto-ts/voice_agent_service';
import { AudioEncoding } from '@runanywhere/proto-ts/voice_events';

const SAMPLE_RATE_HZ = 16_000;
const CHANNELS = 1;
/** Bounded backlog so a slow turn cannot grow the queue without limit. */
const CHANNEL_CAPACITY = 128;
/** Poll interval when no captured frames are pending. */
const FEED_IDLE_SLEEP_MS = 20;

/**
 * Captures mic audio and feeds raw frames to the in-core voice agent.
 * {@link start} runs until {@link stop} is called. The capture callback only
 * enqueues frames; a single async feed loop drains them and calls the core,
 * which blocks for the duration of a turn when an utterance closes and returns
 * the synthesized reply inline. We play it and drop any backlog captured during
 * the turn so the device's own playout is not re-fed.
 */
export class VoiceAgentMicDriver {
  private readonly logger = new SDKLogger('VoiceAgentMic');
  private readonly capture = new AudioCaptureManager();
  private readonly playback = new AudioPlaybackManager();

  private stopped = false;
  private queue: Uint8Array[] = [];

  /** Begin mic capture + feed loop. Resolves once capture has started. */
  async start(): Promise<void> {
    const granted = await this.capture.requestPermission();
    if (!granted) {
      throw new Error('Microphone permission denied');
    }
    this.stopped = false;
    this.queue = [];
    // The voice agent runs a single full-duplex (.playAndRecord) session for the
    // whole turn-taking loop so TTS replies can play through the speaker while
    // the mic stays live. Activate it BEFORE startRecording so capture reuses it
    // instead of forcing the output-only .record session (which silences replies
    // and trips cannotStartPlaying). Mirrors the iOS Swift driver's
    // configureVoiceAudioSession(); no-op on Android.
    await this.capture.activateAudioSession();
    await this.capture.startRecording((chunk) => this.enqueueChunk(chunk));
    this.logger.info('Voice-agent mic capture started');
    void this.feedLoop();
  }

  /** Stop capture + playback and reset state. */
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
    this.queue = [];
    this.logger.info('Voice-agent mic capture stopped');
  }

  private enqueueChunk(chunk: Uint8Array): void {
    if (this.stopped || chunk.byteLength === 0) return;
    this.queue.push(chunk);
    if (this.queue.length > CHANNEL_CAPACITY) {
      this.queue.splice(0, this.queue.length - CHANNEL_CAPACITY);
    }
  }

  private drainChunks(): Uint8Array[] {
    if (this.queue.length === 0) return [];
    const drained = this.queue;
    this.queue = [];
    return drained;
  }

  /**
   * Drains captured frames and feeds them to the core. A non-empty
   * `synthesizedAudio` in the returned result means the core closed an
   * utterance and ran a full turn this call; we play the reply and drop any
   * backlog captured during the turn so the device's own playout is not re-fed.
   */
  private async feedLoop(): Promise<void> {
    const native = requireNativeModule();
    while (!this.stopped) {
      const chunks = this.drainChunks();
      if (chunks.length === 0) {
        await VoiceAgentMicDriver.sleep(FEED_IDLE_SLEEP_MS);
        continue;
      }

      for (const chunk of chunks) {
        if (this.stopped) return;
        try {
          const resultBytes = await native.voiceAgentFeedAudioProto(
            VoiceAgentMicDriver.toArrayBuffer(chunk),
            SAMPLE_RATE_HZ,
            CHANNELS,
            AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
            false
          );
          if (this.stopped) return;
          const bytes = arrayBufferToBytes(resultBytes);
          if (bytes.byteLength === 0) continue; // utterance still open

          const result = VoiceAgentResultMessage.decode(bytes);
          if (result.errorMessage && result.errorMessage.length > 0) {
            this.logger.warning(`Voice turn failed: ${result.errorMessage}`);
          }
          if (await this.playReply(result)) {
            // Drop frames captured during the turn + playback.
            this.queue = [];
          }
        } catch (error) {
          this.logger.warning(
            `Voice feed threw: ${error instanceof Error ? error.message : String(error)}`
          );
        }
      }
    }
  }

  /**
   * Play the turn's synthesized reply through the shared playback sink.
   * Commons returns `synthesized_audio` as a complete WAV
   * (`rac_audio_float32_to_wav`), so the bytes are handed to the native player
   * as-is — not re-encoded. Returns true when a reply was played.
   */
  private async playReply(
    result: ReturnType<typeof VoiceAgentResultMessage.decode>
  ): Promise<boolean> {
    const audio = result.synthesizedAudio;
    if (!audio || audio.byteLength === 0) return false;

    const wav = VoiceAgentMicDriver.toArrayBuffer(audio);
    this.logger.info(`Playing agent reply (${audio.byteLength} WAV bytes)`);
    try {
      await this.playback.playWav(wav);
    } catch (error) {
      this.logger.warning(
        `Agent reply playback failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
    return true;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    return bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength
    ) as ArrayBuffer;
  }
}
