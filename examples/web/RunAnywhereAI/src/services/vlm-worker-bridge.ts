/**
 * VLM Worker Bridge
 *
 * Main-thread proxy for the VLM Web Worker. All VLM inference runs off the
 * main thread so the camera, UI animations, and event loop stay responsive.
 *
 * Usage:
 *   const vlm = VLMWorkerBridge.shared;
 *   await vlm.init();
 *   await vlm.loadModel({ ... });
 *   const result = await vlm.process(rgbPixels, width, height, prompt, { maxTokens: 100 });
 */

import type { VLMWorkerResult, VLMWorkerResponse } from '../workers/vlm-worker';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface VLMLoadModelParams {
  modelOpfsKey: string;
  modelFilename: string;
  mmprojOpfsKey: string;
  mmprojFilename: string;
  modelId: string;
  modelName: string;
}

export interface VLMProcessOptions {
  maxTokens?: number;
  temperature?: number;
}

export { VLMWorkerResult };

// ---------------------------------------------------------------------------
// Progress listener
// ---------------------------------------------------------------------------

type ProgressListener = (stage: string) => void;

// ---------------------------------------------------------------------------
// Bridge
// ---------------------------------------------------------------------------

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

  get isInitialized(): boolean { return this._isInitialized; }
  get isModelLoaded(): boolean { return this._isModelLoaded; }

  // ---- Progress ----

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
   */
  async init(wasmJsUrl?: string): Promise<void> {
    if (this._isInitialized) return;

    // Resolve the WASM JS URL (same logic as WASMBridge)
    const resolvedUrl = wasmJsUrl ?? this.resolveWasmUrl();

    // Create the Worker (Vite handles the bundling)
    this.worker = new Worker(
      new URL('../workers/vlm-worker.ts', import.meta.url),
      { type: 'module' },
    );

    this.worker.onmessage = this.handleMessage.bind(this);
    this.worker.onerror = (e) => {
      console.error('[VLMWorkerBridge] Worker error:', e);
    };

    await this.send('init', { wasmJsUrl: resolvedUrl });
    this._isInitialized = true;
    console.log('[VLMWorkerBridge] Worker initialized');
  }

  /**
   * Load a VLM model in the Worker's WASM instance.
   * The Worker reads model files directly from OPFS (zero-copy).
   */
  async loadModel(params: VLMLoadModelParams): Promise<void> {
    if (!this._isInitialized) {
      await this.init();
    }

    await this.send('load-model', params);
    this._isModelLoaded = true;
    console.log(`[VLMWorkerBridge] Model loaded: ${params.modelId}`);
  }

  /**
   * Process an image with the VLM.
   * Returns a promise that resolves when inference is complete.
   * The main thread stays responsive during processing.
   */
  async process(
    rgbPixels: Uint8Array,
    width: number,
    height: number,
    prompt: string,
    options: VLMProcessOptions = {},
  ): Promise<VLMWorkerResult> {
    if (!this._isModelLoaded) {
      throw new Error('No VLM model loaded in Worker. Call loadModel() first.');
    }

    // Transfer the pixel buffer (zero-copy to Worker)
    const buffer = rgbPixels.buffer.slice(
      rgbPixels.byteOffset,
      rgbPixels.byteOffset + rgbPixels.byteLength,
    );

    return this.send(
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

  /** Terminate the Worker entirely. */
  terminate(): void {
    this.worker?.terminate();
    this.worker = null;
    this._isInitialized = false;
    this._isModelLoaded = false;
    this.pending.clear();
  }

  // ---- Internal ----

  private resolveWasmUrl(): string {
    // The WASM JS glue file location relative to the SDK source
    // In Vite dev mode this resolves via /@fs/ prefix
    return new URL(
      '../../../../../sdk/runanywhere-web/packages/core/wasm/racommons.js',
      import.meta.url,
    ).href;
  }

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
}
