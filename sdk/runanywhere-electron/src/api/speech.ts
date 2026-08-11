// speech.ts — the `stt`, `tts`, `vad`, and `voice` namespaces.
//
// Audio capture and playback are renderer capabilities (Web Audio); the verbs that
// need a device — `tts.speak`, `tts.stop`, `VoiceSession.start` — throw a clear
// error when the surface runs in the main process, which has no audio device.

import * as fs from 'fs';

import { decodeWav, downsample, pcm16Bytes, pcm16ToFloat32 } from '../audio';
import { SDKException, asSDKException } from '../errors';
import { createModelsNamespace } from './assets';
import type { RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { AsyncQueue, bridgeStream } from './iter';
import { ModelAbi, categoryToProto } from './model-abi';
import { DataAbi, toDiarizationRequest } from './data-abi';
import {
  VoiceAgentAbi,
  missingComponents,
  toAudioFrame,
  toComposeConfig,
  toPublicVoiceEvent,
} from './voice-abi';
import {
  SPEECH_SAMPLE_RATE,
  SttAbi,
  STTStreamEventKind,
  TtsAbi,
  TTSStreamEventKind,
  VadAbi,
  toFloatSamples,
  toSttRequest,
  toTtsRequest,
  toVadConfiguration,
  toVadRequest,
} from './speech-abi';
import type { STTOutput } from './speech-abi';
import { audioFormatFromProto, optionDefaults } from './options';
import type {
  DiarizationOptions,
  LlmOptions,
  SttOptions,
  TtsOptions,
  TurnHandlingOptions,
  VadOptions,
} from './options';
import { voiceAgentDefaults } from '@runanywhere/proto-ts/defaults/pool';
import {
  AgentState,
  AudioEncoding,
  AudioFormat,
  ModelCategory,
  newRequestId,
  toProtoError,
} from './types';
import type {
  Audio,
  AudioChunk,
  AudioFormatSpec,
  AudioFrame,
  AudioInput,
  DiarizationResult,
  GenerationEvent,
  ModelRef,
  Segment,
  SpeechHandle,
  SttState,
  SttStream,
  Transcription,
  TranscriptionEvent,
  VadEvent,
  VadResult,
  VadStream,
  Voice,
  VoiceEvent,
  Word,
} from './types';

/** What the speech namespaces need from the facade. */
export interface SpeechDeps {
  backend: RaBackend;
  hub: SdkEventHub;
  requireReady(): void;
}

/** `AudioCaptureDefaults.mic_sample_rate_hz` — the one rate every path here uses. */
const STT_SAMPLE_RATE = SPEECH_SAMPLE_RATE;
// 30 ms at 16 kHz: small enough for responsive endpointing, large enough that the
// energy VAD sees a stable RMS.
const VAD_FRAME_SAMPLES = 480;

// ---------------------------------------------------------------------------
// Audio normalization
// ---------------------------------------------------------------------------

/** Little-endian float32 bytes decoded back to a Float32Array. */
function bytesToFloat32(bytes: Uint8Array): Float32Array {
  const count = Math.floor(bytes.byteLength / 4);
  const view = new DataView(bytes.buffer, bytes.byteOffset, count * 4);
  const out = new Float32Array(count);
  for (let i = 0; i < count; i++) out[i] = view.getFloat32(i * 4, true);
  return out;
}

/** PCM16 little-endian bytes decoded to float32 in [-1, 1]. */
function pcm16BytesToFloat32(bytes: Uint8Array): Float32Array {
  const pcm = new Int16Array(bytes.buffer, bytes.byteOffset, Math.floor(bytes.byteLength / 2));
  return pcm16ToFloat32(pcm);
}

/** Float32 mono samples at 16 kHz, whichever shape the caller supplied. */
function toMono16k(input: AudioInput): Float32Array {
  if (input.samples) {
    const rate = input.format.sampleRate || STT_SAMPLE_RATE;
    return rate === STT_SAMPLE_RATE ? input.samples : downsample(input.samples, rate, STT_SAMPLE_RATE);
  }
  let bytes = input.bytes;
  if (!bytes && input.path) bytes = fs.readFileSync(input.path);
  if (!bytes) {
    throw SDKException.validationFailed({
      fieldPath: 'audio',
      message: 'audio needs bytes, samples, or a path',
    });
  }
  if (input.format.encoding === AudioEncoding.CONTAINER) {
    if (input.format.container && input.format.container !== AudioFormat.WAV) {
      throw SDKException.notImplemented(
        `decoding ${input.format.container} audio (supply PCM16, float32, or WAV)`
      );
    }
    const decoded = decodeWav(bytes);
    return decoded.sampleRate === STT_SAMPLE_RATE
      ? decoded.samples
      : downsample(decoded.samples, decoded.sampleRate, STT_SAMPLE_RATE);
  }
  const samples =
    input.format.encoding === AudioEncoding.PCM_F32_LE ? bytesToFloat32(bytes) : pcm16BytesToFloat32(bytes);
  const rate = input.format.sampleRate || STT_SAMPLE_RATE;
  return rate === STT_SAMPLE_RATE ? samples : downsample(samples, rate, STT_SAMPLE_RATE);
}

/** PCM16 bytes at 16 kHz, whichever shape the caller supplied. */
function toPcm16At16k(input: AudioInput): Uint8Array {
  // PCM16 already at the target rate passes through without a float round-trip.
  if (
    input.bytes &&
    !input.samples &&
    input.format.encoding === AudioEncoding.PCM_S16_LE &&
    (input.format.sampleRate || STT_SAMPLE_RATE) === STT_SAMPLE_RATE
  ) {
    return input.bytes;
  }
  return pcm16Bytes(toMono16k(input));
}

function durationMsOf(samples: number, sampleRate = STT_SAMPLE_RATE): number {
  return sampleRate > 0 ? Math.round((samples / sampleRate) * 1000) : 0;
}

/** Float32 samples of one pushed {@link AudioFrame}, in the stream's established encoding. */
function frameToFloat32(frame: AudioFrame, format: AudioFormatSpec): Float32Array {
  return format.encoding === AudioEncoding.PCM_F32_LE
    ? bytesToFloat32(frame.samples)
    : pcm16BytesToFloat32(frame.samples);
}

/** Adapt one {@link AudioInput} chunk into an {@link AudioFrame} matching `format`. */
function frameOfAudioInput(input: AudioInput, format: AudioFormatSpec): AudioFrame {
  if (format.encoding === AudioEncoding.PCM_F32_LE) {
    const samples = input.samples ?? (input.bytes ? pcm16BytesToFloat32(input.bytes) : undefined);
    if (!samples) {
      throw SDKException.validationFailed({ fieldPath: 'audio', message: 'audio needs bytes or samples' });
    }
    return {
      samples: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
      sampleCount: samples.length,
    };
  }
  const bytes = input.bytes ?? (input.samples ? pcm16Bytes(input.samples) : undefined);
  if (!bytes) {
    throw SDKException.validationFailed({ fieldPath: 'audio', message: 'audio needs bytes or samples' });
  }
  return { samples: bytes, sampleCount: Math.floor(bytes.byteLength / 2) };
}

/** Reject a live-stream format spec that names a container encoding. */
function rejectContainerFormat(format: AudioFormatSpec, verb: string, batchVerb: string): void {
  if (format.encoding !== AudioEncoding.CONTAINER) return;
  throw SDKException.validationFailed({
    fieldPath: 'format.encoding',
    message: `${verb} needs raw PCM audio; container formats are batch-only — use ${batchVerb}.`,
  });
}

// ---------------------------------------------------------------------------
// stt
// ---------------------------------------------------------------------------

/** Speech-to-text. */
export interface SttNamespace {
  /**
   * Transcribe an utterance.
   *
   * @throws SDKException when no speech model is loaded.
   * @example
   * const t = await RunAnywhere.stt.transcribe(audio.wav(bytes), { language: 'en' });
   * console.log(t.text);
   */
  transcribe(input: AudioInput, options?: SttOptions): Promise<Transcription>;
  /**
   * Open a live transcription stream with one audio format established up front.
   *
   * @throws SDKException on preflight failure — no speech model loaded, or
   *   `format.encoding === 'CONTAINER'` (live streams take raw PCM only).
   * @example
   * const stream = await RunAnywhere.stt.openStream({ encoding: 'PCM_S16_LE', sampleRate: 16000 });
   * stream.pushFrame({ samples: pcm, sampleCount: pcm.length / 2 });
   * stream.finish();
   * for await (const event of stream.events) console.log(event);
   */
  openStream(format: AudioFormatSpec, options?: SttOptions): Promise<SttStream>;
  /**
   * Transcribe a stream of audio chunks, emitting `started`, `partial`, and
   * `transcriptFinal`/`completed`.
   *
   * @deprecated Use {@link openStream}. This forwards into an `SttStream` when
   *   every chunk shares one format; mixed formats throw.
   * @throws SDKException on preflight failure, or when chunks carry mixed formats.
   */
  transcribeStream(
    input: AsyncIterable<AudioInput>,
    options?: SttOptions
  ): AsyncIterableIterator<TranscriptionEvent>;
  /** Readiness, model id, and supported languages of the loaded speech model. */
  state(): Promise<SttState>;
}

/** Shape an `STTOutput` into the public grammar. */
function buildTranscription(native: STTOutput, durationMs: number): Transcription {
  return {
    text: native.text,
    language: native.language,
    confidence: native.confidence,
    words: native.words.map(
      (w): Word => ({
        text: w.word,
        startMs: w.startMs,
        endMs: w.endMs,
        confidence: w.confidence,
      })
    ),
    // Commons measures the audio it actually decoded; the caller's byte count
    // is the fallback for a backend that reports none.
    durationMs: native.durationMs || durationMs,
  };
}

/**
 * Live STT push stream backing `stt.openStream`.
 *
 * The addon exposes no incremental push ABI: frames are buffered as they are
 * pushed, and the native streaming pass runs once against the buffered audio
 * when `finish()` is called — the same buffer-then-run shape the deprecated
 * `transcribeStream` adapter already used. Partial/final events come from
 * that native pass; nothing here fabricates a successful `completed`.
 *
 * The grammar's terminal rule holds either way: exactly one
 * `completed`/`failed`/`cancelled` closes the queue, and which one it is says
 * whether the transcript is trustworthy. `close()` before `finish()` is a
 * `cancelled` — the caller walked away with audio still unprocessed — while a
 * failure inside the native pass is a `failed` carrying the proto error.
 */
function createSttStream(deps: SpeechDeps, format: AudioFormatSpec, options: SttOptions = {}): SttStream {
  const stt = new SttAbi(deps.backend);
  const requestId = newRequestId('stt');
  const queue = new AsyncQueue<TranscriptionEvent>();
  // The public handle carries the queue's bridge-safe view, not the queue: a
  // class instance loses `[Symbol.asyncIterator]` (a prototype member) crossing
  // `contextBridge`, and a renderer could not `for await` over it.
  const events = queue.stream();
  const chunks: Float32Array[] = [];
  let announced = false;
  let finished = false;
  let closed = false;
  let terminal = false;
  let sequence = 0;

  function announce(): void {
    if (announced) return;
    announced = true;
    queue.push({ type: 'started', requestId });
  }

  function next(): number {
    sequence += 1;
    return sequence;
  }

  /** Close the queue on exactly one terminal event. Later calls are no-ops. */
  function end(event: TranscriptionEvent): void {
    if (terminal) return;
    terminal = true;
    queue.push(event);
    queue.complete();
  }

  function frameToMono(frame: AudioFrame): Float32Array {
    const floats = frameToFloat32(frame, format);
    const rate = format.sampleRate || STT_SAMPLE_RATE;
    return rate === STT_SAMPLE_RATE ? floats : downsample(floats, rate, STT_SAMPLE_RATE);
  }

  async function runNativePass(): Promise<void> {
    try {
      let total = 0;
      for (const c of chunks) total += c.length;
      if (!total) {
        end({ type: 'completed', requestId });
        return;
      }
      const merged = new Float32Array(total);
      let offset = 0;
      for (const c of chunks) {
        merged.set(c, offset);
        offset += c.length;
      }
      const pcm = pcm16Bytes(merged);
      // One native pass now, not two. The STTStreamEvent envelope carries the
      // partials AND the final STTOutput with its word timings, so the second
      // non-streaming pass the component ABI needed is gone.
      let lastPartial = '';
      let sawFinal = false;
      let speaking = false;
      for await (const event of stt.transcribeStream(toSttRequest(pcm, options, requestId))) {
        if (closed) return;
        if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL) {
          const text = event.partial?.text ?? '';
          if (!text || text === lastPartial) continue;
          // The first text commons recognized is the moment it heard speech.
          // There is no separate VAD arm on `STTStreamEvent` to read — its
          // kinds are STARTED/PARTIAL/FINAL/ENDPOINT/ERROR — so the honest
          // signal is the one the recognizer itself produced.
          if (!speaking) {
            speaking = true;
            queue.push({ type: 'speechStarted', requestId, sequence: next() });
          }
          lastPartial = text;
          queue.push({
            type: 'partial',
            requestId,
            sequence: next(),
            segmentId: '0',
            revision: sequence,
            alternatives: [text],
          });
        } else if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT) {
          // Commons closes an utterance on trailing silence and marks the
          // boundary with ENDPOINT; that boundary IS the end of speech.
          if (speaking) {
            speaking = false;
            queue.push({ type: 'speechEnded', requestId, sequence: next() });
          }
        } else if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL) {
          if (!event.finalOutput) continue;
          sawFinal = true;
          if (speaking) {
            speaking = false;
            queue.push({ type: 'speechEnded', requestId, sequence: next() });
          }
          queue.push({
            type: 'transcriptFinal',
            requestId,
            sequence: next(),
            transcription: buildTranscription(event.finalOutput, durationMsOf(merged.length)),
          });
        } else if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR) {
          if (event.error) throw SDKException.fromProto(event.error);
        }
      }
      if (closed) return;
      // A backend that streams partials but never a FINAL still owes the caller
      // a transcript; one non-streaming pass supplies it rather than the stream
      // ending on a partial.
      if (!sawFinal) {
        if (speaking) queue.push({ type: 'speechEnded', requestId, sequence: next() });
        queue.push({
          type: 'transcriptFinal',
          requestId,
          sequence: next(),
          transcription: buildTranscription(
            await stt.transcribe(toSttRequest(pcm, options, requestId)),
            durationMsOf(merged.length)
          ),
        });
      }
      end({ type: 'completed', requestId });
    } catch (e) {
      end({ type: 'failed', requestId, error: toProtoError(e) });
    }
  }

  return {
    events,
    pushFrame(frame) {
      if (closed || finished) return;
      announce();
      chunks.push(frameToMono(frame));
    },
    flush() {
      // No incremental partial buffer on Electron: nothing buffered client-side to flush early.
    },
    finish() {
      if (finished || closed) return;
      finished = true;
      announce();
      void runNativePass();
    },
    async close() {
      if (closed) return;
      closed = true;
      // Closing without `finish()` abandons buffered audio that was never
      // transcribed, which is a cancellation and not a completion. Closing after
      // `finish()` leaves whichever terminal the native pass reported.
      end({ type: 'cancelled', requestId });
    },
  };
}

