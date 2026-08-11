// speech-abi.ts — typed access to the commons STT, TTS, and VAD proto ABIs.
//
// Three features in one file because they share a shape: none of them takes a
// handle, each reads whatever `rac_model_lifecycle_load_proto` made resident
// for its component, and each speaks one request message and one result or
// event stream. That is also why the options each carry fields the component
// ABI had no room for — word timestamps, diarization hints, the VAD hangover
// dials — which is the point of the migration.

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
  VADConfiguration,
  VADProcessRequest,
  VADResult,
  VADServiceState,
} from '@runanywhere/proto-ts/vad_options';
import type { RaBackend } from './backend';
import { bridgeStream } from './iter';
import { invokeProto } from './proto-abi';
import type { SttOptions, TtsOptions, VadOptions } from './options';
import { newRequestId } from './types';

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
// vad
// ---------------------------------------------------------------------------

/**
 * One frame plus the turn-taking policy for it.
 *
 * `minSpeechMs`, `minSilenceMs`, and `prefixPaddingMs` are declared by the
 * public options type and were dropped on the way to the component ABI, which
 * had only a threshold. Commons owns the debounce, the hangover, and the
 * pre-roll, so they travel on every frame now.
 */
export function toVadRequest(
  samples: Float32Array,
  options: VadOptions,
  frameOffsetMs = 0
): VADProcessRequest {
  return VADProcessRequest.fromPartial({
    audio: {
      audioData: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
      encoding: AudioEncoding.AUDIO_ENCODING_PCM_F32_LE,
      sampleRate: SPEECH_SAMPLE_RATE,
      channels: 1,
      frameOffsetMs,
    },
    options: {
      activationThreshold: options.activationThreshold,
      minSpeechDurationMs: options.minSpeechMs ?? 0,
      minSilenceDurationMs: options.minSilenceMs ?? 0,
      prefixPaddingMs: options.prefixPaddingMs ?? 0,
      sampleRate: SPEECH_SAMPLE_RATE,
    },
  });
}

/**
 * The detector's own configuration, which is a different message from the
 * per-frame request: `rac_vad_configure_lifecycle_proto` parses a
 * `VADConfiguration`, while `rac_vad_process_lifecycle_proto` parses a
 * `VADProcessRequest`.
 */
export function toVadConfiguration(options: VadOptions): VADConfiguration {
  return VADConfiguration.fromPartial({
    modelId: '',
    sampleRate: SPEECH_SAMPLE_RATE,
    frameLengthMs: VAD_FRAME_MS,
    // Left at 0 when the caller named no threshold, so configure and process
    // both land on commons' default. Sending the proto's documented 0.5 here
    // would arm the built-in energy detector at an RMS bar of 0.5 while every
    // process call used the default, and commons rebuilds the detector when
    // the threshold changes, so its debounce state would reset every frame and
    // speech would never be reported.
    activationThreshold: options.activationThreshold ?? 0,
    enableAutoCalibration: false,
    calibrationMultiplier: 1,
  });
}

/** The frame size every VAD path in this SDK feeds the detector. */
export const VAD_FRAME_MS = 30;

/** The commons VAD layer, bound to one backend. */
export class VadAbi {
  constructor(private readonly backend: RaBackend) {}

  async configure(config: VADConfiguration): Promise<VADServiceState> {
    return VADServiceState.decode(
      await this.backend.vadConfigureProto(VADConfiguration.encode(config).finish())
    );
  }

  async process(request: VADProcessRequest): Promise<VADResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.vadProcessProto(bytes),
        VADProcessRequest,
        request,
        VADResult
      )
    );
  }

  async start(): Promise<VADServiceState> {
    return VADServiceState.decode(await this.backend.vadStartProto());
  }

  async stop(): Promise<VADServiceState> {
    return VADServiceState.decode(await this.backend.vadStopProto());
  }

  async reset(): Promise<VADServiceState> {
    return VADServiceState.decode(await this.backend.vadResetProto());
  }
}

export { STTStreamEventKind, TTSStreamEventKind };
export type { STTOutput, STTStreamEvent, TTSOutput, TTSStreamEvent, VADResult };
