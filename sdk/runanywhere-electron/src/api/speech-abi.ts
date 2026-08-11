// speech-abi.ts — typed access to the commons STT, TTS, and VAD proto ABIs.
//
// STT and TTS are handle-free lifecycle entry points. VAD streaming uses
// `rac_vad_stream_*` over a component handle the backend owns — commons applies
// min-speech / min-silence / prefix-padding and emits SPEECH_ACTIVITY events.

import { SDKException } from '../errors';
import { AudioEncoding, AudioFormat } from '@runanywhere/proto-ts/model_types';
import {
  STTOutput,
  STTStreamEvent,
  STTStreamEventKind,
  STTServiceState,
  STTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import {
  TTSOutput,
  TTSServiceState,
  TTSStreamEvent,
  TTSStreamEventKind,
  TTSSynthesisRequest,
  TTSVoiceList,
} from '@runanywhere/proto-ts/tts_options';
import {
  SpeechActivityKind,
  VADOptions as ProtoVadOptions,
  VADResult,
  VADStreamEvent,
  VADStreamEventKind,
} from '@runanywhere/proto-ts/vad_options';
import type { RaBackend } from './backend';
import { bridgeStream } from './iter';
import { invokeProto } from './proto-abi';
import type { SttOptions, TtsOptions, VadOptions } from './options';
import { VAD_DEFAULTS, toNativeVadConfig } from './options';
import { newRequestId } from './types';
import type { Segment, VadEvent } from './types';

/** The sample rate every audio path in this SDK normalizes to. */
export const SPEECH_SAMPLE_RATE = 16000;

function orThrow<T extends { error?: { message?: string } | undefined }>(result: T): T {
  if (result.error) throw SDKException.fromProto(result.error as never);
  return result;
}

// ---------------------------------------------------------------------------
// stt
// ---------------------------------------------------------------------------

/**
 * One transcription request over 16 kHz signed 16-bit PCM.
 *
 * `diarize` and `speakersExpected` reach commons for the first time here; the
 * component ABI had no field for either, so `SttOptions.diarization` used to be
 * declared and dropped.
 */
export function toSttRequest(
  pcm16: Uint8Array,
  options: SttOptions,
  requestId = newRequestId('stt')
): STTTranscriptionRequest {
  return STTTranscriptionRequest.fromPartial({
    requestId,
    audio: {
      audioData: pcm16,
      encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
      sampleRate: SPEECH_SAMPLE_RATE,
      channels: 1,
    },
    options: {
      language: options.language,
      enablePunctuation: options.punctuation ?? true,
      diarize: options.diarization ?? false,
      speakersExpected: options.maxSpeakers,
      enableWordTimestamps: options.wordTimestamps ?? true,
      silenceDurationMs: 0,
    },
    metadata: {},
  });
}

/** The commons STT layer, bound to one backend. */
export class SttAbi {
  constructor(private readonly backend: RaBackend) {}

  async transcribe(request: STTTranscriptionRequest): Promise<STTOutput> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.sttTranscribeProto(bytes),
        STTTranscriptionRequest,
        request,
        STTOutput
      )
    );
  }

  transcribeStream(request: STTTranscriptionRequest): AsyncIterableIterator<STTStreamEvent> {
    const bytes = STTTranscriptionRequest.encode(request).finish();
    return bridgeStream<STTStreamEvent>((sink) =>
      this.backend.sttTranscribeStreamProto(bytes, (event) => {
        sink.push(STTStreamEvent.decode(event));
      })
    );
  }

  async state(): Promise<STTServiceState> {
    return STTServiceState.decode(await this.backend.sttStateProto());
  }
}

// ---------------------------------------------------------------------------
// tts
// ---------------------------------------------------------------------------

export function toTtsRequest(
  text: string,
  options: TtsOptions,
  requestId = newRequestId('tts')
): TTSSynthesisRequest {
  return TTSSynthesisRequest.fromPartial({
    requestId,
    text,
    options: {
      voice: options.voice ?? '',
      languageCode: options.language ?? '',
      speed: options.speed ?? 1,
      pitch: options.pitch ?? 1,
      volume: 1,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
      // 0 means the voice's native rate; naming any other forces a resample.
      sampleRate: options.sampleRate ?? 0,
    },
  });
}

/** Float samples out of a PCM float32 payload, whatever its byte alignment. */
export function toFloatSamples(output: TTSOutput): Float32Array {
  const bytes = output.audioData;
  if (!bytes || bytes.byteLength < 4) return new Float32Array(0);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const samples = new Float32Array(Math.floor(bytes.byteLength / 4));
  for (let i = 0; i < samples.length; i++) samples[i] = view.getFloat32(i * 4, true);
  return samples;
}

/** The commons TTS layer, bound to one backend. */
export class TtsAbi {
  constructor(private readonly backend: RaBackend) {}