function parseLanguages(json?: string): string[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    return Array.isArray(parsed) ? parsed.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

/**
 * Readiness for a category commons holds in its lifecycle store. There is no
 * slot to look in any more: the component's own state ABI is the answer, and it
 * succeeds with is_ready=false rather than failing when nothing is loaded.
 */
async function requireLifecycle(deps: SpeechDeps, category: ModelCategory): Promise<void> {
  const ready =
    category === ModelCategory.SPEECH_TO_TEXT
      ? (await new SttAbi(deps.backend).state()).isReady
      : (await new TtsAbi(deps.backend).state()).isReady;
  if (!ready) {
    throw SDKException.invalidState(
      `no ${category === ModelCategory.SPEECH_TO_TEXT ? 'stt' : 'tts'} model is loaded — call models.load() first`
    );
  }
}

/** Build the `stt` namespace over a backend. */
export function createSttNamespace(deps: SpeechDeps): SttNamespace {
  const stt = new SttAbi(deps.backend);

  async function transcribe(input: AudioInput, options: SttOptions = {}): Promise<Transcription> {
    deps.requireReady();
    if (options.translateToEnglish) {
      // rac_stt_options_t has no translate flag; refusing beats silently ignoring it.
      throw SDKException.notImplemented(
        'stt translateToEnglish (commons rac_stt_options_t exposes no translate field)'
      );
    }
    await requireLifecycle(deps, ModelCategory.SPEECH_TO_TEXT);
    const pcm = toPcm16At16k(input);
    return buildTranscription(
      await stt.transcribe(toSttRequest(pcm, options)),
      durationMsOf(pcm.byteLength / 2)
    );
  }

  async function openStream(format: AudioFormatSpec, options: SttOptions = {}): Promise<SttStream> {
    deps.requireReady();
    rejectContainerFormat(format, 'stt.openStream', 'stt.transcribe');
    await requireLifecycle(deps, ModelCategory.SPEECH_TO_TEXT);
    return createSttStream(deps, format, options);
  }

  function transcribeStream(
    input: AsyncIterable<AudioInput>,
    options: SttOptions = {}
  ): AsyncIterableIterator<TranscriptionEvent> {
    deps.requireReady();
    return bridgeStream<TranscriptionEvent>(async (sink) => {
      let stream: SttStream | null = null;
      let format: AudioFormatSpec | null = null;
      for await (const chunk of input) {
        if (!format) {
          format = chunk.format;
          rejectContainerFormat(format, 'stt.transcribeStream', 'stt.transcribe');
          stream = await openStream(format, options);
        } else if (
          chunk.format.encoding !== format.encoding ||
          chunk.format.sampleRate !== format.sampleRate ||
          (chunk.format.channels ?? 1) !== (format.channels ?? 1)
        ) {
          throw SDKException.validationFailed({
            fieldPath: 'audio',
            message: 'stt.transcribeStream requires every chunk to share one audio format.',
          });
        }
        stream!.pushFrame(frameOfAudioInput(chunk, format));
      }
      if (!stream) return;
      stream.finish();
      for await (const event of stream.events) sink.push(event);
    });
  }

  async function state(): Promise<SttState> {
    const native = await stt.state();
    return {
      isReady: native.isReady,
      modelId: native.currentModel,
      supportsStreaming: native.supportsStreaming,
      languages: native.supportedLanguageCodes,
    };
  }

  return { transcribe, openStream, transcribeStream, state };
}

// ---------------------------------------------------------------------------
// Playback (renderer only)
// ---------------------------------------------------------------------------

type AudioCtor = new () => AudioContext;

function audioContextCtor(): AudioCtor {
  const g = globalThis as unknown as {
    AudioContext?: AudioCtor;
    webkitAudioContext?: AudioCtor;
  };
  const Ctor = g.AudioContext ?? g.webkitAudioContext;
  if (!Ctor) {
    throw SDKException.notImplemented(
      'audio playback in the main process — call tts.speak() from a renderer, or use tts.synthesize()'
    );
  }
  return Ctor;
}

/** Owns one AudioContext so playback can be stopped mid-utterance. */
class Playback {
  private ctx: AudioContext | null = null;
  private source: AudioBufferSourceNode | null = null;

  play(samples: Float32Array, sampleRate: number): Promise<void> {
    const Ctor = audioContextCtor();
    const ctx = this.ctx ?? (this.ctx = new Ctor());
    // `AudioCaptureDefaults.tts_sample_rate_hz` when the synthesis result named
    // no rate of its own; createBuffer rejects 0.
    const buffer = ctx.createBuffer(
      1,
      Math.max(1, samples.length),
      sampleRate || optionDefaults.ttsSampleRateHz
    );
    buffer.getChannelData(0).set(samples);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    this.source = source;
    return new Promise<void>((resolve) => {
      source.onended = () => {
        if (this.source === source) this.source = null;
        resolve();
      };
      source.start();
    });
  }

  stop(): void {
    try {
      this.source?.stop();
    } catch {
      // Already finished; nothing to stop.
    }
    this.source = null;
  }

  close(): void {
    this.stop();
    void this.ctx?.close();
    this.ctx = null;
  }
}

// ---------------------------------------------------------------------------
// tts
// ---------------------------------------------------------------------------

/** Text-to-speech. */
export interface TtsNamespace {
  /**
   * Synthesize `text` into audio samples.
   *
   * @throws SDKException when no voice is loaded.
   * @example
   * const a = await RunAnywhere.tts.synthesize('Hello there.', { speed: 1.1 });
   * console.log(a.sampleRate, a.data.length);
   */
  synthesize(text: string, options?: TtsOptions): Promise<Audio>;
  /** Synthesize incrementally, yielding chunks as the engine produces them. */
  synthesizeStream(text: string, options?: TtsOptions): AsyncIterableIterator<AudioChunk>;
  /**
   * Synthesize and play through the device (renderer only), returning a
   * handle to interrupt or await playout.
   *
   * There is no global `tts.stop()`; callers interrupt through the handle.
   *
   * @throws SDKException never — synthesis/playback failure surfaces on `handle.error`.
   * @example
   * const speech = await RunAnywhere.tts.speak('Hello there.');
   * await speech.waitForPlayout();
   */
  speak(text: string, options?: TtsOptions): Promise<SpeechHandle>;
  /**
   * @deprecated Use the `SpeechHandle` returned by {@link speak}. Interrupts
   *   the most recently created handle when one is still active.
   */
  stop(): Promise<void>;
  /** Voices the loaded model can speak with. */
  voices(): Promise<Voice[]>;
}

/** Build the `tts` namespace over a backend. */
export function createTtsNamespace(deps: SpeechDeps): TtsNamespace {
  const tts = new TtsAbi(deps.backend);
  const playback = new Playback();
  // The most recently created `speak()` handle, for the deprecated `stop()` adapter.
  let latestHandle: SpeechHandle | null = null;

  async function synthesize(text: string, options: TtsOptions = {}): Promise<Audio> {
    deps.requireReady();
    await requireLifecycle(deps, ModelCategory.TEXT_TO_SPEECH);
    const native = await tts.synthesize(toTtsRequest(text, options));
    const samples = toFloatSamples(native);
    return {
      data: samples,
      sampleRate: native.sampleRate,
      // `TTSOutput.audioFormat` is the PROTO enum (PCM = 1), not the C ABI's
      // ordinal (PCM = 0) — decoding it with the C table reported every format
      // one member too high, so a plain PCM synthesis came back as 'WAV'.
      format: audioFormatFromProto(native.audioFormat),
      durationMs: native.durationMs || durationMsOf(samples.length, native.sampleRate),
    };
  }

  function synthesizeStream(
    text: string,
    options: TtsOptions = {}
  ): AsyncIterableIterator<AudioChunk> {
    deps.requireReady();
    return bridgeStream<AudioChunk>(
      async (sink) => {
        await requireLifecycle(deps, ModelCategory.TEXT_TO_SPEECH);
        let index = 0;
        for await (const event of tts.synthesizeStream(toTtsRequest(text, options))) {
          if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK) {
            if (event.output) {
              sink.push({ data: toFloatSamples(event.output), index: index++, isFinal: false });
            }
          } else if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR) {
            if (event.error) throw SDKException.fromProto(event.error);
          }
        }
        sink.push({ data: new Float32Array(0), index, isFinal: true });
      },
      () => tts.stop().then(() => undefined)
    );
  }

  function createSpeechHandle(text: string, options: TtsOptions): SpeechHandle {
    const id = newRequestId('speech');
    let interrupted = false;
    let error: SDKException | undefined;
    let settle!: () => void;
    const settled = new Promise<void>((resolve) => {
      settle = resolve;
    });

    const handle: SpeechHandle = {
      id,
      get interrupted() {
        return interrupted;
      },
      get error() {
        return error;
      },
      async interrupt() {
        interrupted = true;
        playback.stop();
        await tts.stop();
        await settled;
      },
      async waitForPlayout() {
        await settled;
      },
    };

    void (async () => {
      try {
        const a = await synthesize(text, options);
        await playback.play(a.data, a.sampleRate);
      } catch (e) {
        error = asSDKException(e);
      } finally {
        settle();
        if (latestHandle === handle) latestHandle = null;
      }
    })();

    return handle;
  }

  async function speak(text: string, options: TtsOptions = {}): Promise<SpeechHandle> {
    const handle = createSpeechHandle(text, options);
    latestHandle = handle;
    return handle;
  }

  async function stop(): Promise<void> {
    if (latestHandle && !latestHandle.interrupted) {
      await latestHandle.interrupt();
      return;
    }
    playback.stop();
    await tts.stop();
  }

  async function voices(): Promise<Voice[]> {
    // Commons enumerates what the loaded voice/model actually offers, so this
    // is no longer "the one voice id the handle happened to carry".
    // `TTSOptions.language_code`'s own `rac_default` is the label for a voice
    // that declares no language, rather than a literal repeated here.
    const fallbackLanguage = optionDefaults.tts().languageCode;
    const listed = await tts.voices();
    if (listed.voices.length) {
      return listed.voices.map((v) => ({
        id: v.id,
        name: v.displayName || v.id,
        language: v.languageCode || fallbackLanguage,
      }));
    }
    const state = await tts.state();
    if (!state.currentVoice) return [];
    return [
      {
        id: state.currentVoice,
        name: state.currentVoice,
        language: state.supportedLanguageCodes[0] ?? fallbackLanguage,
      },
    ];
  }

  return { synthesize, synthesizeStream, speak, stop, voices };
}

