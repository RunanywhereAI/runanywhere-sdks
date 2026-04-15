/**
 * RunAnywhere+WakeWord
 * -----------------------------------------------------------------------------
 * Web implementation of wake-word detection via `onnxruntime-web`.
 *
 * Model contract matches the native openWakeWord backend in
 * `sdk/runanywhere-commons/src/backends/onnx/wakeword_onnx.cpp`:
 *
 *   Stage 1: melspectrogram.onnx          → audio (1280 samples, 80 ms @ 16kHz)
 *                                            → mel-spectrogram (32 bins)
 *   Stage 2: embedding_model.onnx         → 76-frame mel window (stride 8)
 *                                            → 96-dim embedding vector
 *   Stage 3: <classifier>.onnx            → 16-embedding window
 *                                            → wake-word probability in [0,1]
 *
 * Status: scaffolded with session loading + config; inference pipeline stubbed.
 *
 * The missing piece for end-to-end wake-word on web is the TypeScript port of
 * the feed-forward loop (`process_audio_frame` in the native cpp). That requires:
 *   * Sliding buffer for audio (1280 samples per feed)
 *   * Mel-spec → embedding windowing (76 frames, stride 8)
 *   * Embedding history (16 frames per classifier inference)
 *   * Per-classifier threshold + cooldown
 *
 * None of that is sherpa-onnx territory; it's a straight port of
 * `openWakeWord`'s Python reference implementation. Filed as a follow-up so
 * the architecture is ready but the ML-engineering work is a separate PR.
 */

import type * as ort from 'onnxruntime-web';
import { ORTRuntimeBridge } from '../Foundation/ORTRuntimeBridge';
import type {
  WakeWordCallback,
  WakeWordConfig,
  WakeWordSharedModelConfig,
} from './WakeWordTypes';

const NOT_IMPLEMENTED =
  'WakeWordService.feed() is scaffolded but the openWakeWord feed-forward ' +
  'pipeline is not yet ported to TypeScript. Load the models, but audio ' +
  'processing must land in a follow-up PR before detections will fire.';

interface LoadedClassifier {
  modelId: string;
  wakeWord: string;
  threshold: number;
  session: ort.InferenceSession;
  inputName: string;
  outputName: string;
}

export class WakeWordService {
  private config: WakeWordConfig | null = null;
  private melspecSession: ort.InferenceSession | null = null;
  private embeddingSession: ort.InferenceSession | null = null;
  private classifiers: LoadedClassifier[] = [];
  private callback: WakeWordCallback | null = null;
  private _isReady = false;

  /**
   * Load Stage 1 (melspec) + Stage 2 (embedding) + all classifiers.
   * Safe to call once at start-up. Models are kept in memory until unload().
   */
  async load(config: WakeWordConfig): Promise<void> {
    await ORTRuntimeBridge.initialize();

    this.config = config;

    // Load shared Stage 1 + Stage 2 in parallel with classifiers to minimize
    // perceived load latency. onnxruntime-web handles the WASM init internally.
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
            session,
            inputName: session.inputNames[0]!,
            outputName: session.outputNames[0]!,
          } satisfies LoadedClassifier;
        }),
      ),
    ]);

    this.melspecSession = melspec;
    this.embeddingSession = embedding;
    this.classifiers = classifierSessions;
    this._isReady = true;
  }

  /** True after `load()` completes successfully. */
  get isReady(): boolean {
    return this._isReady;
  }

  /** Subscribe to detection events. Only one callback is supported. */
  setCallback(cb: WakeWordCallback | null): void {
    this.callback = cb;
  }

  /**
   * Feed audio samples (Float32, mono, 16 kHz, [-1, 1]) into the detector.
   *
   * NOT YET IMPLEMENTED — see file header.
   */
  feed(_samples: Float32Array): void {
    if (!this._isReady) {
      throw new Error('WakeWordService.load() must complete before feed().');
    }
    throw new Error(NOT_IMPLEMENTED);
  }

  /** Release GPU / WASM resources. */
  async unload(): Promise<void> {
    await Promise.all([
      this.melspecSession?.release(),
      this.embeddingSession?.release(),
      ...this.classifiers.map((c) => c.session.release()),
    ]);
    this.melspecSession = null;
    this.embeddingSession = null;
    this.classifiers = [];
    this.callback = null;
    this.config = null;
    this._isReady = false;
  }

  // Stable shape for future diagnostics; used by tests.
  _debugDescribe(): {
    ready: boolean;
    sharedLoaded: boolean;
    classifierCount: number;
    sharedConfig: WakeWordSharedModelConfig | null;
  } {
    return {
      ready: this._isReady,
      sharedLoaded: !!this.melspecSession && !!this.embeddingSession,
      classifierCount: this.classifiers.length,
      sharedConfig: this.config?.shared ?? null,
    };
  }
}

/** Module-level facade for one-shot use (mirrors STT / TTS / VAD export shape). */
export const WakeWord = new WakeWordService();
