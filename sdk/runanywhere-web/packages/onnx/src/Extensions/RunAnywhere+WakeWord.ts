/**
 * RunAnywhere+WakeWord
 * -----------------------------------------------------------------------------
 * Web implementation of wake-word detection via `onnxruntime-web`.
 *
 * Full TypeScript port of the openWakeWord 3-stage pipeline from
 * `sdk/runanywhere-commons/src/backends/onnx/wakeword/wakeword_onnx.cpp`:
 *
 *   Stage 1: melspectrogram.onnx          audio (1280 samples, 80ms @16kHz)
 *                                          → mel-spectrogram (32 bins/frame)
 *   Stage 2: embedding_model.onnx         76-frame mel window (stride 8)
 *                                          → 96-dim embedding
 *   Stage 3: <classifier>.onnx            16-embedding window
 *                                          → wake-word probability [0, 1]
 *
 * All three stages are pure ORT inference — no hand-rolled mel-spec or FFT
 * logic. The only non-trivial bits are:
 *
 *   * The +480-sample audio-context overlap fed alongside each 1280-sample
 *     frame so mel-spec frames at frame boundaries are computed correctly
 *     (matches Python openWakeWord's 160*3 lookback).
 *   * The openWakeWord post-mel transform `(v / 10) + 2` applied to raw
 *     melspec output before it enters the embedding model.
 *   * Per-classifier cooldown so a single wake word doesn't fire every
 *     frame it stays above threshold.
 */

import type * as ort from 'onnxruntime-web';
import { ORTRuntimeBridge } from '../Foundation/ORTRuntimeBridge';
import type {
  WakeWordCallback,
  WakeWordConfig,
  WakeWordDetection,
  WakeWordSharedModelConfig,
} from './WakeWordTypes';

// -----------------------------------------------------------------------------
// Pipeline constants (match wakeword_onnx.cpp — do not change without matching
// a new openWakeWord release).
// -----------------------------------------------------------------------------

/** 80 ms @ 16 kHz. */
const FRAME_SIZE = 1280;
/** Lookback samples (160 * 3 = 30 ms) for mel-spec continuity. */
const MELSPEC_CONTEXT_SAMPLES = 480;
/** Mel bins per frame. */
const MELSPEC_BINS = 32;
/** Frames required for one embedding. */
const MELSPEC_WINDOW_SIZE = 76;
/** Frames between embedding windows. */
const MELSPEC_STRIDE = 8;
/** Embedding vector length. */
const EMBEDDING_DIM = 96;
/** Classifier input window size when the model doesn't specify. */
const DEFAULT_CLASSIFIER_EMBEDDINGS = 16;
/** Audio bound on melspec-frame history (~10 s). */
const MAX_MELSPEC_FRAMES = 970;
/** Audio bound on embedding history (~10 s). */
const MAX_EMBEDDING_HISTORY = 120;

// -----------------------------------------------------------------------------
// Internal bookkeeping
// -----------------------------------------------------------------------------

interface LoadedClassifier {
  modelId: string;
  wakeWord: string;
  threshold: number;
  /** Classifier input length N in the [1, N, 96] tensor shape. */
  numEmbeddings: number;
  session: ort.InferenceSession;
  inputName: string;
  outputName: string;
  /** Last frame index at which we emitted a detection (for cooldown). */
  lastDetectionFrame: number;
}

export class WakeWordService {
  private config: WakeWordConfig | null = null;
  private melspecSession: ort.InferenceSession | null = null;
  private embeddingSession: ort.InferenceSession | null = null;
  private melspecIo: { input: string; output: string } | null = null;
  private embeddingIo: { input: string; output: string } | null = null;
  private classifiers: LoadedClassifier[] = [];
  private callback: WakeWordCallback | null = null;
  private _isReady = false;