// ---------------------------------------------------------------------------
// vad
// ---------------------------------------------------------------------------

/** Voice activity detection. */
export interface VadNamespace {
  /**
   * Find the speech in an audio buffer.
   *
   * @example
   * const r = await RunAnywhere.vad.detect(audio.float32(samples, 16000));
   * console.log(r.isSpeech, r.segments);
   */
  detect(input: AudioInput, options?: VadOptions): Promise<VadResult>;
  /**
   * Open a live voice-activity stream with one audio format established up front.
   *
   * @throws SDKException on preflight failure — `format.encoding === 'CONTAINER'`
   *   (live streams take raw PCM only).
   * @example
   * const stream = await RunAnywhere.vad.openStream({ encoding: 'PCM_F32_LE', sampleRate: 16000 });
   * for await (const event of stream.events) console.log(event);
   */
  openStream(format: AudioFormatSpec, options?: VadOptions): Promise<VadStream>;
  /**
   * Run detection over a stream of chunks, emitting speech start/end as they occur.
   *
   * @deprecated Use {@link openStream}. This forwards into a `VadStream` when
   *   every chunk shares one format; mixed formats throw.
   */
  detectStream(
    input: AsyncIterable<AudioInput>,
    options?: VadOptions
  ): AsyncIterableIterator<VadEvent>;
  /**
   * Clear the detector's rolling state between unrelated recordings.
   *
   * @throws SDKException when the SDK is not initialized.
   */
  reset(): Promise<void>;
}

