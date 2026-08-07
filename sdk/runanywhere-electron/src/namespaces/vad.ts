// The vad namespace: voice-activity detection over the proto-byte backend. The
// built-in energy detector is a component (no model); detect/process run one
// frame at a time and openStream feeds them from a live capture.
import { VADConfiguration, VADProcessRequest, VADResult } from '@runanywhere/proto-ts/vad_options';

import { audioToRaw } from '../audio.js';
import type { RaBackend } from '../backend.js';
import { AsyncQueue } from '../stream.js';
import type { AudioInput } from '../types.js';
import type { AudioFormatSpec } from './stt.js';
import type { ModelResolver } from './llm.js';

/** Voice-activity detection controls. Mirrors Swift `VadOptions`. */
export interface VadOptions {
  /** VAD model id (for model-based detectors); the built-in energy VAD needs none. */
  model?: string;
  activationThreshold?: number;
  sampleRate?: number;
}

/** Per-frame VAD outcome. */
export interface VadFrame {
  isSpeech: boolean;
  confidence: number;
}

/** A speech span. */
export interface Segment {
  startMs: number;
  endMs: number;
}

/** A one-shot detection result. Mirrors Swift `VadResult`. */
export interface VadResult {
  isSpeech: boolean;
  probability: number;
  segments: Segment[];
}

/** A streamed VAD event. */
export type VadEvent = { type: 'activity'; isSpeech: boolean; probability: number };

/** A live VAD session fed one frame at a time. */
export interface VadStream {
  readonly events: AsyncIterable<VadEvent>;
  pushFrame(frame: AudioInput): void;
  close(): Promise<void>;
}

export interface VadNamespace {
  /** Configure the detector (or the calibrated default when omitted). */
  configure(options?: VadOptions): Promise<void>;
  /** Classify one whole audio buffer. */
  detect(audio: AudioInput, options?: VadOptions): Promise<VadResult>;
  /** Classify one frame of 16-bit PCM audio. */
  process(pcm16: Uint8Array): Promise<VadFrame>;
  /** Open a live session fed with frames. */
  openStream(format: AudioFormatSpec, options?: VadOptions): VadStream;
  /** Reset detector state. */
  reset(): Promise<void>;
}

function processRequest(audio: { audioData: Uint8Array; encoding: number; sampleRate: number; channels: number }): Uint8Array {
  return VADProcessRequest.encode(
    VADProcessRequest.fromPartial({
      audio: {
        audioData: audio.audioData,
        encoding: audio.encoding,
        sampleRate: audio.sampleRate,
        channels: audio.channels,
      },
    })
  ).finish();
}

export function createVadNamespace(backend: RaBackend, resolve: ModelResolver): VadNamespace {
  async function configure(options: VadOptions = {}): Promise<void> {
    const cfg = VADConfiguration.fromPartial({
      ...(options.sampleRate !== undefined ? { sampleRate: options.sampleRate } : {}),
      ...(options.activationThreshold !== undefined
        ? { activationThreshold: options.activationThreshold }
        : {}),
    });
    await backend.vadConfigure(VADConfiguration.encode(cfg).finish());
  }

  return {
    configure,

    async detect(audio, options) {
      if (options?.model) await resolve(options.model);
      if (options) await configure(options);
      const raw = audioToRaw(audio);
      const out = VADResult.decode(await backend.vadProcess(processRequest(raw)));
      return { isSpeech: out.isSpeech, probability: out.confidence, segments: [] };
    },

    async process(pcm16) {
      const req = VADProcessRequest.fromPartial({ audio: { audioData: pcm16 } });
      const out = VADResult.decode(await backend.vadProcess(VADProcessRequest.encode(req).finish()));
      return { isSpeech: out.isSpeech, confidence: out.confidence };
    },

    openStream(_format, _options) {
      const q = new AsyncQueue<VadEvent>();
      return {
        events: q,
        pushFrame(frame) {
          const raw = audioToRaw(frame);
          void backend
            .vadProcess(processRequest(raw))
            .then((bytes) => {
              const out = VADResult.decode(bytes);
              q.push({ type: 'activity', isSpeech: out.isSpeech, probability: out.confidence });
            })
            .catch((e) => q.fail(e));
        },
        async close() {
          q.complete();
          await backend.vadReset();
        },
      };
    },

    async reset() {
      await backend.vadReset();
    },
  };
}
