/**
 * RunAnywhere Web SDK - VLM Worker Bridge
 *
 * Main-thread proxy for the VLM Web Worker. All VLM inference runs off the
 * main thread so the camera, UI animations, and event loop stay responsive.
 *
 * Usage:
 *   ```typescript
 *   import { VLMWorkerBridge } from '@runanywhere/web';
 *
 *   const vlm = VLMWorkerBridge.shared;
 *   await vlm.init();
 *   await vlm.loadModel({ ... });
 *   const result = await vlm.process(rgbPixels, width, height, prompt, { maxTokens: 100 });
 *   ```
 */

import { SDKLogger } from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * RPC commands sent from the main thread to the Worker.
 */
export type VLMWorkerCommand =
  | {
      type: 'init'; id: number; payload: {
        /** URL to the WASM glue JS (racommons.js or racommons-webgpu.js) */
        wasmJsUrl: string;
        /** Whether the loaded module is the WebGPU variant */
        useWebGPU?: boolean;
      };
    }
  | {
      type: 'load-model'; id: number; payload: {
        modelOpfsKey: string; modelFilename: string;
        mmprojOpfsKey: string; mmprojFilename: string;
        modelId: string; modelName: string;
        /** Optional: raw model data when OPFS doesn't have it (memory-cache fallback). */
        modelData?: ArrayBuffer;
        /** Optional: raw mmproj data when OPFS doesn't have it. */
        mmprojData?: ArrayBuffer;
      };
    }
  | {
      type: 'process'; id: number; payload: {
        rgbPixels: ArrayBuffer; width: number; height: number;
        prompt: string; maxTokens: number; temperature: number;
      };
    }
  | { type: 'cancel'; id: number }
  | { type: 'unload'; id: number };

/**
 * Result of a VLM inference operation.
 */
export interface VLMWorkerResult {
  text: string;
  totalTokens: number;
  promptTokens: number;
  completionTokens: number;
  imageTokens: number;
}

/**
 * RPC responses from the Worker to the main thread.
 */
export type VLMWorkerResponse =
  | { id: number; type: 'result'; payload: any }
  | { id: number; type: 'error'; payload: { message: string } }
  | { id: number; type: 'progress'; payload: { stage: string } };

/**
 * Parameters for loading a VLM model in the Worker.
 */
export interface VLMLoadModelParams {
  modelOpfsKey: string;
  modelFilename: string;
  mmprojOpfsKey: string;
  mmprojFilename: string;
  modelId: string;
  modelName: string;
  /** Optional: raw model data when OPFS doesn't have it (memory-cache fallback). */
  modelData?: ArrayBuffer;
  /** Optional: raw mmproj data when OPFS doesn't have it. */
  mmprojData?: ArrayBuffer;
}

/**
 * Options for VLM image processing.
 */
export interface VLMProcessOptions {
  maxTokens?: number;
  temperature?: number;
}

/**
 * Callback for VLM progress updates (model loading stages, etc.).
 */
export type ProgressListener = (stage: string) => void;

// ---------------------------------------------------------------------------
// Bridge
// ---------------------------------------------------------------------------

const logger = new SDKLogger('VLMWorkerBridge');

/**
 * VLMWorkerBridge - Main-thread proxy for VLM Web Worker inference.
 *
 * Manages the lifecycle of a dedicated Web Worker that runs VLM inference
 * in its own WASM instance. Provides:
 *   - RPC protocol with message ID tracking and promise correlation
 *   - Auto-recovery from WASM crashes (OOB, stack overflow, etc.)
 *   - Progress listeners for model loading stages
 *   - Transferable pixel data for zero-copy image transfer
 */
export class VLMWorkerBridge {
  // ---- Singleton ----
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
  private pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  private _isInitialized = false;
  private _isModelLoaded = false;
  private _progressListeners: ProgressListener[] = [];
  /** Saved for auto-recovery after WASM crash */
  private _lastModelParams: VLMLoadModelParams | null = null;
  private _needsRecovery = false;