/**
 * Turns per-frame speech flags into debounced segments.
 *
 * `minSpeechMs` / `minSilenceMs` / `prefixPaddingMs` have no equivalent in
 * `rac_vad_config_t` (it exposes an energy threshold, sample rate, frame length,
 * and calibration only), so the debouncing lives here. It belongs in commons so
 * every SDK shares one implementation.
 *
 * The dials an unset option falls back to are `VADOptions`' own `rac_default`s —
 * 250 ms debounce, 500 ms hangover, 300 ms pre-roll — which is the turn-taking
 * policy every other SDK applies and the same numbers {@link toVadRequest} sends
 * commons on every frame.
 */
class SegmentTracker {
  private readonly minSpeechMs: number;
  private readonly minSilenceMs: number;
  private readonly prefixPaddingMs: number;
  private speaking = false;
  private candidateStartMs = -1;
  private lastSpeechMs = -1;
  private pendingSilenceMs = 0;

  constructor(options: VadOptions) {
    const defaults = optionDefaults.vad();
    this.minSpeechMs = options.minSpeechMs ?? defaults.minSpeechDurationMs;
    this.minSilenceMs = options.minSilenceMs ?? defaults.minSilenceDurationMs;
    this.prefixPaddingMs = options.prefixPaddingMs ?? defaults.prefixPaddingMs;
  }