  async synthesize(request: TTSSynthesisRequest): Promise<TTSOutput> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.ttsSynthesizeProto(bytes),
        TTSSynthesisRequest,
        request,
        TTSOutput
      )
    );
  }

  synthesizeStream(request: TTSSynthesisRequest): AsyncIterableIterator<TTSStreamEvent> {
    const bytes = TTSSynthesisRequest.encode(request).finish();
    return bridgeStream<TTSStreamEvent>(
      (sink) =>
        this.backend.ttsSynthesizeStreamProto(bytes, (event) => {
          sink.push(TTSStreamEvent.decode(event));
        }),
      () => this.stop().then(() => undefined)
    );
  }

  async stop(): Promise<TTSServiceState> {
    return TTSServiceState.decode(await this.backend.ttsStopProto());
  }

  async voices(): Promise<TTSVoiceList> {
    return TTSVoiceList.decode(await this.backend.ttsListVoicesProto());
  }

  async state(): Promise<TTSServiceState> {
    return TTSServiceState.decode(await this.backend.ttsStateProto());
  }
}

// ---------------------------------------------------------------------------
// vad — rac_vad_stream_* / SPEECH_ACTIVITY (commons owns endpointing)
// ---------------------------------------------------------------------------

/** Serialize public {@link VadOptions} for `rac_vad_stream_start_proto`. */
export function toVadOptionsBytes(options: VadOptions = {}): Uint8Array {
  return ProtoVadOptions.encode(
    ProtoVadOptions.fromPartial({
      activationThreshold: options.activationThreshold,
      minSpeechDurationMs: options.minSpeechMs ?? VAD_DEFAULTS.minSpeechMs,
      minSilenceDurationMs: options.minSilenceMs ?? VAD_DEFAULTS.minSilenceMs,
      prefixPaddingMs: options.prefixPaddingMs ?? VAD_DEFAULTS.prefixPaddingMs,
      sampleRate: SPEECH_SAMPLE_RATE,
    })
  ).finish();
}

function activityToEvent(activity: NonNullable<VADStreamEvent['activity']>): VadEvent | null {
  if (activity.eventType === SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_STARTED) {
    return { type: 'speechStarted', timestampMs: activity.audioStartMs };
  }
  if (activity.eventType === SpeechActivityKind.SPEECH_ACTIVITY_KIND_SPEECH_ENDED) {
    return { type: 'speechEnded', timestampMs: activity.audioEndMs };
  }
  return null;
}

function frameToEvent(result: VADResult): VadEvent {
  const isSpeech = result.isSpeech;
  return {
    type: 'activity',
    isSpeech,
    probability: result.probability || (isSpeech ? 1 : 0),
    timestampMs: result.durationMs || 0,
  };
}

/** Decode one commons `VADStreamEvent` into zero or more public events. */
export function decodeVadStreamEvent(raw: Uint8Array): VadEvent[] {
  const event = VADStreamEvent.decode(raw);
  if (event.kind === VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY && event.activity) {
    const mapped = activityToEvent(event.activity);
    return mapped ? [mapped] : [];
  }
  if (event.kind === VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME && event.result) {
    return [frameToEvent(event.result)];
  }
  if (event.kind === VADStreamEventKind.VAD_STREAM_EVENT_KIND_ERROR) {
    return [
      {
        type: 'failed',
        error: event.error
          ? SDKException.fromProto(event.error as never)
          : SDKException.generationFailed('vad stream error'),
      },
    ];
  }
  return [];
}

/** The commons VAD stream layer, bound to one backend component handle. */
export class VadAbi {
  constructor(private readonly backend: RaBackend) {}

  /** Ensure a component handle is open (energy detector; model optional). */
  async open(options: VadOptions = {}): Promise<void> {
    await this.backend.vadOpen(
      toNativeVadConfig(options, { sampleRate: SPEECH_SAMPLE_RATE })
    );
  }

  /**
   * Feed one PCM16 buffer through a commons stream session and collect segments.
   * Endpointing (min-speech / min-silence / prefix padding) is applied by commons.
   */
  async detect(pcm16: Uint8Array, options: VadOptions = {}): Promise<{
    segments: Segment[];
    probability: number;
  }> {
    await this.open(options);
    const segments: Segment[] = [];
    let openStart: number | null = null;
    let probability = 0;

    const onEvent = (raw: Uint8Array): void => {
      for (const event of decodeVadStreamEvent(raw)) {
        if (event.type === 'speechStarted') {
          openStart = event.timestampMs ?? 0;
        } else if (event.type === 'speechEnded' && openStart != null) {
          segments.push({
            startMs: openStart,
            endMs: Math.max(event.timestampMs ?? openStart, openStart),
          });
          openStart = null;
        } else if (event.type === 'activity') {
          probability = Math.max(probability, event.probability);
        } else if (event.type === 'failed') {
          throw event.error;
        }
      }
    };

    await Promise.resolve(this.backend.vadSetStreamCallback(onEvent));
    try {
      const sessionId = await this.backend.vadStreamStart(toVadOptionsBytes(options));
      if (pcm16.byteLength > 0) await this.backend.vadStreamFeed(sessionId, pcm16);
      await this.backend.vadStreamStop(sessionId);
    } finally {
      await this.backend.vadUnsetStreamCallback();
    }
    return { segments, probability };
  }

  async reset(): Promise<void> {
    await this.backend.vadReset();
  }
}

export { STTStreamEventKind, TTSStreamEventKind, VADStreamEventKind, SpeechActivityKind };
export type { STTOutput, STTStreamEvent, TTSOutput, TTSStreamEvent, VADResult, VADStreamEvent };
