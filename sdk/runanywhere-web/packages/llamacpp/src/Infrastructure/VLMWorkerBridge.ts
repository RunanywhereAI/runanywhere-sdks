/**
 * RunAnywhere Web SDK - VLM Worker Bridge (V2-canonical)
 *
 * Main-thread proxy for the VLM Web Worker. Vision-language inference
 * runs off the main thread so the camera, UI animations, and event loop
 * stay responsive during the multi-second `_rac_vlm_process_proto` call.
 *
 * The bridge owns:
 *   - A dedicated `Worker` instance loaded from `vlm-worker.js`
 *   - Promise correlation by message ID
 *   - WASM OOM detection + recreate-and-retry recovery
 *   - Qwen2-VL CPU pinning (Qwen produces NaN logits on WebGPU because
 *     f16 M-RoPE overflows in the rotary position encoding shader)
 *   - Last-loaded-model snapshot for transparent recovery after a crash
 *
 * The worker side runs `VLMWorkerRuntime` which loads its OWN Emscripten
 * module — separate from the main-thread bridge — so a VLM crash never
 * corrupts the main-thread WASM heap.
 *
 * Usage:
 *   ```typescript
 *   const vlm = VLMWorkerBridge.shared;
 *   await vlm.init();
 *   await vlm.loadModel({ modelPath: '/models/llava.gguf', mmprojPath: '...', modelId: '...', modelName: '...' });
 *   const result = await vlm.process(image, options);
 *   ```
 */

import {
  SDKLogger,
  VLMImage,
  VLMGenerationOptions,
  VLMResult,
  type VLMImage as ProtoVLMImage,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMResult as ProtoVLMResult,
} from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';
import type { VLMLoadModelParams } from '../Types/VLMWorkerTypes';

export type { VLMLoadModelParams } from '../Types/VLMWorkerTypes';

// ---------------------------------------------------------------------------
// RPC protocol — typed messages exchanged between main thread and worker
// ---------------------------------------------------------------------------

/** Commands sent from main thread → worker. */
export type VLMWorkerCommand =
  | {
      type: 'init';
      id: number;
      payload: { wasmJsUrl: string; useWebGPU: boolean };
    }
  | {
      type: 'load-model';
      id: number;
      payload: VLMLoadModelParams;
    }
  | {
      type: 'process';
      id: number;
      payload: { imageBytes: Uint8Array; optionsBytes: Uint8Array };
    }
  | { type: 'cancel'; id: number }
  | { type: 'unload'; id: number };

/** Responses sent from worker → main thread. */
export type VLMWorkerResponse =
  | { id: number; type: 'result'; payload: unknown }
  | { id: number; type: 'error'; payload: { message: string } }
  | { id: number; type: 'progress'; payload: { stage: string } };

/** Optional callback invoked with progress strings during model load. */
export type ProgressListener = (stage: string) => void;

const logger = new SDKLogger('VLMWorkerBridge');

// ---------------------------------------------------------------------------
// VLMWorkerBridge — singleton main-thread proxy
// ---------------------------------------------------------------------------

export class VLMWorkerBridge {
  private static _instance: VLMWorkerBridge | null = null;

  static get shared(): VLMWorkerBridge {
    if (!VLMWorkerBridge._instance) {
      VLMWorkerBridge._instance = new VLMWorkerBridge();
    }
    return VLMWorkerBridge._instance;
  }

  // ---- State ----
  private worker: Worker | null = null;
  private nextId = 0;
  private pending = new Map<
    number,
    { resolve: (v: unknown) => void; reject: (e: Error) => void }
  >();
  private _initialized = false;
  private _modelLoaded = false;
  private _progressListeners: ProgressListener[] = [];
  /** Saved for OOM-recovery — recreate worker + reload model + retry. */
  private _lastModelParams: VLMLoadModelParams | null = null;
  private _needsRecovery = false;
  /** Optional override for the worker bundle URL (e.g. tests / custom deploy). */
  private _workerUrl: URL | string | null = null;

