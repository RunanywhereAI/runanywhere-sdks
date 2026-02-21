/**
 * RunAnywhere Web SDK - Sherpa-ONNX WASM Bridge
 *
 * Loads the sherpa-onnx WASM module (separate from RACommons) and provides
 * typed access to the sherpa-onnx C API for:
 *   - STT (Speech-to-Text) via Whisper, Zipformer, Paraformer
 *   - TTS (Text-to-Speech) via Piper/VITS
 *   - VAD (Voice Activity Detection) via Silero
 *
 * Architecture:
 *   RACommons WASM handles LLM, VLM, Embeddings (llama.cpp)
 *   Sherpa-ONNX WASM handles STT, TTS, VAD (onnxruntime)
 *
 * The sherpa-onnx module is lazy-loaded on first use of STT/TTS/VAD.
 */

import { SDKError, SDKErrorCode, SDKLogger } from '@runanywhere/web';

const logger = new SDKLogger('SherpaONNX');

// ---------------------------------------------------------------------------
// Sherpa-ONNX Module Type
// ---------------------------------------------------------------------------

/**
 * Emscripten module interface for sherpa-onnx WASM.
 * Based on sherpa-onnx's wasm/nodejs C API exports.
 */
export interface SherpaONNXModule {
  // Emscripten runtime
  ccall: (ident: string, returnType: string | null, argTypes: string[], args: unknown[]) => unknown;
  cwrap: (ident: string, returnType: string | null, argTypes: string[]) => (...args: unknown[]) => unknown;
  _malloc: (size: number) => number;
  _free: (ptr: number) => void;
  setValue: (ptr: number, value: number, type: string) => void;
  getValue: (ptr: number, type: string) => number;
  UTF8ToString: (ptr: number) => string;
  stringToUTF8: (str: string, ptr: number, maxLen: number) => void;
  lengthBytesUTF8: (str: string) => number;
  HEAPU8: Uint8Array;
  HEAP16: Int16Array;
  HEAP32: Int32Array;
  HEAPF32: Float32Array;
  HEAPF64: Float64Array;
  FS: SherpaFS;

  // STT - Offline recognizer (Whisper, etc.)
  _SherpaOnnxCreateOfflineRecognizer: (configPtr: number) => number;
  _SherpaOnnxDestroyOfflineRecognizer: (handle: number) => void;
  _SherpaOnnxCreateOfflineStream: (handle: number) => number;
  _SherpaOnnxDestroyOfflineStream: (stream: number) => void;
  _SherpaOnnxAcceptWaveformOffline: (stream: number, sampleRate: number, samplesPtr: number, numSamples: number) => void;
  _SherpaOnnxDecodeOfflineStream: (handle: number, stream: number) => void;
  _SherpaOnnxGetOfflineStreamResultAsJson: (stream: number) => number;
  _SherpaOnnxDestroyOfflineStreamResultJson: (ptr: number) => void;

  // STT - Online recognizer (streaming)
  _SherpaOnnxCreateOnlineRecognizer: (configPtr: number) => number;
  _SherpaOnnxDestroyOnlineRecognizer: (handle: number) => void;
  _SherpaOnnxCreateOnlineStream: (handle: number) => number;
  _SherpaOnnxDestroyOnlineStream: (stream: number) => void;
  _SherpaOnnxOnlineStreamAcceptWaveform: (stream: number, sampleRate: number, samplesPtr: number, numSamples: number) => void;
  _SherpaOnnxIsOnlineStreamReady: (handle: number, stream: number) => number;
  _SherpaOnnxDecodeOnlineStream: (handle: number, stream: number) => void;
  _SherpaOnnxGetOnlineStreamResultAsJson: (handle: number, stream: number) => number;
  _SherpaOnnxDestroyOnlineStreamResultJson: (ptr: number) => void;
  _SherpaOnnxOnlineStreamInputFinished: (stream: number) => void;
  _SherpaOnnxOnlineStreamIsEndpoint: (handle: number, stream: number) => number;
  _SherpaOnnxOnlineStreamReset: (handle: number, stream: number) => void;

  // TTS
  _SherpaOnnxCreateOfflineTts: (configPtr: number) => number;
  _SherpaOnnxDestroyOfflineTts: (handle: number) => void;
  _SherpaOnnxOfflineTtsGenerate: (handle: number, textPtr: number, sid: number, speed: number) => number;
  _SherpaOnnxDestroyOfflineTtsGeneratedAudio: (audio: number) => void;
  _SherpaOnnxOfflineTtsSampleRate: (handle: number) => number;
  _SherpaOnnxOfflineTtsNumSpeakers: (handle: number) => number;

