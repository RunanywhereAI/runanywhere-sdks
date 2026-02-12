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

import { SDKError, SDKErrorCode } from './ErrorTypes';
import { SDKLogger } from './SDKLogger';

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
  _SherpaOnnxGetOnlineStreamResultAsJson: (stream: number) => number;
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
      const moduleUrl = wasmUrl ?? new URL('../../wasm/sherpa/sherpa-onnx-glue.js', import.meta.url).href;
      const { default: createModule } = await import(/* @vite-ignore */ moduleUrl);

      this._module = await createModule({
        print: (text: string) => logger.debug(text),
        printErr: (text: string) => logger.warning(text),
      }) as SherpaONNXModule;

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
   * Ensure a directory exists in the sherpa-onnx Emscripten virtual FS.
   */
  ensureDir(path: string): void {
    const m = this.module;
    const parts = path.split('/').filter(Boolean);
    let current = '';
    for (const part of parts) {
      current += '/' + part;
      if (!m.FS.analyzePath(current).exists) {
        m.FS.mkdir(current);
      }
    }
  }

  /**
   * Write a file into the sherpa-onnx Emscripten virtual FS.
   * Used to stage model files before loading.
   */
  writeFile(path: string, data: Uint8Array): void {
    const dir = path.substring(0, path.lastIndexOf('/'));
    if (dir) this.ensureDir(dir);
    this.module.FS.writeFile(path, data);
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