  get isInitialized(): boolean {
    return this._initialized;
  }
  get isModelLoaded(): boolean {
    return this._modelLoaded;
  }

  /**
   * Set a custom Worker URL. By default the bridge uses the SDK's bundled
   * entry point (`workers/vlm-worker.js`). Apps that ship the worker from
   * a different deploy path can call this before `init()`.
   */
  set workerUrl(url: URL | string) {
    this._workerUrl = url;
  }

  // -----------------------------------------------------------------------
  // Progress
  // -----------------------------------------------------------------------

  onProgress(fn: ProgressListener): () => void {
    this._progressListeners.push(fn);
    return () => {
      this._progressListeners = this._progressListeners.filter((l) => l !== fn);
    };
  }

  private emitProgress(stage: string): void {
    for (const fn of this._progressListeners) fn(stage);
  }

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /**
   * Initialise the worker and its WASM instance.
   *
   * Reads the WASM URL and acceleration mode from `LlamaCppBridge` so the
   * worker loads the same variant (CPU vs WebGPU) the main thread already
   * picked.
   */
  async init(wasmJsUrl?: string): Promise<void> {
    if (this._initialized) return;

    const bridge = LlamaCppBridge.shared;
    const useWebGPU = bridge.accelerationMode === 'webgpu';
    const resolvedUrl = wasmJsUrl ?? bridge.wasmUrl ?? null;

    if (!resolvedUrl) {
      throw new Error(
        '[VLMWorkerBridge] Main bridge has not loaded WASM yet — call LlamaCPP.register() first',
      );
    }

    this.spawnWorker();
    await this.send('init', { wasmJsUrl: resolvedUrl, useWebGPU });
    this._initialized = true;
    logger.info(`Worker initialised (${useWebGPU ? 'WebGPU' : 'CPU'})`);
  }

  /**
   * Load a VLM model in the worker.
   *
   * If the model is Qwen2-VL and the main bridge picked WebGPU, the worker
   * is restarted on the CPU WASM binary because Qwen2-VL produces NaN
   * logits on WebGPU due to f16 M-RoPE overflow.
   */
  async loadModel(params: VLMLoadModelParams): Promise<void> {
    if (!this._initialized) {
      await this.init();
    }

    // Qwen2-VL CPU pinning — see top-of-file comment.
    const bridge = LlamaCppBridge.shared;
    const isQwenVL =
      /qwen.*vl/i.test(params.modelId) || /qwen.*vl/i.test(params.modelName);
    if (isQwenVL && bridge.accelerationMode === 'webgpu') {
      const currentUrl = bridge.wasmUrl ?? '';
      const cpuUrl = currentUrl.replace(/-webgpu\.js$/, '.js');
      if (cpuUrl !== currentUrl) {
        logger.info(
          'Qwen2-VL detected — restarting VLM Worker with CPU WASM (M-RoPE compat)',
        );
        this.terminate();
        await this.initWithUrl(cpuUrl, false);
      }
    }

    const transferables: Transferable[] = [params.modelData, params.mmprojData];
    await this.send('load-model', params, transferables);
    this._modelLoaded = true;
    this._lastModelParams = params;
    this._needsRecovery = false;
    logger.info(`Model loaded in worker: ${params.modelId}`);
  }