  // VAD
  _SherpaOnnxCreateVoiceActivityDetector: (configPtr: number, bufferSizeInSeconds: number) => number;
  _SherpaOnnxDestroyVoiceActivityDetector: (handle: number) => void;
  _SherpaOnnxVoiceActivityDetectorAcceptWaveform: (handle: number, samplesPtr: number, numSamples: number) => void;
  _SherpaOnnxVoiceActivityDetectorEmpty: (handle: number) => number;
  _SherpaOnnxVoiceActivityDetectorDetected: (handle: number) => number;
  _SherpaOnnxVoiceActivityDetectorPop: (handle: number) => void;
  _SherpaOnnxVoiceActivityDetectorFront: (handle: number) => number;
  _SherpaOnnxDestroySpeechSegment: (segment: number) => void;
  _SherpaOnnxVoiceActivityDetectorReset: (handle: number) => void;
  _SherpaOnnxVoiceActivityDetectorFlush: (handle: number) => void;

  // Memory helpers
  _CopyHeap?: (srcPtr: number, numBytes: number, dstPtr: number) => void;
}

interface SherpaFS {
  mkdir: (path: string) => void;
  writeFile: (path: string, data: Uint8Array | string) => void;
  readFile: (path: string) => Uint8Array;
  unlink: (path: string) => void;
  analyzePath: (path: string) => { exists: boolean };
}

// ---------------------------------------------------------------------------
// SherpaONNXBridge
// ---------------------------------------------------------------------------

/**
 * SherpaONNXBridge - Loads and manages the sherpa-onnx WASM module.
 *
 * Singleton that provides access to sherpa-onnx C API functions.
 * Lazy-loaded: only initializes when STT/TTS/VAD is first used.
 */
export class SherpaONNXBridge {
  private static _instance: SherpaONNXBridge | null = null;
  private _module: SherpaONNXModule | null = null;
  private _loaded = false;
  private _loading: Promise<void> | null = null;

  /**
   * Override the default URL to the sherpa-onnx-glue.js file.
   * Set this before any STT/TTS/VAD model is loaded.
   *
   * In a Vite app, resolve it like:
   * ```typescript
   * SherpaONNXBridge.shared.wasmUrl = new URL(
   *   '@runanywhere/web/wasm/sherpa/sherpa-onnx-glue.js',
   *   import.meta.url,
   * ).href;
   * ```
   */
  wasmUrl: string | null = null;

  static get shared(): SherpaONNXBridge {
    if (!SherpaONNXBridge._instance) {
      SherpaONNXBridge._instance = new SherpaONNXBridge();
    }
    return SherpaONNXBridge._instance;
  }

  get isLoaded(): boolean {
    return this._loaded && this._module !== null;
  }

  get module(): SherpaONNXModule {
    if (!this._module) {
      throw new SDKError(
        SDKErrorCode.WASMNotLoaded,
        'Sherpa-ONNX WASM not loaded. Call ensureLoaded() first.',
      );
    }
    return this._module;
  }

  /**
   * Ensure the sherpa-onnx WASM module is loaded.
   * Safe to call multiple times -- will only load once.
   *
   * @param wasmUrl - URL/path to the sherpa-onnx glue JS file.
   *                  Defaults to wasm/sherpa/sherpa-onnx-glue.js
   */
  async ensureLoaded(wasmUrl?: string): Promise<void> {
    if (this._loaded) return;

    // Prevent duplicate loading
    if (this._loading) {
      await this._loading;
      return;
    }

    this._loading = this._doLoad(wasmUrl);
    await this._loading;
    this._loading = null;
  }

