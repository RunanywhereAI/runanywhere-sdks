// speech.ts — the `stt`, `tts`, `vad`, and `voice` namespaces.
//
// Audio capture and playback are renderer capabilities (Web Audio); the verbs that
// need a device — `tts.speak`, `tts.stop`, `VoiceSession.start` — throw a clear
// error when the surface runs in the main process, which has no audio device.

import * as fs from 'fs';

import { decodeWav, downsample, pcm16Bytes, pcm16ToFloat32 } from '../audio';
import { SDKException } from '../errors';
import type { LoadSlot, RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import {
  STT_DEFAULTS,
  TTS_DEFAULTS,
  VAD_DEFAULTS,
  audioFormatFromOrdinal,
  toNativeDiarizationOptions,
  toNativeSttOptions,
  toNativeTtsOptions,
  toNativeVadConfig,
} from './options';
import type {
  DiarizationOptions,
  LlmOptions,
  SttOptions,
  TtsOptions,
  TurnHandlingOptions,
  VadOptions,
} from './options';
import { AgentState, AudioFormat, ModelCategory, TokenKind } from './types';
import type {
  Audio,
  AudioChunk,
  AudioInput,
  DiarizationResult,
  ModelRef,
  Segment,
  SttState,
  Transcription,
  TranscriptionEvent,
  VadEvent,
  VadResult,
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

const STT_SAMPLE_RATE = 16000;
// 30 ms at 16 kHz: small enough for responsive endpointing, large enough that the
// energy VAD sees a stable RMS.
const VAD_FRAME_SAMPLES = 480;

// ---------------------------------------------------------------------------
// Audio normalization
// ---------------------------------------------------------------------------

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
  if (input.format.encoding === AudioFormat.WAV) {
    const decoded = decodeWav(bytes);
    return decoded.sampleRate === STT_SAMPLE_RATE
      ? decoded.samples
      : downsample(decoded.samples, decoded.sampleRate, STT_SAMPLE_RATE);
  }
  if (input.format.encoding !== AudioFormat.PCM) {
    throw SDKException.notImplemented(
      `decoding ${input.format.encoding} audio (supply PCM16, float32, or WAV)`
    );
  }
  const pcm = new Int16Array(bytes.buffer, bytes.byteOffset, Math.floor(bytes.byteLength / 2));
  const samples = pcm16ToFloat32(pcm);
  const rate = input.format.sampleRate || STT_SAMPLE_RATE;
  return rate === STT_SAMPLE_RATE ? samples : downsample(samples, rate, STT_SAMPLE_RATE);
}

/** PCM16 bytes at 16 kHz, whichever shape the caller supplied. */
function toPcm16At16k(input: AudioInput): Uint8Array {
  // PCM16 already at the target rate passes through without a float round-trip.
  if (
    input.bytes &&
    !input.samples &&
    input.format.encoding === AudioFormat.PCM &&
    (input.format.sampleRate || STT_SAMPLE_RATE) === STT_SAMPLE_RATE
  ) {
    return input.bytes;
  }
  return pcm16Bytes(toMono16k(input));
}

function durationMsOf(samples: number, sampleRate = STT_SAMPLE_RATE): number {
  return sampleRate > 0 ? Math.round((samples / sampleRate) * 1000) : 0;
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
  /** Transcribe a stream of audio chunks, emitting partials then a final transcript. */
  transcribeStream(
    input: AsyncIterable<AudioInput>,
    options?: SttOptions
  ): AsyncIterableIterator<TranscriptionEvent>;
  /** Readiness, model id, and supported languages of the loaded speech model. */
  state(): Promise<SttState>;
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

async function requireSlot(
  deps: SpeechDeps,
  slot: LoadSlot,
  category: ModelCategory,
  requested: string | undefined
): Promise<void> {
  const current = await deps.backend.loaded(slot);
  if (requested && (!current || current.id !== requested)) {
    const loaded = await deps.backend.ensure(slot, requested);
    deps.hub.emit({ type: 'modelLoaded', id: loaded.id, category });
    return;
  }
  if (!current) {
    throw SDKException.invalidState(
      `no ${slot} model is loaded — call models.load() first`
    );
  }
}

/** Build the `stt` namespace over a backend. */
export function createSttNamespace(deps: SpeechDeps): SttNamespace {
  const buildTranscription = (
    native: Awaited<ReturnType<RaBackend['sttTranscribe']>>,
    durationMs: number
  ): Transcription => ({
    text: native.text,
    language: native.language,
    confidence: native.confidence,
    words: native.words.map(
      (w): Word => ({
        text: w.text,
        startMs: w.startMs,
        endMs: w.endMs,
        confidence: w.confidence,
      })
    ),
    durationMs,
  });

  async function transcribe(input: AudioInput, options: SttOptions = {}): Promise<Transcription> {
    deps.requireReady();
    if (options.translateToEnglish) {
      // rac_stt_options_t has no translate flag; refusing beats silently ignoring it.
      throw SDKException.notImplemented(
        'stt translateToEnglish (commons rac_stt_options_t exposes no translate field)'
      );
    }
    await requireSlot(deps, 'stt', ModelCategory.SPEECH_TO_TEXT, undefined);
    const pcm = toPcm16At16k(input);
    const native = await deps.backend.sttTranscribe(
      pcm,
      toNativeSttOptions(options, STT_SAMPLE_RATE)
    );
    return buildTranscription(native, durationMsOf(pcm.byteLength / 2));
  }

  function transcribeStream(
    input: AsyncIterable<AudioInput>,
    options: SttOptions = {}
  ): AsyncIterableIterator<TranscriptionEvent> {
    deps.requireReady();
    return bridgeStream<TranscriptionEvent>(async (sink) => {
      await requireSlot(deps, 'stt', ModelCategory.SPEECH_TO_TEXT, undefined);
      sink.push({ type: 'started' });
      // Chunks accumulate into one utterance because commons' streaming transcribe
      // takes the whole buffer; partials come from the engine as it decodes it.
      const chunks: Float32Array[] = [];
      for await (const chunk of input) chunks.push(toMono16k(chunk));
      let total = 0;
      for (const c of chunks) total += c.length;
      const merged = new Float32Array(total);
      let offset = 0;
      for (const c of chunks) {
        merged.set(c, offset);
        offset += c.length;
      }
      const pcm = pcm16Bytes(merged);
      const nativeOptions = toNativeSttOptions(options, STT_SAMPLE_RATE);
      let lastPartial = '';
      await deps.backend.sttTranscribeStream(pcm, nativeOptions, (p) => {
        if (!p.isFinal && p.text !== lastPartial) {
          lastPartial = p.text;
          sink.push({ type: 'partial', text: p.text });
        }
      });
      // The streaming callback carries text only, so the final transcript (with word
      // timings) comes from one non-streaming pass over the same buffer.
      const native = await deps.backend.sttTranscribe(pcm, nativeOptions);
      sink.push({
        type: 'final',
        transcription: buildTranscription(native, durationMsOf(merged.length)),
      });
    });
  }

  async function state(): Promise<SttState> {
    const info = await deps.backend.sttInfo();
    return {
      isReady: info.isReady,
      modelId: info.modelId,
      supportsStreaming: info.supportsStreaming,
      languages: parseLanguages(info.languagesJson),
    };
  }

  return { transcribe, transcribeStream, state };
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
    const buffer = ctx.createBuffer(1, Math.max(1, samples.length), sampleRate || 22050);
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
  /** Synthesize and play through the device (renderer only). */
  speak(text: string, options?: TtsOptions): Promise<void>;
  /** Stop playback and any in-flight synthesis. */
  stop(): Promise<void>;
  /** Voices the loaded model can speak with. */
  voices(): Promise<Voice[]>;
}

/** Build the `tts` namespace over a backend. */
export function createTtsNamespace(deps: SpeechDeps): TtsNamespace {
  const playback = new Playback();

  async function synthesize(text: string, options: TtsOptions = {}): Promise<Audio> {
    deps.requireReady();
    await requireSlot(deps, 'tts', ModelCategory.TEXT_TO_SPEECH, undefined);
    const native = await deps.backend.ttsSynthesize(text, toNativeTtsOptions(options));
    return {
      data: native.samples,
      sampleRate: native.sampleRate,
      format: audioFormatFromOrdinal(native.audioFormat),
      durationMs: native.durationMs || durationMsOf(native.samples.length, native.sampleRate),
    };
  }

  function synthesizeStream(
    text: string,
    options: TtsOptions = {}
  ): AsyncIterableIterator<AudioChunk> {
    deps.requireReady();
    return bridgeStream<AudioChunk>(
      async (sink) => {
        await requireSlot(deps, 'tts', ModelCategory.TEXT_TO_SPEECH, undefined);
        let index = 0;
        await deps.backend.ttsSynthesizeStream(text, toNativeTtsOptions(options), (chunk) => {
          sink.push({ data: chunk.samples, index: index++, isFinal: false });
        });
        sink.push({ data: new Float32Array(0), index, isFinal: true });
      },
      () => deps.backend.ttsStop()
    );
  }

  async function speak(text: string, options: TtsOptions = {}): Promise<void> {
    const a = await synthesize(text, options);
    await playback.play(a.data, a.sampleRate);
  }

  async function stop(): Promise<void> {
    playback.stop();
    await deps.backend.ttsStop();
  }

  async function voices(): Promise<Voice[]> {
    const info = await deps.backend.ttsInfo();
    if (!info.voiceId) return [];
    const languages = parseLanguages(info.languagesJson);
    return [
      {
        id: info.voiceId,
        name: info.voiceId,
        language: languages[0] ?? TTS_DEFAULTS.language,
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
  /** Run detection over a stream of chunks, emitting speech start/end as they occur. */
  detectStream(
    input: AsyncIterable<AudioInput>,
    options?: VadOptions
  ): AsyncIterableIterator<VadEvent>;
}

/**
 * Turns per-frame speech flags into debounced segments.
 *
 * `minSpeechMs` / `minSilenceMs` / `prefixPaddingMs` have no equivalent in
 * `rac_vad_config_t` (it exposes an energy threshold, sample rate, frame length,
 * and calibration only), so the debouncing lives here. It belongs in commons so
 * every SDK shares one implementation.
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
    this.minSpeechMs = options.minSpeechMs ?? VAD_DEFAULTS.minSpeechMs;
    this.minSilenceMs = options.minSilenceMs ?? VAD_DEFAULTS.minSilenceMs;
    this.prefixPaddingMs = options.prefixPaddingMs ?? VAD_DEFAULTS.prefixPaddingMs;
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

/** Build the `vad` namespace over a backend. */
export function createVadNamespace(deps: SpeechDeps): VadNamespace {
  async function detect(input: AudioInput, options: VadOptions = {}): Promise<VadResult> {
    deps.requireReady();
    const samples = toMono16k(input);
    await deps.backend.vadOpen(toNativeVadConfig(options, { sampleRate: STT_SAMPLE_RATE }));
    const tracker = new SegmentTracker(options);
    const segments: Segment[] = [];
    let speechFrames = 0;
    let totalFrames = 0;
    let atMs = 0;
    try {
      for (const frame of frames(samples, VAD_FRAME_SAMPLES)) {
        const frameMs = durationMsOf(frame.length);
        const isSpeech = await deps.backend.vadProcess(new Float32Array(frame));
        totalFrames += 1;
        if (isSpeech) speechFrames += 1;
        for (const t of tracker.push(isSpeech, atMs, frameMs)) {
          if ('ended' in t) segments.push(t.ended);
        }
        atMs += frameMs;
      }
      const open = tracker.finish();
      if (open) segments.push(open);
    } finally {
      await deps.backend.vadClose();
    }
    return {
      isSpeech: segments.length > 0,
      // The energy VAD reports a boolean per frame, so the speech-frame ratio is
      // the only probability available; a model-backed VAD would give a real score.
      probability: totalFrames ? speechFrames / totalFrames : 0,
      segments,
    };
  }

  function detectStream(
    input: AsyncIterable<AudioInput>,
    options: VadOptions = {}
  ): AsyncIterableIterator<VadEvent> {
    deps.requireReady();
    return bridgeStream<VadEvent>(
      async (sink) => {
        await deps.backend.vadOpen(toNativeVadConfig(options, { sampleRate: STT_SAMPLE_RATE }));
        const tracker = new SegmentTracker(options);
        let atMs = 0;
        try {
          for await (const chunk of input) {
            for (const frame of frames(toMono16k(chunk), VAD_FRAME_SAMPLES)) {
              const frameMs = durationMsOf(frame.length);
              const isSpeech = await deps.backend.vadProcess(new Float32Array(frame));
              sink.push({ type: 'frame', isSpeech, probability: isSpeech ? 1 : 0, atMs });
              for (const t of tracker.push(isSpeech, atMs, frameMs)) {
                if ('ended' in t) sink.push({ type: 'speechEnded', atMs, segment: t.ended });
                else if (t.started !== undefined) {
                  sink.push({ type: 'speechStarted', atMs: t.started });
                }
              }
              atMs += frameMs;
            }
          }
          const open = tracker.finish();
          if (open) sink.push({ type: 'speechEnded', atMs, segment: open });
        } finally {
          await deps.backend.vadClose();
        }
      },
      () => deps.backend.vadClose()
    );
  }

  return { detect, detectStream };
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
  return {
    async diarize(input, options = {}) {
      deps.requireReady();
      await requireSlot(deps, 'diarization', ModelCategory.DIARIZATION, undefined);
      const native = await deps.backend.diarize(
        toMono16k(input),
        toNativeDiarizationOptions(options, STT_SAMPLE_RATE)
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
  /** Speak `text` now, outside the turn loop. */
  say(text: string): Promise<void>;
  /** Stop the agent mid-utterance. */
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
  stt: SttNamespace;
  tts: TtsNamespace;
  generate(prompt: string, options?: LlmOptions): AsyncIterableIterator<
    { type: 'token'; text: string; kind: typeof TokenKind.TEXT | typeof TokenKind.THOUGHT } | { type: string }
  >;
  llmCancel(): Promise<void>;
}

/** Build the `voice` namespace over a backend. */
export function createVoiceNamespace(deps: VoiceDeps): VoiceNamespace {
  return {
    async createSession(config: VoiceSessionConfig): Promise<VoiceSession> {
      deps.requireReady();
      if (!config?.stt?.id || !config?.llm?.id || !config?.tts?.id) {
        throw SDKException.validationFailed({
          fieldPath: 'voice.createSession',
          message: 'stt, llm, and tts model refs are all required',
        });
      }
      if (config.downloadIfNeeded === false) {
        for (const [slot, ref] of [
          ['stt', config.stt],
          ['llm', config.llm],
          ['tts', config.tts],
        ] as Array<[LoadSlot, ModelRef]>) {
          const current = await deps.backend.loaded(slot);
          if (!current || current.id !== ref.id) {
            throw SDKException.invalidState(
              `downloadIfNeeded is false but ${ref.id} is not loaded in the ${slot} slot`
            );
          }
        }
      } else {
        // The session owns its prerequisites: load every model before wiring up.
        for (const [slot, ref, category] of [
          ['stt', config.stt, ModelCategory.SPEECH_TO_TEXT],
          ['llm', config.llm, ModelCategory.LANGUAGE],
          ['tts', config.tts, ModelCategory.TEXT_TO_SPEECH],
        ] as Array<[LoadSlot, ModelRef, ModelCategory]>) {
          const loaded = await deps.backend.ensure(slot, ref.id);
          deps.hub.emit({ type: 'modelLoaded', id: loaded.id, category });
        }
      }

      const vadOptions = config.vad ?? {};
      const turn = config.turnHandling ?? {};
      const minSilenceMs = Math.max(
        vadOptions.minSilenceMs ?? VAD_DEFAULTS.minSilenceMs,
        turn.endpointing?.minDelayMs ?? 500
      );
      const maxUtteranceMs = turn.endpointing?.maxDelayMs ?? 3000;
      const interruptEnabled = turn.interruption?.enabled ?? true;

      const subscribers = new Set<{ push(e: VoiceEvent): void }>();
      const emit = (event: VoiceEvent): void => {
        for (const s of [...subscribers]) s.push(event);
      };

      const capture = new FrameCapture();
      let closed = false;
      let running = false;
      let speaking = false;
      let utterance: Float32Array[] = [];
      let silenceMs = 0;
      let speechMs = 0;
      let turnInFlight = false;

      const runTurn = async (samples: Float32Array): Promise<void> => {
        turnInFlight = true;
        try {
          emit({ type: 'agentStateChanged', state: AgentState.THINKING });
          const transcription = await deps.stt.transcribe({
            samples,
            format: { encoding: AudioFormat.PCM, sampleRate: STT_SAMPLE_RATE, channels: 1 },
          });
          const heard = transcription.text.trim();
          emit({ type: 'userTranscribed', text: heard, isFinal: true });
          if (!heard) {
            emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
            return;
          }
          let reply = '';
          for await (const event of deps.generate(heard, config.generation)) {
            if (event.type === 'token') {
              const token = event as { text: string; kind: string };
              if (token.kind === TokenKind.TEXT) reply += token.text;
            }
          }
          reply = reply.trim();
          emit({ type: 'agentResponse', text: reply });
          if (reply) {
            emit({ type: 'agentStateChanged', state: AgentState.SPEAKING });
            await deps.tts.speak(reply, config.tts.voice ? { voice: config.tts.voice } : {});
          }
          emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
        } catch (e) {
          emit({
            type: 'error',
            message: e instanceof Error ? e.message : String(e),
            recoverable: true,
          });
          emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
        } finally {
          turnInFlight = false;
        }
      };

      const onFrame = (frame: Float32Array, rate: number): void => {
        if (!running || closed) return;
        const mono = rate === STT_SAMPLE_RATE ? frame : downsample(frame, rate, STT_SAMPLE_RATE);
        const frameMs = durationMsOf(mono.length);
        void deps.backend
          .vadProcess(new Float32Array(mono))
          .then((isSpeech) => {
            if (!running || closed) return;
            if (isSpeech) {
              if (!speaking) {
                speaking = true;
                speechMs = 0;
                utterance = [];
                emit({ type: 'speechStarted' });
                // A barge-in cuts the agent off so the user is heard immediately.
                if (interruptEnabled && turnInFlight) void interrupt();
              }
              silenceMs = 0;
              speechMs += frameMs;
              utterance.push(mono);
              if (speechMs >= maxUtteranceMs) endUtterance();
              return;
            }
            if (!speaking) return;
            utterance.push(mono);
            silenceMs += frameMs;
            if (silenceMs >= minSilenceMs) endUtterance();
          })
          .catch((e) => {
            emit({
              type: 'error',
              message: e instanceof Error ? e.message : String(e),
              recoverable: true,
            });
          });
      };

      const endUtterance = (): void => {
        speaking = false;
        emit({ type: 'speechEnded' });
        let total = 0;
        for (const c of utterance) total += c.length;
        const merged = new Float32Array(total);
        let offset = 0;
        for (const c of utterance) {
          merged.set(c, offset);
          offset += c.length;
        }
        utterance = [];
        silenceMs = 0;
        speechMs = 0;
        if (total) void runTurn(merged);
      };

      async function interrupt(): Promise<void> {
        await deps.tts.stop();
        await deps.llmCancel();
      }

      const session: VoiceSession = {
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
          await deps.backend.vadOpen(
            toNativeVadConfig(vadOptions, { sampleRate: STT_SAMPLE_RATE })
          );
          await capture.start(onFrame);
          running = true;
          emit({ type: 'agentStateChanged', state: AgentState.LISTENING });
        },
        async say(text: string): Promise<void> {
          if (closed) throw SDKException.invalidState('voice session is closed');
          emit({ type: 'agentStateChanged', state: AgentState.SPEAKING });
          await deps.tts.speak(text, config.tts.voice ? { voice: config.tts.voice } : {});
          emit({ type: 'agentStateChanged', state: running ? AgentState.LISTENING : AgentState.THINKING });
        },
        interrupt,
        async close(): Promise<void> {
          if (closed) return;
          closed = true;
          running = false;
          capture.stop();
          await deps.tts.stop();
          await deps.backend.vadClose();
          subscribers.clear();
        },
      };
      return session;
    },
  };
}

export { STT_SAMPLE_RATE, toMono16k, toPcm16At16k };