  /**
   * Process an image through the VLM and return a typed `ProtoVLMResult`.
   *
   * The image / options are encoded as proto bytes and forwarded to the
   * worker, which decodes them on its side, calls `_rac_vlm_process_proto`,
   * and returns the encoded `VLMResult` bytes — the same wire format used by
   * the main-thread `VLMProtoAdapter` so callers see a uniform surface.
   */
  async process(
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult> {
    if (this._needsRecovery) {
      await this.recover();
    }
    if (!this._modelLoaded) {
      throw new Error(
        '[VLMWorkerBridge] No VLM model loaded in worker. Call loadModel() first.',
      );
    }

    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();

    try {
      const responseBytes = (await this.send('process', {
        imageBytes,
        optionsBytes,
      })) as Uint8Array;
      return VLMResult.decode(responseBytes);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // WASM runtime crashes (OOB, stack overflow, JSPI corruption) leave the
      // module unrecoverable — mark for recreate so the next call gets a
      // fresh worker + WASM instance + reloaded model.
      if (
        msg.includes('memory access out of bounds') ||
        msg.includes('unreachable') ||
        msg.includes('RuntimeError') ||
        msg.includes('out of memory')
      ) {
        logger.warning(
          `WASM crash detected (${msg.slice(0, 80)}…) — will recover on next call`,
        );
        this._needsRecovery = true;
      }
      throw err;
    }
  }

  /** Cancel the in-flight VLM generation. Best-effort — no result returned. */
  cancel(): void {
    if (!this.worker) return;
    this.worker.postMessage({ type: 'cancel', id: -2 });
  }

  /** Unload the model in the worker (keeps the WASM instance). */
  async unloadModel(): Promise<void> {
    if (!this._modelLoaded) return;
    await this.send('unload', {});
    this._modelLoaded = false;
  }

  /** Terminate the worker entirely; rejects all in-flight RPC promises. */
  terminate(): void {
    for (const [, { reject }] of this.pending) {
      reject(new Error('VLM Worker terminated'));
    }
    this.pending.clear();

    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    this._initialized = false;
    this._modelLoaded = false;
  }

  // -----------------------------------------------------------------------
  // Internal: recovery
  // -----------------------------------------------------------------------

  /**
   * Recover from a WASM crash by terminating the corrupted worker, spinning
   * up a fresh one, and replaying the last `loadModel` so the next inference
   * call works transparently.
   */
  private async recover(): Promise<void> {
    if (!this._lastModelParams) {
      throw new Error(
        '[VLMWorkerBridge] Cannot recover: no model parameters cached',
      );
    }

    logger.info('Recovering from VLM WASM crash…');
    const params = this._lastModelParams;
    this.terminate();
    await this.init();
    await this.loadModel(params);
    this._needsRecovery = false;
    logger.info('VLM Worker recovery complete');
  }

  // -----------------------------------------------------------------------
  // Internal: worker spawning + RPC
  // -----------------------------------------------------------------------

  private spawnWorker(): void {
    const url =
      this._workerUrl ?? new URL('../workers/vlm-worker.js', import.meta.url);
    this.worker = new Worker(url, { type: 'module' });
    this.worker.onmessage = this.handleMessage.bind(this);
    this.worker.onerror = (e) => {
      logger.error(`Worker error: ${e.message ?? e}`);
    };
  }

  private async initWithUrl(wasmJsUrl: string, useWebGPU: boolean): Promise<void> {
    this.spawnWorker();
    await this.send('init', { wasmJsUrl, useWebGPU });
    this._initialized = true;
  }

  private send(
    type: string,
    payload: unknown,
    transferables: Transferable[] = [],
  ): Promise<unknown> {
    return new Promise((resolve, reject) => {
      if (!this.worker) {
        reject(new Error('[VLMWorkerBridge] Worker not initialised'));
        return;
      }
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ type, id, payload }, transferables);
    });
  }

  private handleMessage(e: MessageEvent<VLMWorkerResponse>): void {
    const { id, type, payload } = e.data;

    if (type === 'progress') {
      const stage = (payload as { stage: string }).stage;
      this.emitProgress(stage);
      return;
    }

    const pending = this.pending.get(id);
    if (!pending) return;
    this.pending.delete(id);

    if (type === 'error') {
      pending.reject(new Error((payload as { message: string }).message));
    } else {
      pending.resolve(payload);
    }
  }
}