  /**
   * Optional: the app can provide a custom Worker URL or factory.
   * If not set, the bridge uses the bundled SDK worker entry point.
   */
  private _workerUrl: URL | string | null = null;

  get isInitialized(): boolean { return this._isInitialized; }
  get isModelLoaded(): boolean { return this._isModelLoaded; }

  // ---- Configuration ----

  /**
   * Set a custom Worker URL.
   *
   * By default the bridge creates a Worker using the SDK's bundled entry point
   * (`workers/vlm-worker.js`). Apps that need to customise the Worker location
   * (e.g. different deploy path, or a worker that wraps the runtime) can call
   * this before `init()`.
   */
  set workerUrl(url: URL | string) {
    this._workerUrl = url;
  }

  // ---- Progress ----

  /**
   * Subscribe to progress updates from the Worker.
   * Returns an unsubscribe function.
   */
  onProgress(fn: ProgressListener): () => void {
    this._progressListeners.push(fn);
    return () => {
      this._progressListeners = this._progressListeners.filter((l) => l !== fn);
    };
  }

  private emitProgress(stage: string): void {
    for (const fn of this._progressListeners) fn(stage);
  }

  // ---- Lifecycle ----

  /**
   * Initialize the Worker and its WASM instance.
   * Must be called once before loadModel/process.
   *
   * Reads the WASM URL and acceleration mode from LlamaCppBridge internally —
   * the app does not need to pass these.
   *
   * @param wasmJsUrl - Optional explicit URL for the WASM glue JS.
   *                    When omitted, the SDK's LlamaCppBridge.wasmUrl is used
   *                    so the worker loads the exact same variant (WebGPU or CPU)
   *                    that the main thread successfully loaded.
   */
  async init(wasmJsUrl?: string): Promise<void> {
    if (this._isInitialized) return;

    // All acceleration logic lives in the SDK's LlamaCppBridge.
    // We just read the decision it already made.
    const bridge = LlamaCppBridge.shared;
    const useWebGPU = bridge.accelerationMode === 'webgpu';
    const resolvedUrl = wasmJsUrl ?? bridge.wasmUrl ?? '';

    if (!resolvedUrl) {
      throw new Error('[VLMWorkerBridge] SDK not initialized — no WASM URL available');
    }

    // Create the Worker
    const workerUrl = this._workerUrl ?? new URL('../workers/vlm-worker.js', import.meta.url);
    this.worker = new Worker(workerUrl, { type: 'module' });

    this.worker.onmessage = this.handleMessage.bind(this);
    this.worker.onerror = (e) => {
      logger.error(`Worker error: ${e.message ?? e}`);
    };

    await this.send('init', { wasmJsUrl: resolvedUrl, useWebGPU });
    this._isInitialized = true;
    logger.info(`Worker initialized (${useWebGPU ? 'WebGPU' : 'CPU'})`);
  }

  /**
   * Load a VLM model in the Worker's WASM instance.
   *
   * Normally the Worker reads model files directly from OPFS (zero-copy).
   * When OPFS quota is exceeded and models are only in the main-thread memory
   * cache, the data is transferred via postMessage (still zero-copy via
   * Transferable ArrayBuffers).
   */
  async loadModel(params: VLMLoadModelParams): Promise<void> {
    if (!this._isInitialized) {
      await this.init();
    }

    // Transfer data buffers when provided (zero-copy to Worker)
    const transferables: Transferable[] = [];
    if (params.modelData) transferables.push(params.modelData);
    if (params.mmprojData) transferables.push(params.mmprojData);

    await this.send('load-model', params, transferables);
    this._isModelLoaded = true;
    this._lastModelParams = params;
    this._needsRecovery = false;
    logger.info(`Model loaded: ${params.modelId}`);
  }