  // Streaming state --------------------------------------------------------
  /** Pending audio samples, not yet aligned into a 1280-sample frame. */
  private audioBuffer: number[] = [];
  /** Last MELSPEC_CONTEXT_SAMPLES samples, prepended to each new frame. */
  private contextBuffer: Float32Array = new Float32Array(0);
  /** All mel-spec frames we've computed so far (each is Float32Array[32]). */
  private melspecBuffer: Float32Array[] = [];
  /** Index of the next mel-spec frame we have NOT yet embedded. */
  private nextUnwindowedMelspecIndex = 0;
  /** Computed embeddings (each is Float32Array[96]). */
  private embeddingBuffer: Float32Array[] = [];
  /** Running count of 80 ms frames processed since load(). */
  private frameIndex = 0;

  // =====================================================================
  // Public API
  // =====================================================================

  async load(config: WakeWordConfig): Promise<void> {
    await ORTRuntimeBridge.initialize();

    if (config.classifiers.length === 0) {
      throw new Error('WakeWordService.load(): at least one classifier required');
    }

    const [melspec, embedding, classifierSessions] = await Promise.all([
      ORTRuntimeBridge.createSession(config.shared.melspectrogramModel),
      ORTRuntimeBridge.createSession(config.shared.embeddingModel),
      Promise.all(
        config.classifiers.map(async (c) => {
          const session = await ORTRuntimeBridge.createSession(c.classifierModel);
          return {
            modelId: c.modelId,
            wakeWord: c.wakeWord,
            threshold: c.threshold ?? config.globalThreshold ?? 0.5,
            // Introspect the classifier's input tensor to learn N (the number
            // of embeddings it wants). Fall back to 16 if the model metadata
            // doesn't resolve a concrete shape.
            numEmbeddings: this.resolveClassifierWindow(session),
            session,
            inputName: session.inputNames[0]!,
            outputName: session.outputNames[0]!,
            lastDetectionFrame: -Infinity,
          } satisfies LoadedClassifier;
        }),
      ),
    ]);

    this.config = config;
    this.melspecSession = melspec;
    this.melspecIo = {
      input: melspec.inputNames[0]!,
      output: melspec.outputNames[0]!,
    };
    this.embeddingSession = embedding;
    this.embeddingIo = {
      input: embedding.inputNames[0]!,
      output: embedding.outputNames[0]!,
    };
    this.classifiers = classifierSessions;
    this.resetStreamingState();
    this._isReady = true;
  }

  get isReady(): boolean {
    return this._isReady;
  }

  setCallback(cb: WakeWordCallback | null): void {
    this.callback = cb;
  }

  /**
   * Feed audio samples (Float32, mono, 16 kHz, range [-1, 1]) into the
   * detector. Processes as many complete 1280-sample frames as the buffer
   * allows; leftover samples stay buffered for the next feed().
   *
   * Awaitable because ORT inference is async on the WASM backend.
   */
  async feed(samples: Float32Array | Int16Array): Promise<void> {
    if (!this._isReady) {
      throw new Error('WakeWordService.load() must complete before feed().');
    }

    // Normalize int16 → float32 in-place into the buffer.
    if (samples instanceof Int16Array) {
      for (let i = 0; i < samples.length; i++) {
        this.audioBuffer.push(samples[i]! / 32768);
      }
    } else {
      for (let i = 0; i < samples.length; i++) {
        this.audioBuffer.push(samples[i]!);
      }
    }

    while (this.audioBuffer.length >= FRAME_SIZE) {
      const frame = Float32Array.from(this.audioBuffer.splice(0, FRAME_SIZE));
      await this.processFrame(frame);
    }
  }

  /** Clear buffered audio and detection state without unloading models. */
  reset(): void {
    this.resetStreamingState();
  }

  async unload(): Promise<void> {
    await Promise.all([
      this.melspecSession?.release(),
      this.embeddingSession?.release(),
      ...this.classifiers.map((c) => c.session.release()),
    ]);
    this.melspecSession = null;
    this.embeddingSession = null;
    this.melspecIo = null;
    this.embeddingIo = null;
    this.classifiers = [];
    this.callback = null;
    this.config = null;
    this.resetStreamingState();
    this._isReady = false;
  }