  /** Feed one frame; returns the transitions it caused. */
  push(
    isSpeech: boolean,
    atMs: number,
    frameMs: number
  ): Array<{ started?: number } | { ended: Segment }> {
    const out: Array<{ started?: number } | { ended: Segment }> = [];
    if (isSpeech) {
      this.pendingSilenceMs = 0;
      this.lastSpeechMs = atMs + frameMs;
      if (!this.speaking) {
        if (this.candidateStartMs < 0) this.candidateStartMs = atMs;
        if (atMs + frameMs - this.candidateStartMs >= this.minSpeechMs) {
          this.speaking = true;
          out.push({ started: Math.max(0, this.candidateStartMs - this.prefixPaddingMs) });
        }
      }
      return out;
    }
    if (!this.speaking) {
      this.candidateStartMs = -1;
      return out;
    }
    this.pendingSilenceMs += frameMs;
    if (this.pendingSilenceMs >= this.minSilenceMs) {
      const segment: Segment = {
        startMs: Math.max(0, this.candidateStartMs - this.prefixPaddingMs),
        endMs: this.lastSpeechMs,
      };
      this.speaking = false;
      this.candidateStartMs = -1;
      this.pendingSilenceMs = 0;
      out.push({ ended: segment });
    }
    return out;
  }

  /** Close an open segment when the audio ends mid-speech. */
  finish(): Segment | null {
    if (!this.speaking) return null;
    const segment: Segment = {
      startMs: Math.max(0, this.candidateStartMs - this.prefixPaddingMs),
      endMs: this.lastSpeechMs,
    };
    this.speaking = false;
    return segment;
  }
}

function* frames(samples: Float32Array, size: number): Generator<Float32Array> {
  for (let i = 0; i < samples.length; i += size) {
    yield samples.subarray(i, Math.min(samples.length, i + size));
  }
}

/**
 * Live VAD push stream backing `vad.openStream`.
 *
 * Pushed frames are converted to mono float32 at 16 kHz and buffered until
 * there is enough audio for one fixed-size `VAD_FRAME_SAMPLES` window — the
 * same rebinning `vad.detect`/`detectStream` already do — then run through
 * the persistent native detector in push order.
 */