  /**
   * Process an image with the VLM.
   * Returns a promise that resolves when inference is complete.
   * The main thread stays responsive during processing.
   *
   * The pixel buffer is transferred (zero-copy) to the Worker.
   */
  async process(
    rgbPixels: Uint8Array,
    width: number,
    height: number,
    prompt: string,
    options: VLMProcessOptions = {},
  ): Promise<VLMWorkerResult> {
    // Auto-recover from previous WASM crash (OOB, etc.)
    if (this._needsRecovery) {
      await this.recover();
    }

    if (!this._isModelLoaded) {
      throw new Error('No VLM model loaded in Worker. Call loadModel() first.');
    }

    // Transfer the pixel buffer (zero-copy to Worker)
    const buffer = rgbPixels.buffer.slice(
      rgbPixels.byteOffset,
      rgbPixels.byteOffset + rgbPixels.byteLength,
    );

    try {
      return await this.send(
        'process',
        {
          rgbPixels: buffer,
          width,
          height,
          prompt,
          maxTokens: options.maxTokens ?? 200,
          temperature: options.temperature ?? 0.7,
        },
        [buffer],
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // WASM runtime errors (OOB, stack overflow) leave the instance corrupted.
      // Mark for recovery so the next call creates a fresh Worker.
      if (msg.includes('memory access out of bounds') ||
          msg.includes('unreachable') ||
          msg.includes('RuntimeError')) {
        logger.warning('WASM crash detected, will recover on next call');
        this._needsRecovery = true;
      }
      throw err;
    }
  }

  /**
   * Recover from a WASM crash by terminating the old Worker,
   * creating a fresh one, and reloading the model.
   */
  private async recover(): Promise<void> {
    if (!this._lastModelParams) {
      throw new Error('Cannot recover: no model params saved');
    }

    logger.info('Recovering from WASM crash...');
    const params = this._lastModelParams;

    // Destroy old worker completely
    this.terminate();

    // Reinitialize fresh worker + reload model
    await this.init();
    await this.loadModel(params);
    logger.info('Recovery complete');
  }

  /** Cancel in-progress VLM generation. */
  cancel(): void {
    if (this.worker) {
      this.worker.postMessage({ type: 'cancel', id: -2 });
    }
  }

  /** Unload the VLM model. */
  async unloadModel(): Promise<void> {
    if (!this._isModelLoaded) return;
    await this.send('unload', {});
    this._isModelLoaded = false;
  }

  /**
   * Terminate the Worker entirely.
   *
   * Rejects any in-flight RPC promises so callers aren't left hanging,
   * then terminates the underlying Web Worker.
   */
  terminate(): void {
    // Reject all pending RPC calls so callers don't hang forever
    for (const [, { reject }] of this.pending) {
      reject(new Error('VLM Worker terminated'));
    }
    this.pending.clear();

    this.worker?.terminate();
    this.worker = null;
    this._isInitialized = false;
    this._isModelLoaded = false;
  }

  // ---- Internal RPC ----

  /* eslint-disable @typescript-eslint/no-explicit-any */
  private send(type: string, payload: any, transferables?: Transferable[]): Promise<any> {
    return new Promise((resolve, reject) => {
      if (!this.worker) {
        reject(new Error('VLM Worker not initialized'));
        return;
      }

      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      this.worker.postMessage({ type, id, payload }, transferables ?? []);
    });
  }

  private handleMessage(e: MessageEvent<VLMWorkerResponse>): void {
    const { id, type, payload } = e.data;

    // Progress messages (id=-1) are not RPC responses
    if (type === 'progress') {
      this.emitProgress((payload as any).stage);
      return;
    }

    const pending = this.pending.get(id);
    if (!pending) return;
    this.pending.delete(id);

    if (type === 'error') {
      pending.reject(new Error((payload as any).message));
    } else {
      pending.resolve(payload);
    }
  }
  /* eslint-enable @typescript-eslint/no-explicit-any */
}
