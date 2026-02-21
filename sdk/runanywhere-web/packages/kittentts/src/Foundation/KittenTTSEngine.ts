/**
 * KittenTTS Engine — ONNX Runtime inference for StyleTTS 2 models.
 *
 * Implements the full KittenTTS synthesis pipeline:
 *   1. Text preprocessing (numbers, currency, abbreviations)
 *   2. Text chunking (split at sentence boundaries, max 400 chars)
 *   3. Phonemization (espeak-ng IPA or built-in fallback)
 *   4. Tokenization (IPA chars → integer token IDs)
 *   5. Voice embedding selection (from voices.npz)
 *   6. ONNX inference (input_ids + style + speed → audio)
 *   7. Post-processing (trim, concatenate chunks)
 *
 * Reference: https://github.com/KittenML/KittenTTS/blob/main/kittentts/onnx_model.py
 */

import type * as ort from 'onnxruntime-web';
import { parseNPZAsync, type NpyArray } from './NPZParser';
import { phonemize, createSherpaEspeakPhonemizer, setPhonemizer } from './ESpeakPhonemizer';
import { preprocessText } from '../Infrastructure/TextPreprocessor';
import { chunkText, basicEnglishTokenize, tokenizePhonemes } from '../Infrastructure/TextCleaner';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface KittenTTSConfig {
  name: string;
  version: string;
  type: string;
  model: string;
  modelFile: string;
  voices: string;
  speedPriors: Record<string, number>;
  voiceAliases: Record<string, string>;
}

export type KittenTTSVoice = 'Bella' | 'Jasper' | 'Luna' | 'Bruno' | 'Rosie' | 'Hugo' | 'Kiki' | 'Leo';

const ALL_VOICES: KittenTTSVoice[] = ['Bella', 'Jasper', 'Luna', 'Bruno', 'Rosie', 'Hugo', 'Kiki', 'Leo'];

const SAMPLE_RATE = 24000;
const TRIM_SAMPLES = 5000;

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

export class KittenTTSEngine {
  private session: ort.InferenceSession | null = null;
  private voices: Map<string, NpyArray> = new Map();
  private config: KittenTTSConfig | null = null;
  private _isLoaded = false;
  private _modelId = '';

  get isLoaded(): boolean {
    return this._isLoaded;
  }

  get modelId(): string {
    return this._modelId;
  }

  get availableVoices(): KittenTTSVoice[] {
    return ALL_VOICES;
  }

  get sampleRate(): number {
    return SAMPLE_RATE;
  }

  /**
   * Load a KittenTTS model from raw file data.
   *
   * @param modelData - The ONNX model file bytes
   * @param voicesData - The voices.npz file bytes
   * @param configData - The config.json file bytes
   * @param modelId - Model identifier
   */
  async load(
    modelData: Uint8Array,
    voicesData: Uint8Array,
    configData: Uint8Array,
    modelId: string,
  ): Promise<void> {
    this.cleanup();

    // Parse config.json
    const configStr = new TextDecoder().decode(configData);
    const rawConfig = JSON.parse(configStr);
    this.config = {
      name: rawConfig.name ?? '',
      version: rawConfig.version ?? '',
      type: rawConfig.type ?? 'ONNX2',
      model: rawConfig.model ?? '',
      modelFile: rawConfig.model_file ?? '',
      voices: rawConfig.voices ?? 'voices.npz',
      speedPriors: rawConfig.speed_priors ?? {},
      voiceAliases: rawConfig.voice_aliases ?? {},
    };

    // Parse voice embeddings from NPZ
    this.voices = await parseNPZAsync(voicesData);

    // Create ONNX Runtime inference session
    const ortModule = await getORT();
    this.session = await ortModule.InferenceSession.create(
      modelData.buffer,
      {
        executionProviders: ['wasm'],
        graphOptimizationLevel: 'all',
      },
    );

    this._modelId = modelId;
    this._isLoaded = true;
  }

  /**
   * Try to set up the sherpa-onnx espeak phonemizer for better quality.
   * Call this after the sherpa-onnx WASM module is loaded (e.g., after VAD/STT init).
   */
  trySetupSherpaPhonmizer(sherpaModule: unknown): void {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const impl = createSherpaEspeakPhonemizer(sherpaModule as any);
    if (impl) {
      setPhonemizer(impl);
    }
  }

