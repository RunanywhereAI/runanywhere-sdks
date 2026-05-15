/**
 * StandaloneSherpaTts — VITS / Piper TTS wrapper around the standalone
 * Sherpa Emscripten module's `_SherpaOnnxCreateOfflineTts` C API.
 *
 * The struct layout mirrors `SherpaOnnxOfflineTtsConfig` from
 * `sherpa-onnx/c-api/c-api.h` and matches the byte layout produced by
 * `wasm/tts/sherpa-onnx-tts.js > initSherpaOnnxOfflineTtsConfig`. Each
 * sub-struct is allocated as a fixed-size block populated via `setValue`
 * + UTF-8 strings copied into a side buffer.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';

const logger = new SDKLogger('StandaloneSherpaTts');

// Block sizes in bytes. Must match `*.len` from upstream
// `sherpa-onnx-tts.js`. Layout assumes 32-bit pointers (Emscripten WASM).
const VITS_BLOCK = 8 * 4;     // 32 bytes
const MATCHA_BLOCK = 8 * 4;   // 32 bytes
const KOKORO_BLOCK = 8 * 4;   // 32 bytes
const KITTEN_BLOCK = 5 * 4;   // 20 bytes
const ZIPVOICE_BLOCK = 10 * 4; // 40 bytes
const MODEL_TOP_BLOCK = 4 * 4; // num_threads, debug, provider*, ...
const MODEL_BLOCK = VITS_BLOCK + MODEL_TOP_BLOCK + MATCHA_BLOCK + KOKORO_BLOCK + KITTEN_BLOCK + ZIPVOICE_BLOCK;
const TTS_TOP_BLOCK = 4 * 4;  // rule_fsts*, max_num_sentences, rule_fars*, silence_scale
const TTS_CONFIG_SIZE = MODEL_BLOCK + TTS_TOP_BLOCK;

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

interface AllocatedString {
  ptr: number;
  bytes: number;
}

function allocString(module: StandaloneSherpaModule, str: string): AllocatedString {
  const bytes = module.lengthBytesUTF8(str ?? '') + 1;
  const ptr = module._malloc(bytes);
  module.stringToUTF8(str ?? '', ptr, bytes);
  return { ptr, bytes };
}

export class StandaloneSherpaTts {
  private handle: number = 0;
  private sampleRate: number = 0;

  constructor(private readonly module: StandaloneSherpaModule) {}

  load(config: StandaloneSherpaTtsConfig): void {
    if (this.handle) {
      this.destroy();
    }

    const m = this.module;
    if (typeof m._SherpaOnnxCreateOfflineTts !== 'function') {
      throw new Error('Standalone Sherpa module is missing _SherpaOnnxCreateOfflineTts.');
    }

    const cfgPtr = m._malloc(TTS_CONFIG_SIZE);
    m.HEAPU8.fill(0, cfgPtr, cfgPtr + TTS_CONFIG_SIZE);

    // Allocate per-string heap buffers we need to keep alive until the
    // SherpaOnnxCreate call returns. Each is freed in the finally block.
    const allocs: AllocatedString[] = [];
    const remember = (s: AllocatedString): number => {
      allocs.push(s);
      return s.ptr;
    };

    try {
      const vits = config.vits;
      const modelPtr = remember(allocString(m, vits.modelPath));
      const lexiconPtr = remember(allocString(m, vits.lexicon ?? ''));
      const tokensPtr = remember(allocString(m, vits.tokensPath));
      const dataDirPtr = remember(allocString(m, vits.dataDir ?? ''));
      const dictDirPtr = remember(allocString(m, ''));
      const providerPtr = remember(allocString(m, config.provider ?? 'cpu'));
      const ruleFstsPtr = remember(allocString(m, ''));
      const ruleFarsPtr = remember(allocString(m, ''));

      // SherpaOnnxOfflineTtsVitsModelConfig @ cfgPtr (32 bytes)
      m.setValue(cfgPtr + 0, modelPtr, 'i8*');
      m.setValue(cfgPtr + 4, lexiconPtr, 'i8*');
      m.setValue(cfgPtr + 8, tokensPtr, 'i8*');
      m.setValue(cfgPtr + 12, dataDirPtr, 'i8*');
      m.setValue(cfgPtr + 16, vits.noiseScale ?? 0.667, 'float');
      m.setValue(cfgPtr + 20, vits.noiseScaleW ?? 0.8, 'float');
      m.setValue(cfgPtr + 24, vits.lengthScale ?? 1.0, 'float');
      m.setValue(cfgPtr + 28, dictDirPtr, 'i8*');

      // OfflineTtsModelConfig top fields after vits (16 bytes)
      const modelTop = cfgPtr + VITS_BLOCK;
      m.setValue(modelTop + 0, config.numThreads ?? 1, 'i32');
      m.setValue(modelTop + 4, config.debug ? 1 : 0, 'i32');
      m.setValue(modelTop + 8, providerPtr, 'i8*');
      // (matcha / kokoro / kitten / zipvoice blocks remain zeroed = disabled)

      // OfflineTtsConfig top fields after model block
      const ttsTop = cfgPtr + MODEL_BLOCK;
      m.setValue(ttsTop + 0, ruleFstsPtr, 'i8*');
      m.setValue(ttsTop + 4, config.maxNumSentences ?? 1, 'i32');
      m.setValue(ttsTop + 8, ruleFarsPtr, 'i8*');
      m.setValue(ttsTop + 12, config.silenceScale ?? 0.2, 'float');

      const handle = m._SherpaOnnxCreateOfflineTts(cfgPtr);
      if (!handle) {
        throw new Error(
          `_SherpaOnnxCreateOfflineTts returned NULL for VITS model "${vits.modelPath}". ` +
          'Check that the tokens.txt and espeak-ng-data directory are staged in MEMFS.',
        );
      }
      this.handle = handle;
      this.sampleRate = m._SherpaOnnxOfflineTtsSampleRate?.(handle) ?? 22050;
      logger.info(
        `Standalone Sherpa TTS loaded (handle=${handle}, sampleRate=${this.sampleRate}, model=${vits.modelPath})`,
      );
    } finally {
      for (const a of allocs) m._free(a.ptr);
      m._free(cfgPtr);
    }
  }

  isLoaded(): boolean {
    return this.handle !== 0;
  }

  destroy(): void {
    if (!this.handle) return;
    const m = this.module;
    m._SherpaOnnxDestroyOfflineTts?.(this.handle);
    this.handle = 0;
    this.sampleRate = 0;
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

      // SherpaOnnxGeneratedAudio { float* samples; int32_t n; int32_t sample_rate; }
      const samplesPtr = m.HEAPU32[audioPtr / 4] >>> 0;
      const numSamples = m.HEAP32[audioPtr / 4 + 1];
      const sampleRate = m.HEAP32[audioPtr / 4 + 2];

      if (numSamples <= 0 || samplesPtr === 0) {
        throw new Error(`TTS produced 0 samples (sampleRate=${sampleRate})`);
      }

      // Copy out of WASM memory before destroying the audio handle.
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
}
