/**
 * RunAnywhere+Embeddings
 * -----------------------------------------------------------------------------
 * Web implementation of BERT-style text embeddings for RAG, via
 * `onnxruntime-web`.
 *
 * Mirrors the native provider in
 * `sdk/runanywhere-commons/src/backends/onnx/embeddings/onnx_embedding_provider.cpp`,
 * but uses a proper WordPiece tokenizer (see WordPieceTokenizer.ts) rather
 * than the native SimpleTokenizer — accuracy parity with HuggingFace
 * reference implementations of `all-MiniLM-L6-v2`, `bge-small-en`, etc.
 *
 * Pipeline:
 *   1. Tokenize text with WordPiece (BERT-style)
 *   2. Build input tensors: input_ids, attention_mask, token_type_ids
 *   3. Run encoder → last_hidden_state [1, N, D]
 *   4. Mean-pool along sequence dim (weighted by attention_mask) → [D]
 *   5. Optionally L2-normalize for cosine-similarity search
 */

import type * as ort from 'onnxruntime-web';
import { ORTRuntimeBridge } from '../Foundation/ORTRuntimeBridge';
import { WordPieceTokenizer } from '../Foundation/WordPieceTokenizer';
import type {
  EmbedOptions,
  EmbeddingResult,
  EmbeddingsModelConfig,
} from './EmbeddingsTypes';

export class EmbeddingsService {
  private config: Required<Omit<EmbeddingsModelConfig, 'model' | 'tokenizer'>> &
    Pick<EmbeddingsModelConfig, 'model' | 'tokenizer'> | null = null;
  private session: ort.InferenceSession | null = null;
  private tokenizer: WordPieceTokenizer | null = null;
  /** Map model-input-name → which tensor it wants. */
  private inputMapping: {
    inputIds: string | null;
    attentionMask: string | null;
    tokenTypeIds: string | null;
  } | null = null;
  private outputName: string | null = null;
  private _isReady = false;

  async load(config: EmbeddingsModelConfig): Promise<void> {
    await ORTRuntimeBridge.initialize();

    this.tokenizer = await this.buildTokenizer(config.tokenizer);
    this.session = await ORTRuntimeBridge.createSession(config.model);

    this.inputMapping = this.resolveInputMapping(this.session.inputNames);
    if (!this.inputMapping.inputIds || !this.inputMapping.attentionMask) {
      throw new Error(
        `EmbeddingsService: encoder must expose input_ids + attention_mask ` +
          `(got ${this.session.inputNames.join(', ')})`,
      );
    }
    this.outputName = this.session.outputNames[0] ?? null;
    if (!this.outputName) {
      throw new Error('EmbeddingsService: encoder exposes no output tensor');
    }

    this.config = {
      model: config.model,
      tokenizer: config.tokenizer,
      embeddingDim: config.embeddingDim ?? 384,
      maxSeqLength: config.maxSeqLength ?? 512,
      normalize: config.normalize ?? true,
    };
    this._isReady = true;
  }

  get isReady(): boolean {
    return this._isReady;
  }

  get dim(): number {
    return this.config?.embeddingDim ?? 384;
  }

  async embed(text: string, options: EmbedOptions = {}): Promise<EmbeddingResult> {
    if (!this._isReady || !this.session || !this.tokenizer || !this.config ||
        !this.inputMapping || !this.outputName) {
      throw new Error('EmbeddingsService.load() must complete before embed().');
    }

    const { Tensor } = ORTRuntimeBridge.ort;
    const encoded = this.tokenizer.encode(text, this.config.maxSeqLength);
    const seqLen = encoded.inputIds.length;

    const inputIds = BigInt64Array.from(encoded.inputIds, (x) => BigInt(x));
    const attention = BigInt64Array.from(encoded.attentionMask, (x) => BigInt(x));
    const tokenType = BigInt64Array.from(encoded.tokenTypeIds, (x) => BigInt(x));

    const feeds: Record<string, ort.Tensor> = {};
    feeds[this.inputMapping.inputIds!] = new Tensor('int64', inputIds, [1, seqLen]);
    feeds[this.inputMapping.attentionMask!] = new Tensor('int64', attention, [1, seqLen]);
    if (this.inputMapping.tokenTypeIds) {
      feeds[this.inputMapping.tokenTypeIds] = new Tensor('int64', tokenType, [1, seqLen]);
    }

    const output = await this.session.run(feeds);
    const lastHidden = output[this.outputName]!;
    const pooled = this.meanPool(lastHidden, encoded.attentionMask);

    const normalize = options.normalize ?? this.config.normalize;
    const vector = normalize ? this.l2Normalize(pooled) : pooled;

    return { vector, dim: vector.length, tokenCount: seqLen };
  }

