/**
 * StandaloneSherpaStt — Whisper offline recognizer wrapper around the
 * standalone Sherpa Emscripten module's `_SherpaOnnxCreateOfflineRecognizer`
 * C API.
 *
 * The OfflineRecognizerConfig struct is large (~200 bytes with many
 * sub-structs). Rather than re-implementing its byte layout in TS we
 * reuse the upstream `sherpa-onnx-asr.js` `initSherpaOnnxOfflineRecognizerConfig`
 * helper via `SherpaUpstreamHelpers`. That keeps us aligned with the
 * upstream sherpa-onnx ABI for free.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';
import {
  loadSherpaASRHelpers,
  type SherpaConfigHandle,
} from './SherpaUpstreamHelpers';

const logger = new SDKLogger('StandaloneSherpaStt');

export interface StandaloneSherpaSttWhisperConfig {
  /** Path to `*-encoder.{int8,}.onnx` inside the staged model directory. */
  encoderPath: string;
  /** Path to `*-decoder.{int8,}.onnx` inside the staged model directory. */
  decoderPath: string;
  /** Path to `tokens.txt` inside the staged model directory. */
  tokensPath: string;
  /** Whisper task: `transcribe` (default) or `translate`. */
  task?: string;
  /** ISO-639 language code (`en`, `es`, …). */
  language?: string;
  /** Whisper tail padding in samples (Sherpa defaults to -1 → auto). */
  tailPaddings?: number;
}

export interface StandaloneSherpaSttConfig {
  whisper: StandaloneSherpaSttWhisperConfig;
  numThreads?: number;
  provider?: string;
  decodingMethod?: string;
  maxActivePaths?: number;
  debug?: boolean;
}

export interface StandaloneSherpaSttResult {
  text: string;
  tokens?: string[];
  timestamps?: number[];
  raw: string;
}

export class StandaloneSherpaStt {
  private handle: number = 0;
  private helperConfig: SherpaConfigHandle | null = null;

  constructor(private readonly module: StandaloneSherpaModule) {}

  async load(config: StandaloneSherpaSttConfig): Promise<void> {
    if (this.handle) {
      this.destroy();
    }
    const m = this.module;
    if (typeof m._SherpaOnnxCreateOfflineRecognizer !== 'function') {
      throw new Error('Standalone Sherpa module is missing _SherpaOnnxCreateOfflineRecognizer.');
    }

    const helpers = await loadSherpaASRHelpers();

    const whisper = config.whisper;
    const initConfig: Record<string, unknown> = {
      featConfig: {
        sampleRate: 16000,
        featureDim: 80,
      },
      modelConfig: {
        debug: config.debug ? 1 : 0,
        numThreads: config.numThreads ?? 1,
        provider: config.provider ?? 'cpu',
        modelType: 'whisper',
        tokens: whisper.tokensPath,
        whisper: {
          encoder: whisper.encoderPath,
          decoder: whisper.decoderPath,
          language: whisper.language ?? '',
          task: whisper.task ?? 'transcribe',
          tailPaddings: whisper.tailPaddings ?? -1,
        },
      },
      decodingMethod: config.decodingMethod ?? 'greedy_search',
      maxActivePaths: config.maxActivePaths ?? 4,
    };

    const helperConfig = helpers.initSherpaOnnxOfflineRecognizerConfig(initConfig, m);
    try {
      const handle = m._SherpaOnnxCreateOfflineRecognizer(helperConfig.ptr);
      if (!handle) {
        helpers.freeConfig(helperConfig, m);
        throw new Error(
          `_SherpaOnnxCreateOfflineRecognizer returned NULL for Whisper encoder=${whisper.encoderPath}.`,
        );
      }
      this.handle = handle;
      this.helperConfig = helperConfig;
      logger.info(
        `Standalone Sherpa STT loaded (handle=${handle}, encoder=${whisper.encoderPath})`,
      );
    } catch (err) {
      helpers.freeConfig(helperConfig, m);
      throw err;
    }
  }

  isLoaded(): boolean {
    return this.handle !== 0;
  }

  destroy(): void {
    const m = this.module;
    if (this.handle && typeof m._SherpaOnnxDestroyOfflineRecognizer === 'function') {
      m._SherpaOnnxDestroyOfflineRecognizer(this.handle);
    }
    if (this.helperConfig) {
      // Best-effort free of the helper-allocated config blocks.
      void loadSherpaASRHelpers().then((helpers) => helpers.freeConfig(this.helperConfig!, m)).catch(() => undefined);
    }
    this.handle = 0;
    this.helperConfig = null;
  }

  /**
   * Transcribe a Float32Array of PCM samples (16 kHz, mono). Returns the
   * decoded text + the raw JSON Sherpa returns for advanced consumers.
   */
  transcribe(samples: Float32Array, sampleRate: number = 16000): StandaloneSherpaSttResult {
    if (!this.handle) {
      throw new Error('StandaloneSherpaStt: no model loaded; call load() first.');
    }
    const m = this.module;

    const createStream = m._SherpaOnnxCreateOfflineStream;
    const accept = m._SherpaOnnxAcceptWaveformOffline;
    const decode = m._SherpaOnnxDecodeOfflineStream;
    const getJson = m._SherpaOnnxGetOfflineStreamResultAsJson;
    const destroyJson = m._SherpaOnnxDestroyOfflineStreamResultJson;
    const destroyStream = m._SherpaOnnxDestroyOfflineStream;
    if (!createStream || !accept || !decode || !getJson || !destroyJson || !destroyStream) {
      throw new Error('Standalone Sherpa module is missing one or more offline-stream STT exports.');
    }

    const stream = createStream(this.handle);
    if (!stream) throw new Error('SherpaOnnxCreateOfflineStream returned NULL.');

    const samplesPtr = m._malloc(samples.length * 4);
    let jsonPtr = 0;
    try {
      m.HEAPF32.set(samples, samplesPtr / 4);
      accept(stream, sampleRate, samplesPtr, samples.length);
      decode(this.handle, stream);
      jsonPtr = getJson(stream);
      const raw = jsonPtr ? m.UTF8ToString(jsonPtr) : '{}';
      const parsed = safeParse(raw);
      const text = (typeof parsed?.text === 'string' ? parsed.text : '').trim();
      const tokens = Array.isArray(parsed?.tokens) ? parsed.tokens.map(String) : undefined;
      const timestamps = Array.isArray(parsed?.timestamps) ? parsed.timestamps.map(Number) : undefined;
      return { text, tokens, timestamps, raw };
    } finally {
      if (jsonPtr) destroyJson(jsonPtr);
      m._free(samplesPtr);
      destroyStream(stream);
    }
  }
}

function safeParse(json: string): {
  text?: unknown;
  tokens?: unknown;
  timestamps?: unknown;
} {
  try {
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return {};
  }
}