  _debugDescribe(): {
    ready: boolean;
    sharedLoaded: boolean;
    classifierCount: number;
    sharedConfig: WakeWordSharedModelConfig | null;
    melspecFrames: number;
    embeddings: number;
    frameIndex: number;
  } {
    return {
      ready: this._isReady,
      sharedLoaded: !!this.melspecSession && !!this.embeddingSession,
      classifierCount: this.classifiers.length,
      sharedConfig: this.config?.shared ?? null,
      melspecFrames: this.melspecBuffer.length,
      embeddings: this.embeddingBuffer.length,
      frameIndex: this.frameIndex,
    };
  }

  // =====================================================================
  // Pipeline — private
  // =====================================================================

  private resetStreamingState(): void {
    this.audioBuffer = [];
    this.contextBuffer = new Float32Array(0);
    // Pre-fill melspec buffer with 76 frames of ones(32) so the first
    // embedding can be generated immediately (matches Python's np.ones((76, 32))
    // initialization in openWakeWord).
    this.melspecBuffer = [];
    for (let i = 0; i < MELSPEC_WINDOW_SIZE; i++) {
      const frame = new Float32Array(MELSPEC_BINS);
      frame.fill(1);
      this.melspecBuffer.push(frame);
    }
    this.nextUnwindowedMelspecIndex = 0;
    this.embeddingBuffer = [];
    this.frameIndex = 0;
    for (const c of this.classifiers) {
      c.lastDetectionFrame = -Infinity;
    }
  }

  private async processFrame(frame: Float32Array): Promise<void> {
    this.frameIndex += 1;

    // 1. Prepend the context buffer so mel-spec boundary frames are correct.
    const input = new Float32Array(this.contextBuffer.length + frame.length);
    input.set(this.contextBuffer, 0);
    input.set(frame, this.contextBuffer.length);

    // 2. Stage 1 — mel-spectrogram.
    const newMelspecFrames = await this.runMelspec(input);
    if (newMelspecFrames) {
      for (const f of newMelspecFrames) {
        this.melspecBuffer.push(f);
      }
      // Cap history.
      while (this.melspecBuffer.length > MAX_MELSPEC_FRAMES) {
        this.melspecBuffer.shift();
        if (this.nextUnwindowedMelspecIndex > 0) {
          this.nextUnwindowedMelspecIndex -= 1;
        }
      }
    }

    // 3. Update the 480-sample lookback for the next frame.
    this.contextBuffer = frame.slice(
      Math.max(0, frame.length - MELSPEC_CONTEXT_SAMPLES),
    );

    // 4. Stage 2 — sliding 76-frame windows, stride 8.
    await this.generateEmbeddings();

    // 5. Stage 3 — classifier(s).
    await this.runClassifiers();
  }

  private async runMelspec(audio: Float32Array): Promise<Float32Array[] | null> {
    if (!this.melspecSession || !this.melspecIo) return null;

    const { InferenceSession: _IS, Tensor } = ORTRuntimeBridge.ort;
    const input = new Tensor('float32', audio, [1, audio.length]);

    let output: ort.InferenceSession.OnnxValueMapType;
    try {
      output = await this.melspecSession.run({ [this.melspecIo.input]: input });
    } catch (e) {
      console.error('[WakeWord] melspec inference failed', e);
      return null;
    }

    const out = output[this.melspecIo.output]! as ort.Tensor;
    const dims = out.dims;
    const data = out.data as Float32Array;

    // Accepted shapes: [frames, 32], [1, frames, 32], or flat multiple of 32.
    let numFrames: number;
    if (dims.length === 2) {
      numFrames = dims[0]!;
    } else if (dims.length === 3) {
      numFrames = dims[1]!;
    } else {
      numFrames = Math.floor(data.length / MELSPEC_BINS);
    }

    const frames: Float32Array[] = [];
    for (let f = 0; f < numFrames; f++) {
      const frame = new Float32Array(MELSPEC_BINS);
      for (let b = 0; b < MELSPEC_BINS; b++) {
        // openWakeWord post-mel transform: (v / 10) + 2
        frame[b] = data[f * MELSPEC_BINS + b]! / 10 + 2;
      }
      frames.push(frame);
    }
    return frames;
  }