function createVadStream(deps: SpeechDeps, format: AudioFormatSpec, options: VadOptions = {}): VadStream {
  const vad = new VadAbi(deps.backend);
  const queue = new AsyncQueue<VadEvent>();
  // See `createSttStream`: the handle publishes the queue's bridge-safe view so
  // a renderer can iterate it, which is what the app's old polling loop existed
  // to work around.
  const events = queue.stream();
  const tracker = new SegmentTracker(options);
  const rate = format.sampleRate || STT_SAMPLE_RATE;
  let pending = new Float32Array(0);
  let atMs = 0;
  let closed = false;
  // Frames must reach the native detector in push order; each push chains onto
  // this promise rather than racing a concurrent vadProcess call.
  let chain = Promise.resolve();

  function append(samples: Float32Array): void {
    const merged = new Float32Array(pending.length + samples.length);
    merged.set(pending, 0);
    merged.set(samples, pending.length);
    pending = merged;
  }

  async function drain(): Promise<void> {
    while (!closed && pending.length >= VAD_FRAME_SAMPLES) {
      const frame = pending.slice(0, VAD_FRAME_SAMPLES);
      pending = pending.slice(VAD_FRAME_SAMPLES);
      const frameMs = durationMsOf(VAD_FRAME_SAMPLES);
      const result = await vad.process(toVadRequest(frame, options, atMs));
      if (closed) return;
      for (const t of tracker.push(result.isSpeech, atMs, frameMs)) {
        if ('ended' in t) queue.push({ type: 'speechEnded', timestampMs: t.ended.endMs });
        else if (t.started !== undefined) queue.push({ type: 'speechStarted', timestampMs: t.started });
      }
      // The detector's own score, not a boolean widened to 0/1.
      queue.push({
        type: 'activity',
        isSpeech: result.isSpeech,
        probability: result.probability,
        timestampMs: atMs,
      });
      atMs += frameMs;
    }
  }

  function chainNext(step: () => Promise<void>): void {
    chain = chain.then(step).catch((e) => {
      if (!closed) queue.push({ type: 'failed', error: toProtoError(e) });
    });
  }

  return {
    events,
    pushFrame(frame) {
      if (closed) return;
      let floats = frameToFloat32(frame, format);
      if (rate !== STT_SAMPLE_RATE) floats = downsample(floats, rate, STT_SAMPLE_RATE);
      append(floats);
      chainNext(drain);
    },
    flush() {
      // No partial-result buffer beyond frame alignment: nothing to flush early.
    },
    finish() {
      chainNext(async () => {
        if (closed) return;
        const open = tracker.finish();
        if (open) queue.push({ type: 'speechEnded', timestampMs: open.endMs });
        queue.push({ type: 'completed' });
        queue.complete();
      });
    },
    async close() {
      if (closed) return;
      closed = true;
      await vad.stop();
      queue.complete();
    },
  };
}

/** Build the `vad` namespace over the commons lifecycle VAD ABI. */
export function createVadNamespace(deps: SpeechDeps): VadNamespace {
  const vad = new VadAbi(deps.backend);

  // Configure carries the turn-taking dials the component ABI had no field
  // for; start arms the session they apply to. Both work with no VAD model
  // loaded, because the lifecycle path falls back to the built-in energy
  // detector the same way the component path always has.
  async function arm(options: VadOptions): Promise<void> {
    await vad.configure(toVadConfiguration(options));
    await vad.start();
  }

  async function detect(input: AudioInput, options: VadOptions = {}): Promise<VadResult> {
    deps.requireReady();
    const samples = toMono16k(input);
    await arm(options);
    const tracker = new SegmentTracker(options);
    const segments: Segment[] = [];
    let probability = 0;
    let atMs = 0;
    try {
      for (const frame of frames(samples, VAD_FRAME_SAMPLES)) {
        const frameMs = durationMsOf(frame.length);
        const result = await vad.process(toVadRequest(new Float32Array(frame), options, atMs));
        probability = Math.max(probability, result.probability);
        for (const t of tracker.push(result.isSpeech, atMs, frameMs)) {
          if ('ended' in t) segments.push(t.ended);
        }
        atMs += frameMs;
      }
      const open = tracker.finish();
      if (open) segments.push(open);
    } finally {
      await vad.stop();
    }
    return {
      isSpeech: segments.length > 0,
      // The peak frame score, which is what "was there speech in this clip"
      // asks. The old speech-frame ratio answered a different question, and
      // could only ever be a ratio because the component ABI returned a bool.
      probability,
      segments,
    };
  }

  async function openStream(format: AudioFormatSpec, options: VadOptions = {}): Promise<VadStream> {
    deps.requireReady();
    rejectContainerFormat(format, 'vad.openStream', 'vad.detect');
    await arm(options);
    return createVadStream(deps, format, options);
  }

  function detectStream(
    input: AsyncIterable<AudioInput>,
    options: VadOptions = {}
  ): AsyncIterableIterator<VadEvent> {
    deps.requireReady();
    return bridgeStream<VadEvent>(async (sink) => {
      let stream: VadStream | null = null;
      let format: AudioFormatSpec | null = null;
      for await (const chunk of input) {
        if (!format) {
          format = chunk.format;
          rejectContainerFormat(format, 'vad.detectStream', 'vad.detect');
          stream = await openStream(format, options);
        } else if (
          chunk.format.encoding !== format.encoding ||
          chunk.format.sampleRate !== format.sampleRate ||
          (chunk.format.channels ?? 1) !== (format.channels ?? 1)
        ) {
          throw SDKException.validationFailed({
            fieldPath: 'audio',
            message: 'vad.detectStream requires every chunk to share one audio format.',
          });
        }
        stream!.pushFrame(frameOfAudioInput(chunk, format));
      }
      if (!stream) return;
      stream.finish();
      for await (const event of stream.events) sink.push(event);
    });
  }

  async function reset(): Promise<void> {
    deps.requireReady();
    // Commons owns the detector's rolling state; this clears the debounce and
    // the segment history so an unrelated recording does not inherit them.
    await vad.reset();
  }

  return { detect, openStream, detectStream, reset };
}

// ---------------------------------------------------------------------------
// diarization
// ---------------------------------------------------------------------------

/** Speaker diarization. */
export interface DiarizationNamespace {
  /**
   * Split an audio buffer into per-speaker turns.
   *
   * @throws SDKException when no diarization model is loaded.
   * @example
   * const d = await RunAnywhere.diarization.diarize(audio.wav(bytes));
   * console.log(d.speakerCount, d.segments.length);
   */
  diarize(input: AudioInput, options?: DiarizationOptions): Promise<DiarizationResult>;
}

/** Build the `diarization` namespace over a backend. */
export function createDiarizationNamespace(deps: SpeechDeps): DiarizationNamespace {
  const data = new DataAbi(deps.backend);
  return {
    async diarize(input, options = {}) {
      deps.requireReady();
      // Commons resolves the resident diarization model; 16 kHz is the only
      // rate it accepts and it does not resample, which is why the input is
      // brought to that rate here first.
      const native = await data.diarize(
        toDiarizationRequest(toMono16k(input), options, STT_SAMPLE_RATE)
      );
      return {
        segments: native.segments.map((s) => ({
          speakerId: s.speakerId,
          startMs: s.startMs,
          endMs: s.endMs,
        })),
        speakerCount: native.speakerCount,
      };
    },
  };
}

