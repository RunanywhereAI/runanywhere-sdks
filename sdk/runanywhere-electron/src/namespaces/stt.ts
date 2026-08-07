// The stt namespace: transcribe audio to text over the proto-byte backend, plus
// a live push-stream session. Auto-loads the speech-recognition model named in
// options.model, mirroring Swift.
import {
  STTOptions,
  STTOutput,
  STTServiceState,
  STTStreamEvent,
  STTStreamEventKind,
  STTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import { AudioEncoding } from '@runanywhere/proto-ts/model_types';

import { audioToSource, to16kPcm16 } from '../audio.js';
import type { RaBackend } from '../backend.js';
import { bridgeStream } from '../stream.js';
import type { AudioInput } from '../types.js';
import type { ModelResolver } from './llm.js';

/** Transcription controls. Mirrors Swift `SttOptions`. */
export interface SttOptions {
  /** Speech model id; loaded (and downloaded) first if not resident. */
  model?: string;
  /** BCP-47 tag; absent auto-detects. */
  language?: string;
  punctuation?: boolean;
  wordTimestamps?: boolean;
  diarization?: boolean;
  maxSpeakers?: number;
  translateToEnglish?: boolean;
}

/** A transcription result. */
export interface Transcription {
  text: string;
  language: string;
  confidence: number;
  durationMs: number;
}

/** The audio format a live stream is fed in. Raw PCM only (containers rejected). */
export interface AudioFormatSpec {
  encoding: 'pcmS16Le' | 'pcmF32Le';
  sampleRate: number;
  channels?: number;
}

/** A streamed transcription event. Mirrors Swift `TranscriptionEvent`. */
export type TranscriptionEvent =
  | { type: 'started' }
  | { type: 'partial'; text: string }
  | { type: 'final'; transcription: Transcription }
  | { type: 'endpoint' }
  | { type: 'error'; message: string };

/** The service's current speech-recognition state. */
export interface SttState {
  isReady: boolean;
  modelId: string;
  supportsStreaming: boolean;
  languages: string[];
}

/** A live push-to-transcribe session. Feed frames, read events, then finish/close. */
export interface SttStream {
  readonly events: AsyncIterableIterator<TranscriptionEvent>;
  /** Feed one chunk of audio (PCM matching the opened format). */
  pushFrame(frame: AudioInput): void;
  /** Ask for a final result on the audio so far. */
  flush(): Promise<void>;
  /** Signal end of input and flush the final transcript. */
  finish(): Promise<void>;
  /** Tear the session down without waiting for a final. */
  close(): Promise<void>;
}

export interface SttNamespace {
  /** Transcribe an audio buffer or file. */
  transcribe(audio: AudioInput, options?: SttOptions): Promise<Transcription>;
  /** Open a live push-stream session for incremental transcription. */
  openStream(format: AudioFormatSpec, options?: SttOptions): Promise<SttStream>;
  /** The service's current speech-recognition state. */
  state(): Promise<SttState>;
}

function toSttOptions(o: SttOptions = {}): Partial<STTOptions> {
  const out: Partial<STTOptions> = {
    enablePunctuation: o.punctuation ?? true,
    enableWordTimestamps: o.wordTimestamps ?? true,
    enableDiarization: o.diarization ?? false,
    translateToEnglish: o.translateToEnglish ?? false,
  };
  if (o.language !== undefined) out.language = o.language;
  if (o.maxSpeakers !== undefined) out.maxSpeakers = o.maxSpeakers;
  return out;
}

function toTranscription(out: STTOutput): Transcription {
  return {
    text: out.text,
    language: out.language ?? '',
    confidence: out.confidence,
    durationMs: out.durationMs ?? 0,
  };
}

function encodingOf(format: AudioFormatSpec): AudioEncoding {
  return format.encoding === 'pcmF32Le'
    ? AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
    : AudioEncoding.AUDIO_ENCODING_PCM_S16_LE;
}

function mapStreamEvent(ev: STTStreamEvent): TranscriptionEvent {
  switch (ev.kind) {
    case STTStreamEventKind.STT_STREAM_EVENT_KIND_STARTED:
      return { type: 'started' };
    case STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL:
      return { type: 'partial', text: ev.partial?.text ?? '' };
    case STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL:
      return {
        type: 'final',
        transcription: ev.finalOutput
          ? toTranscription(ev.finalOutput)
          : { text: ev.partial?.text ?? '', language: '', confidence: 0, durationMs: 0 },
      };
    case STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT:
      return { type: 'endpoint' };
    default:
      return { type: 'error', message: ev.error?.message ?? 'stt stream error' };
  }
}

export function createSttNamespace(backend: RaBackend, resolve: ModelResolver): SttNamespace {
  return {
    async transcribe(audio, options) {
      if (options?.model) await resolve(options.model);
      const req = STTTranscriptionRequest.fromPartial({
        audio: audioToSource(to16kPcm16(audio)),
        options: toSttOptions(options),
      });
      const out = STTOutput.decode(await backend.sttTranscribe(STTTranscriptionRequest.encode(req).finish()));
      return toTranscription(out);
    },

    async openStream(format, options) {
      if (options?.model) await resolve(options.model);
      const startReq = STTTranscriptionRequest.encode(
        STTTranscriptionRequest.fromPartial({
          audio: {
            encoding: encodingOf(format),
            sampleRate: format.sampleRate,
            channels: format.channels ?? 1,
          },
          options: toSttOptions(options),
        })
      ).finish();
      const session = await backend.sttStreamStart(startReq);
      const events = bridgeStream<TranscriptionEvent>((sink) =>
        backend.sttStreamEvents(session, (bytes) => sink.push(mapStreamEvent(STTStreamEvent.decode(bytes))))
      );
      return {
        events,
        pushFrame(frame) {
          const raw = audioToSource(frame);
          if (raw.audioData) void backend.sttStreamFeed(session, raw.audioData);
        },
        async flush() {
          await backend.sttStreamStop(session);
        },
        async finish() {
          await backend.sttStreamStop(session);
        },
        async close() {
          await backend.sttStreamCancel(session);
        },
      };
    },

    async state() {
      const s = STTServiceState.decode(await backend.sttState());
      return {
        isReady: s.isReady,
        modelId: s.currentModel ?? '',
        supportsStreaming: s.supportsStreaming,
        languages: s.supportedLanguageCodes ?? [],
      };
    },
  };
}
