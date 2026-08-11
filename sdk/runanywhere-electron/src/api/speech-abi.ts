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
import { audioFormatToProto, optionDefaults } from './options';
import type { SttOptions, TtsOptions, VadOptions } from './options';
import { AudioFormat as PublicAudioFormat, newRequestId, toProtoError } from './types';
import type { Segment, VadEvent } from './types';

/**
 * The sample rate every audio path in this SDK normalizes to.
 * `idl/sdk_defaults.proto`'s `AudioCaptureDefaults.mic_sample_rate_hz`, read
 * rather than restated.
 */
export const SPEECH_SAMPLE_RATE = optionDefaults.micSampleRateHz;

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
 *
 * The unset policy across this file: a field the proto declares OPTIONAL is left
 * absent so commons applies its own `rac_default`; a field the proto declares as
 * a plain scalar cannot be left absent (proto3 would send the zero value, i.e.
 * punctuation OFF), so the IDL default is read from the generated
 * `*Defaults()` helper and sent explicitly. Nothing here states a literal.
 */
export function toSttRequest(
  pcm16: Uint8Array,
  options: SttOptions,
  requestId = newRequestId('stt')
): STTTranscriptionRequest {
  const defaults = optionDefaults.stt();
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
      ...defaults,
      language: options.language,
      enablePunctuation: options.punctuation ?? defaults.enablePunctuation,
      diarize: options.diarization ?? defaults.diarize,
      speakersExpected: options.maxSpeakers,
      enableWordTimestamps: options.wordTimestamps ?? defaults.enableWordTimestamps,
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

/**
 * One synthesis request. Every unnamed knob falls back to the IDL default
 * (`tTSOptionsDefaults()`), so `speed`, `pitch`, `volume`, `languageCode`, and
 * the "0 = the voice's native rate" sample rate all come from
 * `idl/tts_options.proto` rather than being retyped here.
 *
 * `audioFormat` is the exception: the public surface always hands the caller
 * back float32 samples (`toFloatSamples` below), so PCM is a hard requirement of
 * this path rather than a preference. `TtsOptions.format` describes what the
 * caller wants to DO with the audio, which is `tts.speak`'s business.
 */
export function toTtsRequest(
  text: string,
  options: TtsOptions,
  requestId = newRequestId('tts')
): TTSSynthesisRequest {
  const defaults = optionDefaults.tts();
  return TTSSynthesisRequest.fromPartial({
    requestId,
    text,
    options: {
      ...defaults,
      voice: options.voice ?? defaults.voice,
      languageCode: options.language ?? defaults.languageCode,
      speed: options.speed ?? defaults.speed,
      pitch: options.pitch ?? defaults.pitch,
      audioFormat: audioFormatToProto(PublicAudioFormat.PCM),
      sampleRate: options.sampleRate ?? defaults.sampleRate,
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
  const defaults = optionDefaults.vad();
  return ProtoVadOptions.encode(
    ProtoVadOptions.fromPartial({
      activationThreshold: options.activationThreshold,
      minSpeechDurationMs: options.minSpeechMs ?? defaults.minSpeechDurationMs,
      minSilenceDurationMs: options.minSilenceMs ?? defaults.minSilenceDurationMs,
      prefixPaddingMs: options.prefixPaddingMs ?? defaults.prefixPaddingMs,
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
  return {
    type: 'activity',
    isSpeech: result.isSpeech,
    probability: result.probability,
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
          ? toProtoError(SDKException.fromProto(event.error as never))
          : toProtoError(SDKException.generationFailed('vad stream error')),
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
    const config: { activationThreshold?: number; sampleRate: number } = {
      sampleRate: SPEECH_SAMPLE_RATE,
    };
    if (options.activationThreshold !== undefined) {
      config.activationThreshold = options.activationThreshold;
    }
    await this.backend.vadOpen(config);
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
          throw SDKException.fromProto(event.error);
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