// ---------------------------------------------------------------------------
// voice
// ---------------------------------------------------------------------------
//
// The turn loop is commons' now. It frames the audio this file captures, decides
// where the utterance ends, and runs VAD -> STT -> LLM -> TTS over it while
// walking the eight `rac_audio_pipeline_state_t` states, including the 800 ms
// cooldown that stops the microphone re-hearing the reply. What is left here is
// the microphone and the speaker.

/** Arguments for {@link VoiceNamespace.createSession}. */
export interface VoiceSessionConfig {
  stt: ModelRef;
  llm: ModelRef;
  tts: ModelRef;
  vad?: VadOptions;
  turnHandling?: TurnHandlingOptions;
  generation?: LlmOptions;
  downloadIfNeeded?: boolean;
}

/** A live voice conversation. */
export interface VoiceSession {
  /** Conversation events; subscribing never opens the microphone. */
  readonly events: AsyncIterableIterator<VoiceEvent>;
  /** Open the microphone and begin the turn loop (renderer only). */
  start(): Promise<void>;
  /** Speak `text` now, outside the turn loop, returning a handle to it. */
  say(text: string): Promise<SpeechHandle>;
  /**
   * Stop the agent mid-utterance. Awaitable: resolves once the interrupted
   * `say()`/turn-loop response and its playout have settled.
   */
  interrupt(): Promise<void>;
  /** Close the microphone and release the pipeline. */
  close(): Promise<void>;
}

/** Voice conversations composed from stt, llm, tts, and vad. */
export interface VoiceNamespace {
  /**
   * Build a voice session that owns its own model prerequisites.
   *
   * @throws SDKException when a model cannot be downloaded or loaded.
   * @example
   * const s = await RunAnywhere.voice.createSession({
   *   stt: { id: 'whisper-tiny' }, llm: { id: 'qwen2.5-0.5b' }, tts: { id: 'piper-lessac' } });
   */
  createSession(config: VoiceSessionConfig): Promise<VoiceSession>;
}

/** Per-frame microphone capture. Renderer only. */
class FrameCapture {
  private ctx: AudioContext | null = null;
  private stream: MediaStream | null = null;
  private node: ScriptProcessorNode | null = null;

  async start(onFrame: (samples: Float32Array, sampleRate: number) => void): Promise<void> {
    const nav = (globalThis as unknown as { navigator?: Navigator }).navigator;
    if (!nav?.mediaDevices?.getUserMedia) {
      throw SDKException.notImplemented(
        'microphone capture in the main process — start a voice session from a renderer'
      );
    }
    const Ctor = audioContextCtor();
    this.stream = await nav.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
    this.ctx = new Ctor();
    const source = this.ctx.createMediaStreamSource(this.stream);
    const node = this.ctx.createScriptProcessor(4096, 1, 1);
    const rate = this.ctx.sampleRate;
    node.onaudioprocess = (e) => {
      onFrame(new Float32Array(e.inputBuffer.getChannelData(0)), rate);
    };
    source.connect(node);
    node.connect(this.ctx.destination);
    this.node = node;
  }

  stop(): void {
    this.node?.disconnect();
    this.stream?.getTracks().forEach((t) => t.stop());
    void this.ctx?.close();
    this.node = null;
    this.stream = null;
    this.ctx = null;
  }
}

/** What a voice session needs from the facade. */
export interface VoiceDeps extends SpeechDeps {
  tts: TtsNamespace;
  // Accepted and no longer read. Transcription, generation, and cancellation
  // all happen inside the commons turn now, so the session only needs `tts` for
  // `say()`. The facade still passes these, so they stay declared here rather
  // than making that one call site an exception.
  stt?: SttNamespace;
  generate?: (
    prompt: string,
    options?: LlmOptions
  ) => AsyncIterableIterator<GenerationEvent>;
  llmCancel?: () => Promise<void>;
}

/** Categories a voice session needs resident at once, so no load evicts another. */
const VOICE_CATEGORIES: ModelCategory[] = [
  ModelCategory.SPEECH_TO_TEXT,
  ModelCategory.LANGUAGE,
  ModelCategory.TEXT_TO_SPEECH,
  ModelCategory.VOICE_ACTIVITY,
];

/**
 * How many captured frames may wait to be fed. The cap only matters while a
 * turn is running, and those frames are the device hearing its own reply, so
 * the oldest are the ones to drop.
 */
const VOICE_FRAME_BACKLOG = 64;

/** How long the feed loop idles when the microphone has produced nothing. */
const VOICE_IDLE_POLL_MS = 20;

