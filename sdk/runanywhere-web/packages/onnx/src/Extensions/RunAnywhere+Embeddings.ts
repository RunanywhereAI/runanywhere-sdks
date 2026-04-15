/**
 * RunAnywhere+Embeddings
 * -----------------------------------------------------------------------------
 * Web implementation of BERT-style text embeddings for RAG, via
 * `onnxruntime-web`.
 *
 * Model contract matches the native provider in
 * `sdk/runanywhere-commons/src/features/rag/onnx_embedding_provider.cpp`:
 *
 *   Input tensors  : input_ids (int64[1,N]), attention_mask (int64[1,N]),
 *                    token_type_ids (int64[1,N])  [token_type_ids optional]
 *   Output         : last_hidden_state[1,N,D]  → mean-pool → Float32[D]
 *
 * Status: scaffolded with session + config loading; tokenization + inference
 * stubbed.
 *
 * Why the tokenizer is the non-trivial part: the native code uses a
 * whitespace-based SimpleTokenizer because its input is already cleaned;
 * the web SDK needs full WordPiece (for all-MiniLM-L6-v2) or
 * SentencePiece (for multilingual models). Candidates for the follow-up:
 *   * @huggingface/tokenizers (wasm, matches HF's implementation exactly)
 *   * Port the SimpleTokenizer for parity with native RAG (quicker, weaker)
 *
 * Either way, the loader and session plumbing here stays the same — the
 * follow-up only fills `tokenize()` and the inference loop.
 */

import type * as ort from 'onnxruntime-web';
import { ORTRuntimeBridge } from '../Foundation/ORTRuntimeBridge';
import type {
  EmbedOptions,
  EmbeddingResult,
  EmbeddingsModelConfig,
} from './EmbeddingsTypes';

const NOT_IMPLEMENTED =
  'EmbeddingsService.embed() is scaffolded but tokenization + BERT inference ' +
  'are not yet ported to TypeScript. Load the model, but .embed() throws until ' +
  'the follow-up PR adds a WordPiece / SentencePiece tokenizer.';

export class EmbeddingsService {
  private config: EmbeddingsModelConfig | null = null;
  private session: ort.InferenceSession | null = null;
  private _inputNames: string[] = [];
  private _outputName: string | null = null;
  private _isReady = false;

  /**
   * Load the encoder ONNX model + tokenizer. Idempotent within a single
   * service instance (call `unload()` before switching models).
   */
  async load(config: EmbeddingsModelConfig): Promise<void> {
    await ORTRuntimeBridge.initialize();

    this.session = await ORTRuntimeBridge.createSession(config.model);
    this._inputNames = [...this.session.inputNames];
    this._outputName = this.session.outputNames[0] ?? null;
    this.config = {
      embeddingDim: 384,
      maxSeqLength: 512,
      normalize: true,
      ...config,
    };
    this._isReady = true;
  }

  /** True after `load()` completes successfully. */
  get isReady(): boolean {
    return this._isReady;
  }

  /** Dimensionality of output vectors. */
  get dim(): number {
    return this.config?.embeddingDim ?? 384;
  }

  /**
   * Embed a single text string into a fixed-dimension vector.
   *
   * NOT YET IMPLEMENTED — see file header.
   */
  async embed(_text: string, _options: EmbedOptions = {}): Promise<EmbeddingResult> {
    if (!this._isReady) {
      throw new Error('EmbeddingsService.load() must complete before embed().');
    }
    throw new Error(NOT_IMPLEMENTED);
  }

  /** Batch variant — runs `embed()` concurrently once implemented. */
  async embedBatch(
    _texts: readonly string[],
    _options: EmbedOptions = {},
  ): Promise<EmbeddingResult[]> {
    if (!this._isReady) {
      throw new Error('EmbeddingsService.load() must complete before embedBatch().');
    }
    throw new Error(NOT_IMPLEMENTED);
  }

  async unload(): Promise<void> {
    await this.session?.release();
    this.session = null;
    this._inputNames = [];
    this._outputName = null;
    this.config = null;
    this._isReady = false;
  }

  // Stable shape for future diagnostics; used by tests.
  _debugDescribe(): {
    ready: boolean;
    inputNames: readonly string[];
    outputName: string | null;
    dim: number;
  } {
    return {
      ready: this._isReady,
      inputNames: this._inputNames,
      outputName: this._outputName,
      dim: this.dim,
    };
  }
}

/** Module-level facade for one-shot use (mirrors STT / TTS / VAD export shape). */
export const Embeddings = new EmbeddingsService();