  private async _doLoad(wasmUrl?: string): Promise<void> {
    logger.info('Loading Sherpa-ONNX WASM module...');

    try {
      const moduleUrl = wasmUrl ?? this.wasmUrl ?? new URL('../../wasm/sherpa/sherpa-onnx-glue.js', import.meta.url).href;
      const { default: createModule } = await import(/* @vite-ignore */ moduleUrl);

      // Derive the base URL for the .wasm binary
      const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);
      const wasmBinaryUrl = baseUrl + 'sherpa-onnx.wasm';

      // Pre-fetch the WASM binary to avoid Emscripten's sync XHR
      // (the Node.js-targeted build uses sync fetch which fails in browsers)
      logger.info(`Fetching sherpa-onnx WASM binary from ${wasmBinaryUrl}`);
      const wasmResponse = await fetch(wasmBinaryUrl);
      if (!wasmResponse.ok) {
        throw new Error(`Failed to fetch sherpa-onnx.wasm: ${wasmResponse.status} ${wasmResponse.statusText}`);
      }
      const wasmBinary = await wasmResponse.arrayBuffer();
      logger.info(`Sherpa-ONNX WASM binary fetched: ${(wasmBinary.byteLength / 1_000_000).toFixed(1)} MB`);

      // Use instantiateWasm for async compilation (Chrome blocks sync compile for >8MB).
      //
      // The sherpa-onnx glue JS was compiled with NODERAWFS but we patched it:
      //   1. ENVIRONMENT_IS_NODE = false → forces browser code paths
      //   2. NODERAWFS mounting skipped → FS uses MEMFS
      //   3. receiveInstance patched → re-assigns Module exports after wasmExports is set
      //
      // We pass noFSInit: true to skip FS.init() (which creates /dev/stdin etc.).
      // We don't need standard streams — only file operations for staging model files.
      // This ensures initRuntime() succeeds and the ready promise resolves.
      //
      // We track a separate wasmReady promise so that if WebAssembly.instantiate
      // itself fails, we get the actual error instead of a generic timeout.
      let resolveWasm: () => void;
      let rejectWasm: (err: Error) => void;
      const wasmReady = new Promise<void>((resolve, reject) => {
        resolveWasm = resolve;
        rejectWasm = reject;
      });

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const modOrPromise = createModule({
        noFSInit: true,
        print: (text: string) => logger.debug(text),
        printErr: (text: string) => logger.warning(text),
        wasmBinary,
        locateFile: (path: string) => baseUrl + path,
        instantiateWasm: (
          imports: WebAssembly.Imports,
          receiveInstance: (instance: WebAssembly.Instance, module: WebAssembly.Module) => void,
        ) => {
          WebAssembly.instantiate(wasmBinary, imports)
            .then((result) => {
              try {
                receiveInstance(result.instance, result.module);
                resolveWasm();
              } catch (err) {
                // receiveInstance may throw if initRuntime fails (e.g. FS errors).
                logger.warning(`receiveInstance completed with error: ${err}`);
                resolveWasm();
              }
            })
            .catch((err) => {
              const error = err instanceof Error ? err : new Error(String(err));
              logger.error(`WASM instantiation failed: ${error.message}`);
              rejectWasm(error);
            });
          return {}; // Indicates async instantiation
        },
      });

      // Wait for WASM instantiation + receiveInstance + initRuntime to complete.
      // With Patch 6 applied, createModule returns a Promise (resolved after initRuntime).
      // wasmReady resolves first (after receiveInstance), then initRuntime fires synchronously.
      const timeoutPromise = new Promise<void>((_, reject) => {
        setTimeout(() => reject(new Error('Sherpa-ONNX WASM module timed out after 30s')), 30_000);
      });
      await Promise.race([wasmReady, timeoutPromise]);

      // Resolve the module: Emscripten returns a Promise<Module> when using async WASM init.
      // Promise.resolve() is a no-op if modOrPromise is already the Module object.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const mod = await Promise.resolve(modOrPromise) as SherpaONNXModule;
      this._module = mod;

      // Verify critical exports are available (set by our patched receiveInstance)
      if (typeof mod._malloc !== 'function') {
        const available = ['_malloc', '_free', '_SherpaOnnxCreateOfflineRecognizer']
          .map(fn => `${fn}: ${typeof (mod as unknown as Record<string, unknown>)[fn]}`)
          .join(', ');
        throw new Error(`WASM exports not available after initialization. Available: ${available}`);
      }

      this._loaded = true;
      logger.info('Sherpa-ONNX WASM module loaded successfully');
    } catch (error) {
      this._module = null;
      this._loaded = false;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load Sherpa-ONNX WASM: ${message}`);
      throw new SDKError(
        SDKErrorCode.WASMLoadFailed,
        `Failed to load Sherpa-ONNX WASM module: ${message}. ` +
        'Build with: ./wasm/scripts/build-sherpa-onnx.sh',
      );
    }
  }

  // -----------------------------------------------------------------------
  // Filesystem Helpers
  // -----------------------------------------------------------------------

  /**
   * Get the Emscripten FS object from the module.
   * Handles both direct FS property and module-level helper functions.
   */
  private getFS(): SherpaFS {
    const m = this.module;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const mod = m as any;

    // First try direct FS property
    if (m.FS && typeof m.FS.mkdir === 'function') {
      return m.FS;
    }

    // Fallback: construct FS-like interface from Emscripten module-level helpers
    if (typeof mod.FS_createPath === 'function') {
      return {
        mkdir: (p: string) => {
          const parent = p.substring(0, p.lastIndexOf('/')) || '/';
          const name = p.substring(p.lastIndexOf('/') + 1);
          mod.FS_createPath(parent, name, true, true);
        },
        writeFile: (p: string, data: Uint8Array | string) => {
          const dir = p.substring(0, p.lastIndexOf('/')) || '/';
          const name = p.substring(p.lastIndexOf('/') + 1);
          try { mod.FS_unlink(p); } catch { /* file may not exist */ }
          mod.FS_createDataFile(dir, name, data, true, true, true);
        },
        readFile: (p: string) => mod.FS_readFile(p),
        unlink: (p: string) => mod.FS_unlink(p),
        analyzePath: (p: string) => {
          try {
            mod.FS_readFile(p);
            return { exists: true };
          } catch {
            return { exists: false };
          }
        },
      };
    }

    throw new SDKError(SDKErrorCode.WASMNotLoaded, 'Sherpa-ONNX FS not available');
  }

  /**
   * Ensure a directory exists in the sherpa-onnx Emscripten virtual FS.
   */
  ensureDir(path: string): void {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const mod = this.module as any;

    if (typeof mod.FS_createPath === 'function') {
      // Use FS_createPath which creates all intermediate directories
      mod.FS_createPath('/', path.replace(/^\//, ''), true, true);
      return;
    }

    // Fallback to FS.mkdir
    const fs = this.getFS();
    const parts = path.split('/').filter(Boolean);
    let current = '';
    for (const part of parts) {
      current += '/' + part;
      if (!fs.analyzePath(current).exists) {
        fs.mkdir(current);
      }
    }
  }

  /**
   * Write a file into the sherpa-onnx Emscripten virtual FS.
   * Used to stage model files before loading.
   *
   * Prefers FS_createDataFile over FS.writeFile for reliability —
   * the module was compiled with NODERAWFS which can leave FS.writeFile
   * in a broken state even after our browser patches.
   */
  writeFile(path: string, data: Uint8Array): void {
    const dir = path.substring(0, path.lastIndexOf('/'));
    if (dir) this.ensureDir(dir);

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const mod = this.module as any;

    // Prefer FS_createDataFile — it creates the file node and writes data
    // in one shot, avoiding potential issues with FS.open / FS.write on
    // NODERAWFS-patched modules.
    if (typeof mod.FS_createDataFile === 'function') {
      const parentDir = dir || '/';
      const filename = path.substring(path.lastIndexOf('/') + 1);

      // Remove existing file first (FS_createDataFile throws if it exists)
      try {
        if (typeof mod.FS_unlink === 'function') {
          mod.FS_unlink(path);
        }
      } catch {
        // File doesn't exist — that's fine
      }

      mod.FS_createDataFile(parentDir, filename, data, true, true, false);
      logger.debug(`Wrote ${data.length} bytes to sherpa FS: ${path}`);
      return;
    }

    // Fallback to FS.writeFile
    const fs = this.getFS();
    fs.writeFile(path, data);
    logger.debug(`Wrote ${data.length} bytes to sherpa FS: ${path}`);
  }

  /**
   * Download a file from a URL and write it to the sherpa-onnx FS.
   */
  async downloadAndWrite(
    url: string,
    fsPath: string,
    onProgress?: (loaded: number, total: number) => void,
  ): Promise<void> {
    logger.info(`Downloading ${url} -> ${fsPath}`);

    const response = await fetch(url);
    if (!response.ok) {
      throw new SDKError(
        SDKErrorCode.NetworkError,
        `Failed to download ${url}: ${response.status} ${response.statusText}`,
      );
    }

    const contentLength = Number(response.headers.get('content-length') ?? 0);
    const reader = response.body?.getReader();

    if (!reader) {
      // Fallback: read all at once
      const buffer = await response.arrayBuffer();
      this.writeFile(fsPath, new Uint8Array(buffer));
      return;
    }

    // Stream download with progress
    const chunks: Uint8Array[] = [];
    let loaded = 0;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      loaded += value.length;
      onProgress?.(loaded, contentLength);
    }

    // Combine chunks
    const combined = new Uint8Array(loaded);
    let offset = 0;
    for (const chunk of chunks) {
      combined.set(chunk, offset);
      offset += chunk.length;
    }

    this.writeFile(fsPath, combined);
  }

  // -----------------------------------------------------------------------
  // String Helpers
  // -----------------------------------------------------------------------

  allocString(str: string): number {
    const m = this.module;
    const len = m.lengthBytesUTF8(str) + 1;
    const ptr = m._malloc(len);
    m.stringToUTF8(str, ptr, len);
    return ptr;
  }

  readString(ptr: number): string {
    if (ptr === 0) return '';
    return this.module.UTF8ToString(ptr);
  }

  free(ptr: number): void {
    if (ptr !== 0) this.module._free(ptr);
  }

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  shutdown(): void {
    this._module = null;
    this._loaded = false;
    this._loading = null;
    SherpaONNXBridge._instance = null;
    logger.info('Sherpa-ONNX bridge shut down');
  }
}
