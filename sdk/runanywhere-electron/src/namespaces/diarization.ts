// The diarization namespace: who-spoke-when over the proto-byte backend.
// Auto-loads the speaker-diarization model named in options.model.
import { DiarizationOptions, DiarizationRequest, DiarizationResult } from '@runanywhere/proto-ts/diarization';

import { audioToRaw } from '../audio.js';
import type { RaBackend } from '../backend.js';
import type { AudioInput } from '../types.js';
import type { ModelResolver } from './llm.js';

/** Diarization controls. Mirrors Swift `DiarizationOptions`. */
export interface DiarizationParams {
  /** Diarization model id; loaded (and downloaded) first if not resident. */
  model?: string;
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
}

/** One speaker-labelled span. */
export interface SpeakerSegment {
  startMs: number;
  endMs: number;
  speakerIndex: number;
  speakerId: string;
}

/** A diarization result. */
export interface Diarization {
  segments: SpeakerSegment[];
  speakerCount: number;
  durationMs: number;
}

export interface DiarizationNamespace {
  /** Diarize an audio buffer. */
  diarize(audio: AudioInput, options?: DiarizationParams): Promise<Diarization>;
}

export function createDiarizationNamespace(backend: RaBackend, resolve: ModelResolver): DiarizationNamespace {
  return {
    async diarize(audio, options) {
      if (options?.model) await resolve(options.model);
      const raw = audioToRaw(audio);
      // Carry the input's real encoding; the decoder defaults to float32 and
      // would reject 16-bit PCM otherwise.
      const opts: Partial<DiarizationOptions> = {
        encoding: raw.encoding,
        sampleRate: raw.sampleRate,
        channels: raw.channels,
      };
      if (options?.threshold !== undefined) opts.threshold = options.threshold;
      if (options?.minimumDurationMs !== undefined) opts.minimumDurationMs = options.minimumDurationMs;
      if (options?.mergeGapMs !== undefined) opts.mergeGapMs = options.mergeGapMs;
      const req = DiarizationRequest.fromPartial({ audioData: raw.audioData, options: opts });
      const out = DiarizationResult.decode(await backend.diarize(DiarizationRequest.encode(req).finish()));
      return {
        segments: out.segments.map((s) => ({
          startMs: s.startMs,
          endMs: s.endMs,
          speakerIndex: s.speakerIndex,
          speakerId: s.speakerId,
        })),
        speakerCount: out.speakerCount,
        durationMs: out.audioDurationMs,
      };
    },
  };
}