  /**
   * Synthesize speech from text.
   *
   * @param text - Input text
   * @param voice - Voice name (default: 'Jasper')
   * @param speed - Speed factor (default: 1.0)
   * @returns PCM audio as Float32Array at 24000 Hz
   */
  async synthesize(
    text: string,
    voice: KittenTTSVoice | string = 'Jasper',
    speed = 1.0,
  ): Promise<{ audioData: Float32Array; sampleRate: number; durationMs: number; processingTimeMs: number }> {
    if (!this.session || !this.config) {
      throw new Error('KittenTTS model not loaded. Call load() first.');
    }

    const startMs = performance.now();

    // Step 1: Preprocess text
    const cleanedText = preprocessText(text);

    // Step 2: Chunk text
    const chunks = chunkText(cleanedText);
    if (chunks.length === 0) {
      return { audioData: new Float32Array(0), sampleRate: SAMPLE_RATE, durationMs: 0, processingTimeMs: 0 };
    }

    // Step 3-6: Process each chunk
    const audioChunks: Float32Array[] = [];
    for (const chunk of chunks) {
      const audio = await this.synthesizeChunk(chunk, voice, speed);
      if (audio.length > 0) {
        audioChunks.push(audio);
      }
    }

    // Step 7: Concatenate chunks
    const totalLen = audioChunks.reduce((sum, c) => sum + c.length, 0);
    const audioData = new Float32Array(totalLen);
    let offset = 0;
    for (const chunk of audioChunks) {
      audioData.set(chunk, offset);
      offset += chunk.length;
    }

    const processingTimeMs = Math.round(performance.now() - startMs);
    const durationMs = Math.round((audioData.length / SAMPLE_RATE) * 1000);

    return { audioData, sampleRate: SAMPLE_RATE, durationMs, processingTimeMs };
  }

  private async synthesizeChunk(
    text: string,
    voice: KittenTTSVoice | string,
    speed: number,
  ): Promise<Float32Array> {
    if (!this.session || !this.config) {
      throw new Error('Model not loaded');
    }

    const ortModule = await getORT();

    // Resolve voice alias
    let resolvedVoice = voice;
    if (this.config.voiceAliases[voice]) {
      resolvedVoice = this.config.voiceAliases[voice];
    }

    // Apply speed priors
    let adjustedSpeed = speed;
    if (this.config.speedPriors[resolvedVoice]) {
      adjustedSpeed = speed * this.config.speedPriors[resolvedVoice];
    }

    // Phonemize
    const phonemes = await phonemize(text);

    // Tokenize: split phonemes, join with spaces, map to token IDs
    const phonemeTokens = basicEnglishTokenize(phonemes);
    const phonemeStr = phonemeTokens.join(' ');
    const tokenIds = tokenizePhonemes(phonemeStr);

    // Get voice embedding
    const voiceData = this.voices.get(resolvedVoice);
    if (!voiceData) {
      throw new Error(`Voice '${resolvedVoice}' not found in voices.npz. Available: ${[...this.voices.keys()].join(', ')}`);
    }

    // Select reference style based on text length (matching Python: ref_id = min(len(text), shape[0]-1))
    const refId = Math.min(text.length, voiceData.shape[0] - 1);
    const embeddingDim = voiceData.shape.length > 1 ? voiceData.shape[1] : voiceData.data.length;
    const refStyle = voiceData.data.subarray(refId * embeddingDim, (refId + 1) * embeddingDim);

    // Build ONNX inputs
    const inputIdsTensor = new ortModule.Tensor(
      'int64',
      BigInt64Array.from(tokenIds.map(BigInt)),
      [1, tokenIds.length],
    );

    const styleTensor = new ortModule.Tensor(
      'float32',
      new Float32Array(refStyle),
      [1, embeddingDim],
    );

    const speedTensor = new ortModule.Tensor(
      'float32',
      new Float32Array([adjustedSpeed]),
      [1],
    );

    // Run inference
    const feeds: Record<string, ort.Tensor> = {
      input_ids: inputIdsTensor,
      style: styleTensor,
      speed: speedTensor,
    };

    const results = await this.session.run(feeds);

    // Extract audio output (first output tensor)
    const outputNames = Object.keys(results);
    if (outputNames.length === 0) {
      throw new Error('No output from ONNX model');
    }

    const outputTensor = results[outputNames[0]];
    const rawAudio = outputTensor.data as Float32Array;

    // Trim last 5000 samples (matching Python: audio = outputs[0][..., :-5000])
    const trimmedLen = Math.max(0, rawAudio.length - TRIM_SAMPLES);
    return rawAudio.subarray(0, trimmedLen);
  }

  /** Clean up resources. */
  cleanup(): void {
    if (this.session) {
      this.session.release();
      this.session = null;
    }
    this.voices.clear();
    this.config = null;
    this._isLoaded = false;
    this._modelId = '';
  }
}

// ---------------------------------------------------------------------------
// Lazy ORT Import
// ---------------------------------------------------------------------------

let _ortModule: typeof ort | null = null;

async function getORT(): Promise<typeof ort> {
  if (_ortModule) return _ortModule;

  try {
    const ortMod = await import('onnxruntime-web');

    // Configure WASM paths so onnxruntime-web can find its binaries.
    // In Vite dev mode, the files must be served from public/ at the root path.
    ortMod.env.wasm.wasmPaths = '/';
    ortMod.env.wasm.numThreads = 1;

    _ortModule = ortMod;
    return _ortModule;
  } catch {
    throw new Error(
      'onnxruntime-web is required for KittenTTS. ' +
      'Install it: npm install onnxruntime-web',
    );
  }
}