  private async generateEmbeddings(): Promise<void> {
    if (!this.embeddingSession || !this.embeddingIo) return;

    let start = this.nextUnwindowedMelspecIndex;
    while (start + MELSPEC_WINDOW_SIZE <= this.melspecBuffer.length) {
      const windowBuf = new Float32Array(MELSPEC_WINDOW_SIZE * MELSPEC_BINS);
      for (let i = 0; i < MELSPEC_WINDOW_SIZE; i++) {
        const src = this.melspecBuffer[start + i]!;
        windowBuf.set(src, i * MELSPEC_BINS);
      }

      const { Tensor } = ORTRuntimeBridge.ort;
      const input = new Tensor('float32', windowBuf, [
        1,
        MELSPEC_WINDOW_SIZE,
        MELSPEC_BINS,
        1,
      ]);

      let output: ort.InferenceSession.OnnxValueMapType;
      try {
        output = await this.embeddingSession.run({
          [this.embeddingIo.input]: input,
        });
      } catch (e) {
        console.error('[WakeWord] embedding inference failed', e);
        return;
      }

      const data = output[this.embeddingIo.output]!.data as Float32Array;
      const emb = new Float32Array(EMBEDDING_DIM);
      const copyLen = Math.min(data.length, EMBEDDING_DIM);
      emb.set(data.subarray(0, copyLen));
      // Zero-pad if the model emits < 96 dims.
      this.embeddingBuffer.push(emb);
      while (this.embeddingBuffer.length > MAX_EMBEDDING_HISTORY) {
        this.embeddingBuffer.shift();
      }

      start += MELSPEC_STRIDE;
    }
    this.nextUnwindowedMelspecIndex = start;
  }

  private async runClassifiers(): Promise<void> {
    const cooldownFrames = this.config?.cooldownFrames ?? 0;
    for (const clf of this.classifiers) {
      const n = clf.numEmbeddings;
      if (this.embeddingBuffer.length < n) continue;

      const windowBuf = new Float32Array(n * EMBEDDING_DIM);
      const startIdx = this.embeddingBuffer.length - n;
      for (let i = 0; i < n; i++) {
        windowBuf.set(this.embeddingBuffer[startIdx + i]!, i * EMBEDDING_DIM);
      }

      const { Tensor } = ORTRuntimeBridge.ort;
      const input = new Tensor('float32', windowBuf, [1, n, EMBEDDING_DIM]);

      let output: ort.InferenceSession.OnnxValueMapType;
      try {
        output = await clf.session.run({ [clf.inputName]: input });
      } catch (e) {
        console.error(`[WakeWord] classifier ${clf.modelId} failed`, e);
        continue;
      }

      const raw = output[clf.outputName]!.data as Float32Array;
      const score = raw[0] ?? 0;

      if (score >= clf.threshold) {
        const sinceLast = this.frameIndex - clf.lastDetectionFrame;
        if (sinceLast >= cooldownFrames) {
          clf.lastDetectionFrame = this.frameIndex;
          const detection: WakeWordDetection = {
            modelId: clf.modelId,
            wakeWord: clf.wakeWord,
            score,
            frameIndex: this.frameIndex,
          };
          this.callback?.(detection);
        }
      }
    }
  }

  /**
   * Learn N from the classifier's input metadata. Shape is expected to be
   * [batch=1, N, 96] — we pick the dimension whose index is 1. If the model
   * uses a dynamic axis (reported as 0 or -1), fall back to the default.
   */
  private resolveClassifierWindow(session: ort.InferenceSession): number {
    try {
      const inputMeta = (
        session as unknown as {
          inputMetadata?: Array<{ dimensions?: ReadonlyArray<number> }>;
        }
      ).inputMetadata;
      const dims = inputMeta?.[0]?.dimensions;
      if (dims && dims.length >= 2) {
        const candidate = dims[1];
        if (candidate && candidate > 0 && candidate < 1024) return candidate;
      }
    } catch {
      /* fall through */
    }
    return DEFAULT_CLASSIFIER_EMBEDDINGS;
  }
}

/** Module-level facade for one-shot use (mirrors STT / TTS / VAD export shape). */
export const WakeWord = new WakeWordService();
