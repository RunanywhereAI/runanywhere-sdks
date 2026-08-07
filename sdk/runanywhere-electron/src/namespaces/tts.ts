// The tts namespace: synthesize text to audio over the proto-byte backend, with a
// streaming variant and a voice list. Auto-loads the speech-synthesis model named
// in options.model. Device playback (Swift's speak()) has no equivalent here: the
// Node host has no audio device, so the renderer plays the returned PCM itself.
import {
  TTSOptions,
  TTSOutput,
  TTSStreamEvent,
  TTSStreamEventKind,
  TTSSynthesisRequest,
  TTSVoiceList,
} from '@runanywhere/proto-ts/tts_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';

import type { RaBackend } from '../backend.js';
import { bridgeStream } from '../stream.js';
import type { ModelResolver } from './llm.js';

/** How the returned PCM samples are encoded, so the caller can play them back. */
export type SampleFormat = 'f32' | 's16' | 'encoded';

// sherpa/piper emits float32 PCM (AUDIO_FORMAT_PCM); s16 is little-endian int16;
// anything else (mp3/wav/opus…) is a container the caller decodes.
function sampleFormatOf(f: AudioFormat): SampleFormat {
  if (f === AudioFormat.AUDIO_FORMAT_PCM_S16LE) return 's16';
  if (f === AudioFormat.AUDIO_FORMAT_PCM) return 'f32';
  return 'encoded';
}

/** Synthesis controls. Mirrors Swift `TtsOptions`. */
export interface TtsOptions {
  /** Speech-synthesis model id; loaded (and downloaded) first if not resident. */
  model?: string;
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  sampleRate?: number;
}

/** Synthesized audio (raw PCM bytes plus its format). */
export interface Audio {
  data: Uint8Array;
  sampleRate: number;
  durationMs: number;
  /** Sample encoding of `data` (`f32`/`s16` raw PCM, or `encoded` container). */
  format: SampleFormat;
}

/** One chunk of a streamed synthesis. */
export interface AudioChunk {
  data: Uint8Array;
  index: number;
  isFinal: boolean;
  format: SampleFormat;
}

/** A synthesis voice. */
export interface Voice {
  id: string;
  name: string;
  language: string;
}

export interface TtsNamespace {
  /** Synthesize `text` to audio. */
  synthesize(text: string, options?: TtsOptions): Promise<Audio>;
  /** Stream synthesized audio chunk by chunk. */
  synthesizeStream(text: string, options?: TtsOptions): AsyncIterableIterator<AudioChunk>;
  /** The voices the loaded synthesis model offers. */
  voices(): Promise<Voice[]>;
  /** Stop any in-flight synthesis. */
  stop(): Promise<void>;
}

function toTtsOptions(o: TtsOptions = {}): Partial<TTSOptions> {
  const out: Partial<TTSOptions> = {
    speed: o.speed ?? 1.0,
    pitch: o.pitch ?? 1.0,
  };
  if (o.voice !== undefined) out.voice = o.voice;
  if (o.language !== undefined) out.languageCode = o.language;
  if (o.sampleRate !== undefined) out.sampleRate = o.sampleRate;
  return out;
}

export function createTtsNamespace(backend: RaBackend, resolve: ModelResolver): TtsNamespace {
  return {
    async synthesize(text, options) {
      if (options?.model) await resolve(options.model);
      const req = TTSSynthesisRequest.fromPartial({ text, options: toTtsOptions(options) });
      const out = TTSOutput.decode(await backend.ttsSynthesize(TTSSynthesisRequest.encode(req).finish()));
      return {
        data: out.audioData,
        sampleRate: out.sampleRate,
        durationMs: out.durationMs,
        format: sampleFormatOf(out.audioFormat),
      };
    },

    synthesizeStream(text, options) {
      return bridgeStream<AudioChunk>(async (sink) => {
        if (options?.model) await resolve(options.model);
        const req = TTSSynthesisRequest.encode(
          TTSSynthesisRequest.fromPartial({ text, options: toTtsOptions(options) })
        ).finish();
        return backend.ttsSynthesizeStream(req, (bytes) => {
          const ev = TTSStreamEvent.decode(bytes);
          if (ev.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK && ev.output) {
            sink.push({
              data: ev.output.audioData,
              index: ev.chunkIndex,
              isFinal: ev.output.isFinal,
              format: sampleFormatOf(ev.output.audioFormat),
            });
          }
        });
      });
    },

    async voices() {
      const list = TTSVoiceList.decode(await backend.ttsListVoices());
      return list.voices.map((v) => ({ id: v.id, name: v.displayName || v.id, language: v.languageCode ?? '' }));
    },

    async stop() {
      await backend.ttsStop();
    },
  };
}
