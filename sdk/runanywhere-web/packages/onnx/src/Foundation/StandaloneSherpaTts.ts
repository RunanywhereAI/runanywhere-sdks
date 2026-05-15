/**
 * StandaloneSherpaTts — VITS / Piper TTS wrapper around the standalone
 * Sherpa Emscripten module's `_SherpaOnnxCreateOfflineTts` C API.
 *
 * The struct layout for `SherpaOnnxOfflineTtsConfig` is non-trivial: it
 * embeds five model-specific sub-configs (vits, matcha, kokoro, kitten,
 * zipvoice) plus rule_fsts/rule_fars/silence_scale. Re-implementing the
 * exact byte layout in TypeScript is brittle (we previously got the
 * vits-vs-matcha gap wrong by one i32 slot, which silently mis-fed the
 * matcha/kokoro/kitten/zipvoice fields and made the constructor return
 * NULL). Instead we delegate to the upstream `sherpa-onnx-tts.js`
 * `initSherpaOnnxOfflineTtsConfig` helper that ships with sherpa-onnx
 * itself and is guaranteed to track upstream layout changes.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';
import {
  loadSherpaTTSHelpers,
  type SherpaConfigHandle,
  type SherpaTTSHelpers,
  type UpstreamTtsConfig,
} from './SherpaUpstreamHelpers';

const logger = new SDKLogger('StandaloneSherpaTts');

export interface StandaloneSherpaTtsVitsConfig {
  modelPath: string;
  tokensPath: string;
  /** Path to the extracted `espeak-ng-data` directory. */
  dataDir?: string;
  /** Optional lexicon file (defaults to ''). */
  lexicon?: string;
  noiseScale?: number;
  noiseScaleW?: number;
  lengthScale?: number;
}

export interface StandaloneSherpaTtsConfig {
  vits: StandaloneSherpaTtsVitsConfig;
  numThreads?: number;
  provider?: string;
  debug?: boolean;
  maxNumSentences?: number;
  silenceScale?: number;
}

export interface StandaloneSherpaTtsResult {
  samples: Float32Array;
  sampleRate: number;
}

let _helpersPromise: Promise<SherpaTTSHelpers> | null = null;
function getTTSHelpers(): Promise<SherpaTTSHelpers> {
  if (!_helpersPromise) _helpersPromise = loadSherpaTTSHelpers();
  return _helpersPromise;
}

export class StandaloneSherpaTts {
  private handle: number = 0;
  private sampleRate: number = 0;
  private cfgHandle: SherpaConfigHandle | null = null;

  constructor(private readonly module: StandaloneSherpaModule) {}

  async load(config: StandaloneSherpaTtsConfig): Promise<void> {
    if (this.handle) {
      this.destroy();
    }

    const m = this.module;
    if (typeof m._SherpaOnnxCreateOfflineTts !== 'function') {
      throw new Error('Standalone Sherpa module is missing _SherpaOnnxCreateOfflineTts.');
    }

    const helpers = await getTTSHelpers();
    const upstreamConfig: UpstreamTtsConfig = {
      offlineTtsModelConfig: {
        offlineTtsVitsModelConfig: {
          model: config.vits.modelPath,
          lexicon: config.vits.lexicon ?? '',
          tokens: config.vits.tokensPath,
          dataDir: config.vits.dataDir ?? '',
          noiseScale: config.vits.noiseScale ?? 0.667,
          noiseScaleW: config.vits.noiseScaleW ?? 0.8,
          lengthScale: config.vits.lengthScale ?? 1.0,
        },
        numThreads: config.numThreads ?? 1,
        debug: config.debug ? 1 : 0,
        provider: config.provider ?? 'cpu',
      },
      ruleFsts: '',
      ruleFars: '',
      maxNumSentences: config.maxNumSentences ?? 1,
      silenceScale: config.silenceScale ?? 0.2,
    };

    const cfgHandle = helpers.initSherpaOnnxOfflineTtsConfig(upstreamConfig, m);
    this.cfgHandle = cfgHandle;

    const handle = m._SherpaOnnxCreateOfflineTts(cfgHandle.ptr);
    if (!handle) {
      this.releaseConfigHandle();
      throw new Error(
        `_SherpaOnnxCreateOfflineTts returned NULL for VITS model "${config.vits.modelPath}". ` +
          'Check that tokens.txt + espeak-ng-data are staged in MEMFS and ' +
          'that voices/<lang> exist (use ensureEspeakVoiceFiles).',
      );
    }
    this.handle = handle;
    this.sampleRate = m._SherpaOnnxOfflineTtsSampleRate?.(handle) ?? 22050;
    logger.info(
      `Standalone Sherpa TTS loaded (handle=${handle}, sampleRate=${this.sampleRate}, model=${config.vits.modelPath})`,
    );
  }

  isLoaded(): boolean {
    return this.handle !== 0;
  }

  destroy(): void {
    if (!this.handle) {
      this.releaseConfigHandle();
      return;
    }
    const m = this.module;
    m._SherpaOnnxDestroyOfflineTts?.(this.handle);
    this.handle = 0;
    this.sampleRate = 0;
    this.releaseConfigHandle();
  }

  getSampleRate(): number {
    return this.sampleRate;
  }

  /**
   * Synthesize `text` to a Float32 PCM buffer. `speakerId` defaults to 0
   * (the first speaker for VITS Piper voices). `speed` follows Sherpa's
   * convention: 1.0 = original tempo, < 1 = slower, > 1 = faster.
   */
  generate(text: string, speakerId: number = 0, speed: number = 1.0): StandaloneSherpaTtsResult {
    if (!this.handle) {
      throw new Error('StandaloneSherpaTts: no voice loaded; call load() first.');
    }
    const m = this.module;
    const generate = m._SherpaOnnxOfflineTtsGenerate;
    if (typeof generate !== 'function') {
      throw new Error('Standalone Sherpa module is missing _SherpaOnnxOfflineTtsGenerate.');
    }

    const textBytes = m.lengthBytesUTF8(text) + 1;
    const textPtr = m._malloc(textBytes);
    m.stringToUTF8(text, textPtr, textBytes);

    let audioPtr = 0;
    try {
      audioPtr = generate(this.handle, textPtr, speakerId, speed);
      if (!audioPtr) {
        throw new Error('SherpaOnnxOfflineTtsGenerate returned NULL audio handle');
      }

      const samplesPtr = m.HEAPU32[audioPtr / 4] >>> 0;
      const numSamples = m.HEAP32[audioPtr / 4 + 1];
      const sampleRate = m.HEAP32[audioPtr / 4 + 2];

      if (numSamples <= 0 || samplesPtr === 0) {
        throw new Error(`TTS produced 0 samples (sampleRate=${sampleRate})`);
      }

      const samples = new Float32Array(numSamples);
      const heap = m.HEAPF32;
      const baseIndex = samplesPtr >>> 2;
      for (let i = 0; i < numSamples; i += 1) {
        samples[i] = heap[baseIndex + i];
      }

      return { samples, sampleRate };
    } finally {
      m._free(textPtr);
      if (audioPtr) m._SherpaOnnxDestroyOfflineTtsGeneratedAudio?.(audioPtr);
    }
  }

  private releaseConfigHandle(): void {
    if (!this.cfgHandle) return;
    try {
      void getTTSHelpers().then((helpers) => helpers.freeConfig(this.cfgHandle!, this.module));
    } catch (err) {
      logger.warning(`Failed to free TTS config handle: ${err instanceof Error ? err.message : String(err)}`);
    }
    this.cfgHandle = null;
  }
}