const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/** Build the `voice` namespace over a backend. */
export function createVoiceNamespace(deps: VoiceDeps): VoiceNamespace {
  // The facade builds `voice` without the models namespace, and a session owns
  // its prerequisites, so it constructs one over the same deps. That is cheaper
  // than repeating what `models.load` does — resolve the artifact, point the
  // registry row at it, admit it against the machine's memory, then run the
  // lifecycle load that is the only store the voice pipeline reads from.
  const models = createModelsNamespace(deps);
  const modelAbi = new ModelAbi(deps.backend);

  /**
   * Guarantee a resident VAD before the pipeline is composed, the way Swift's
   * `ensureResidentVAD` does.
   *
   * A session used to refuse to open unless the app had already loaded one,
   * which is exactly the multi-step bootstrap an example app must not carry.
   * The model id is `VoiceAgentDefaults.default_vad_model_id` from the IDL, not
   * a literal, so all six SDKs ensure the same one.
   */
  async function ensureResidentVad(downloadIfNeeded: boolean): Promise<void> {
    const current = await modelAbi.current({
      category: categoryToProto(ModelCategory.VOICE_ACTIVITY),
      includeModelMetadata: false,
    });
    if (current.found && current.modelId) return;

    const modelId = voiceAgentDefaults.defaultVadModelId;
    if (!modelId) {
      throw SDKException.modelNotFound('the default voice-activity model');
    }
    if (!downloadIfNeeded && !(await models.get(modelId))?.downloaded) {
      throw SDKException.invalidState(
        `a voice session needs a resident voice-activity model and '${modelId}' is not ` +
          'downloaded — load one first, or leave downloadIfNeeded unset so the session fetches it'
      );
    }
    await models.load(modelId, { keepResident: VOICE_CATEGORIES });
  }

  return {
    async createSession(config: VoiceSessionConfig): Promise<VoiceSession> {
      deps.requireReady();
      if (!config?.stt?.id || !config?.llm?.id || !config?.tts?.id) {
        throw SDKException.validationFailed({
          fieldPath: 'voice.createSession',
          message: 'stt, llm, and tts model refs are all required',
        });
      }
      if (config.downloadIfNeeded !== false) {
        for (const id of [config.stt.id, config.llm.id, config.tts.id]) {
          await models.load(id, { keepResident: VOICE_CATEGORIES });
        }
      }
      // The VAD is the session's own prerequisite rather than the caller's:
      // `VoiceSessionConfig` names no VAD model, only its tuning knobs.
      await ensureResidentVad(config.downloadIfNeeded !== false);

      const session = await deps.backend.voiceOpen(new Uint8Array(0));
      const agent = new VoiceAgentAbi(deps.backend, session);
      const states = await agent
        .initialize(
          toComposeConfig({
            sttModelId: config.stt.id,
            llmModelId: config.llm.id,
            ttsVoiceId: config.tts.voice,
            vad: config.vad,
            turnHandling: config.turnHandling,
            generation: config.generation,
          })
        )
        .catch(async (e) => {
          await deps.backend.voiceClose(session).catch(() => undefined);
          throw e;
        });
      // Commons is the authority on which components it found, so readiness is
      // read back from its own snapshot rather than tracked separately here.
      const missing = missingComponents(states);
      if (missing.length) {
        await deps.backend.voiceClose(session).catch(() => undefined);
        throw SDKException.invalidState(
          `voice session is missing ${missing.join(', ')} — call models.load() first` +
            (config.downloadIfNeeded === false ? ' (downloadIfNeeded is false)' : '')
        );
      }

      const ttsOptions: TtsOptions = config.tts.voice ? { voice: config.tts.voice } : {};
      const subscribers = new Set<{ push(e: VoiceEvent): void }>();
      const emit = (event: VoiceEvent): void => {
        for (const s of [...subscribers]) s.push(event);
      };
      const emitError = (e: unknown, recoverable: boolean): void => {
        emit({ type: 'error', message: asSDKException(e).message, recoverable });
      };

      const capture = new FrameCapture();
      const playback = new Playback();
      let pending: Uint8Array[] = [];
      let running = false;
      let closed = false;
      let loop: Promise<void> | null = null;
      let lastSpeechHandle: SpeechHandle | null = null;
      // The cancellation key for the turn in flight. The feed path leaves the
      // request id empty, so commons generates the turn id and reports it on
      // every event of that turn; that is the id `cancel_turn_proto` matches.
      let currentTurnId = '';

      void (async () => {
        try {
          for await (const raw of agent.events()) {
            if (raw.turnId) currentTurnId = raw.turnId;
            const mapped = toPublicVoiceEvent(raw);
            if (mapped) emit(mapped);
          }
        } catch (e) {
          if (!closed) emitError(e, false);
        }
      })();

      const onFrame = (frame: Float32Array, rate: number): void => {
        if (!running || closed) return;
        const mono = rate === STT_SAMPLE_RATE ? frame : downsample(frame, rate, STT_SAMPLE_RATE);
        pending.push(pcm16Bytes(mono));
        if (pending.length > VOICE_FRAME_BACKLOG) {
          pending.splice(0, pending.length - VOICE_FRAME_BACKLOG);
        }
      };

      async function feedLoop(): Promise<void> {
        while (running && !closed) {
          const chunks = pending;
          pending = [];
          if (!chunks.length) {
            await delay(VOICE_IDLE_POLL_MS);
            continue;
          }
          for (const chunk of chunks) {
            if (!running || closed) return;
            let reply: Uint8Array | undefined;
            try {
              // This blocks for the whole turn when the utterance closes, and
              // comes back with the synthesized reply as self-describing WAV.
              reply = (await agent.feed(toAudioFrame(chunk))).synthesizedAudio;
            } catch (e) {
              emitError(e, true);
              continue;
            }
            if (!reply?.byteLength || closed) continue;
            try {
              const decoded = decodeWav(reply);
              await playback.play(decoded.samples, decoded.sampleRate);
            } catch (e) {
              emitError(e, true);
            }
            // Whatever the microphone picked up during the turn is the device
            // hearing itself. Commons drops its own backlog for the same reason
            // (`voice_agent_feed_abi.cpp:150`); this drops ours.
            pending = [];
          }
        }
      }

      async function interrupt(): Promise<void> {
        playback.stop();
        pending = [];
        const settling: Promise<void>[] = [];
        if (currentTurnId) {
          settling.push(agent.cancel(currentTurnId).catch(() => undefined));
        }
        if (lastSpeechHandle && !lastSpeechHandle.interrupted) {
          settling.push(lastSpeechHandle.interrupt());
        } else {
          settling.push(deps.tts.stop());
        }
        await Promise.all(settling);
      }

      return {
        get events(): AsyncIterableIterator<VoiceEvent> {
          let registered: { push(e: VoiceEvent): void } | null = null;
          return bridgeStream<VoiceEvent>(
            (sink) => {
              registered = sink;
              subscribers.add(sink);
            },
            () => {
              if (registered) subscribers.delete(registered);
            }
          );
        },
        async start(): Promise<void> {
          if (closed) throw SDKException.invalidState('voice session is closed');
          if (running) return;
          await capture.start(onFrame);
          running = true;
          // Commons reports every later state transition; the microphone being
          // open before the first frame arrives is this layer's own fact.
          emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
          loop = feedLoop();
        },
        async say(text: string): Promise<SpeechHandle> {
          if (closed) throw SDKException.invalidState('voice session is closed');
          emit({ type: 'agentStateChanged', state: AgentState.SPEAKING });
          const handle = await deps.tts.speak(text, ttsOptions);
          lastSpeechHandle = handle;
          void handle.waitForPlayout().then(() => {
            if (!closed) emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
          });
          return handle;
        },
        interrupt,
        async close(): Promise<void> {
          if (closed) return;
          closed = true;
          running = false;
          capture.stop();
          playback.close();
          // The loop may be parked inside a turn; the destroy below waits on the
          // same work, so draining here keeps the two from racing.
          await loop?.catch(() => undefined);
          await deps.tts.stop().catch(() => undefined);
          await deps.backend.voiceClose(session);
          subscribers.clear();
        },
      };
    },
  };
}

export { STT_SAMPLE_RATE, toMono16k, toPcm16At16k };