  async embedBatch(
    texts: readonly string[],
    options: EmbedOptions = {},
  ): Promise<EmbeddingResult[]> {
    if (!this._isReady) {
      throw new Error('EmbeddingsService.load() must complete before embedBatch().');
    }
    // Sequential instead of Promise.all to cap memory churn on large batches;
    // ORT-web serializes under the hood anyway on the single-threaded path.
    const out: EmbeddingResult[] = [];
    for (const t of texts) out.push(await this.embed(t, options));
    return out;
  }

  async unload(): Promise<void> {
    await this.session?.release();
    this.session = null;
    this.tokenizer = null;
    this.inputMapping = null;
    this.outputName = null;
    this.config = null;
    this._isReady = false;
  }

  _debugDescribe(): {
    ready: boolean;
    inputMapping: {
      inputIds: string | null;
      attentionMask: string | null;
      tokenTypeIds: string | null;
    } | null;
    outputName: string | null;
    dim: number;
    vocabSize: number;
  } {
    return {
      ready: this._isReady,
      inputMapping: this.inputMapping,
      outputName: this.outputName,
      dim: this.dim,
      vocabSize: this.tokenizer?.vocabSize ?? 0,
    };
  }

  // =====================================================================
  // Internals
  // =====================================================================

  private async buildTokenizer(
    source: string | ArrayBuffer | Uint8Array,
  ): Promise<WordPieceTokenizer> {
    let text: string;
    let looksJson: boolean;
    if (typeof source === 'string') {
      const url = source;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`Failed to fetch tokenizer from ${url}: ${res.status}`);
      text = await res.text();
      looksJson = url.toLowerCase().endsWith('.json') || text.trimStart().startsWith('{');
    } else {
      const bytes = source instanceof Uint8Array ? source : new Uint8Array(source);
      text = new TextDecoder('utf-8').decode(bytes);
      looksJson = text.trimStart().startsWith('{');
    }
    if (looksJson) {
      const parsed = JSON.parse(text) as { model?: { vocab?: Record<string, number> } };
      return WordPieceTokenizer.fromTokenizerJson(parsed);
    }
    return WordPieceTokenizer.fromVocabText(text);
  }

  /**
   * Map well-known BERT input names to the actual model's input names.
   * Accepts common aliases so the same code works for HF-exported encoders
   * and ONNX-optimized variants.
   */
  private resolveInputMapping(inputNames: readonly string[]): {
    inputIds: string | null;
    attentionMask: string | null;
    tokenTypeIds: string | null;
  } {
    const pick = (aliases: readonly string[]): string | null => {
      for (const a of aliases) {
        const match = inputNames.find((n) => n === a || n.toLowerCase() === a);
        if (match) return match;
      }
      return null;
    };
    return {
      inputIds: pick(['input_ids', 'inputIds', 'input']),
      attentionMask: pick(['attention_mask', 'attentionMask']),
      tokenTypeIds: pick(['token_type_ids', 'tokenTypeIds', 'segment_ids']),
    };
  }

  private meanPool(hidden: ort.Tensor, attentionMask: readonly number[]): Float32Array {
    const dims = hidden.dims;
    // Accept [1, N, D] or [N, D].
    let seqLen: number;
    let hiddenDim: number;
    if (dims.length === 3) {
      seqLen = dims[1]!;
      hiddenDim = dims[2]!;
    } else if (dims.length === 2) {
      seqLen = dims[0]!;
      hiddenDim = dims[1]!;
    } else {
      throw new Error(`Unexpected encoder output rank ${dims.length}: [${dims.join(', ')}]`);
    }

    const data = hidden.data as Float32Array;
    const out = new Float32Array(hiddenDim);
    let totalWeight = 0;
    for (let t = 0; t < seqLen; t++) {
      const w = attentionMask[t] ?? 0;
      if (w === 0) continue;
      totalWeight += w;
      const rowStart = t * hiddenDim;
      for (let d = 0; d < hiddenDim; d++) {
        out[d]! += data[rowStart + d]! * w;
      }
    }
    if (totalWeight > 0) {
      const inv = 1 / totalWeight;
      for (let d = 0; d < hiddenDim; d++) out[d]! *= inv;
    }
    return out;
  }

  private l2Normalize(v: Float32Array): Float32Array {
    let sum = 0;
    for (let i = 0; i < v.length; i++) sum += v[i]! * v[i]!;
    const norm = Math.sqrt(sum);
    if (norm <= 1e-12) return v;
    const out = new Float32Array(v.length);
    const inv = 1 / norm;
    for (let i = 0; i < v.length; i++) out[i]! = v[i]! * inv;
    return out;
  }
}

/** Module-level facade for one-shot use (mirrors STT / TTS / VAD export shape). */
export const Embeddings = new EmbeddingsService();
