/**
 * LlamaCppBridge - Independent WASM module bridge for the llama.cpp backend
 *
 * Loads racommons-llamacpp.wasm (which contains rac_commons + llama.cpp)
 * as a fully independent WASM module with its own Emscripten runtime,
 * linear memory, and virtual filesystem.
 *
 * Follows the same pattern as SherpaONNXBridge in @runanywhere/web-onnx:
 *   - Singleton with lazy loading
 *   - Dynamic import of glue JS + fetch of .wasm binary
 *   - Async WebAssembly.instantiate
 *   - Own MEMFS for model files
 *   - Platform adapter registration
 *   - rac_init() + backend registration
 *
 * This module is completely independent from any core WASM — the core
 * package (@runanywhere/web) is pure TypeScript.
 */

import { SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType, SDKEnvironment, RunAnywhere } from '@runanywhere/web';
import type { AccelerationMode } from '@runanywhere/web';
import { getDeviceInfo } from '@runanywhere/web';
import { PlatformAdapter } from './PlatformAdapter';
import { AnalyticsEventsBridge } from './AnalyticsEventsBridge';
import { TelemetryService } from './TelemetryService';

const logger = new SDKLogger('LlamaCppBridge');

// ---------------------------------------------------------------------------
// Module Type
// ---------------------------------------------------------------------------

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Emscripten module interface for the racommons-llamacpp WASM.
 * Contains both core RACommons functions and llama.cpp backend functions.
 */
export interface LlamaCppModule {
  // Emscripten runtime
  ccall: (ident: string, returnType: string | null, argTypes: string[], args: unknown[], opts?: object) => unknown;
  cwrap: (ident: string, returnType: string | null, argTypes: string[]) => (...args: unknown[]) => unknown;
  addFunction: (func: (...args: number[]) => number | void, signature: string) => number;
  removeFunction: (ptr: number) => void;
  _malloc: (size: number) => number;
  _free: (ptr: number) => void;
  setValue: (ptr: number, value: number, type: string) => void;
  getValue: (ptr: number, type: string) => number;
  UTF8ToString: (ptr: number, maxBytesToRead?: number) => string;
  stringToUTF8: (str: string, outPtr: number, maxBytesToWrite: number) => void;
  lengthBytesUTF8: (str: string) => number;
  HEAPU8?: Uint8Array;
  HEAPF32?: Float32Array;

  // Core
  _rac_init: (configPtr: number) => number;
  _rac_shutdown: () => void;
  _rac_wasm_ping: () => number;
  _rac_wasm_sizeof_platform_adapter: () => number;
  _rac_wasm_sizeof_config: () => number;
  _rac_set_platform_adapter: (adapterPtr: number) => number;
  _rac_error_message: (code: number) => number;

  // Backend registration
  _rac_backend_llamacpp_register?: () => number;
  _rac_backend_llamacpp_vlm_register?: () => number;

  // LLM Component
  _rac_llm_component_create: (outHandlePtr: number) => number;
  _rac_llm_component_load_model: (handle: number, pathPtr: number, idPtr: number, namePtr: number) => number;
  _rac_llm_component_unload: (handle: number) => number;
  _rac_llm_component_generate: (handle: number, promptPtr: number, optionsPtr: number, outResultPtr: number) => number;
  _rac_llm_component_generate_stream: (
    handle: number, promptPtr: number, optionsPtr: number,
    tokenCb: number, completeCb: number, errorCb: number, userData: number,
  ) => number;
  _rac_llm_component_cancel: (handle: number) => number;
  _rac_llm_component_destroy: (handle: number) => void;
  _rac_llm_component_is_loaded: (handle: number) => number;
  _rac_llm_component_get_model_id: (handle: number) => number;
  _rac_llm_result_free: (resultPtr: number) => void;

  // VLM Component
  _rac_vlm_component_create?: (outHandlePtr: number) => number;
  _rac_vlm_component_load_model?: (handle: number, modelPath: number, mmprojPath: number, modelId: number, modelName: number) => number;
  _rac_vlm_component_process?: (handle: number, imagePtr: number, promptPtr: number, optionsPtr: number, resultPtr: number) => number;
  _rac_vlm_component_destroy?: (handle: number) => void;
  _rac_vlm_component_cancel?: (handle: number) => void;
  _rac_vlm_result_free?: (resultPtr: number) => void;

  // Sizeof / offset helpers
  _rac_wasm_sizeof_llm_options: () => number;
  _rac_wasm_sizeof_llm_result: () => number;
  _rac_wasm_sizeof_vlm_image: () => number;
  _rac_wasm_sizeof_vlm_options: () => number;
  _rac_wasm_sizeof_vlm_result: () => number;
  _rac_wasm_sizeof_structured_output_config: () => number;
  _rac_wasm_sizeof_embeddings_options: () => number;
  _rac_wasm_sizeof_embeddings_result: () => number;
  _rac_wasm_sizeof_diffusion_options: () => number;
  _rac_wasm_sizeof_diffusion_result: () => number;
  _rac_wasm_create_llm_options_default: () => number;

  // Structured Output
  _rac_structured_output_prepare_prompt?: (promptPtr: number, schemaPtr: number) => number;
  _rac_structured_output_validate?: (textPtr: number, schemaPtr: number) => number;

  // Embeddings
  _rac_embeddings_component_create?: (outHandlePtr: number) => number;

  // Diffusion
  _rac_diffusion_component_create?: (outHandlePtr: number) => number;

  // Tool Calling
  _rac_tool_call_parse?: (textPtr: number, outResultPtr: number) => number;

  // Telemetry Manager
  _rac_telemetry_manager_create?: (env: number, deviceIdPtr: number, platformPtr: number, sdkVersionPtr: number) => number;
  _rac_telemetry_manager_destroy?: (handle: number) => void;
  _rac_telemetry_manager_set_device_info?: (handle: number, modelPtr: number, osVersionPtr: number) => void;
  _rac_telemetry_manager_set_http_callback?: (handle: number, callbackPtr: number, userData: number) => void;
  _rac_telemetry_manager_track_analytics?: (handle: number, eventType: number, dataPtr: number) => number;
  _rac_telemetry_manager_flush?: (handle: number) => number;
  _rac_telemetry_manager_http_complete?: (handle: number, success: number, responsePtr: number, errorPtr: number) => void;

  // Analytics Events
  _rac_analytics_events_set_callback?: (callbackPtr: number, userData: number) => number;
  _rac_analytics_events_has_callback?: () => number;

  // Platform Emit Helpers (STT/TTS/VAD/Download — called from TypeScript via ccall)
  _rac_analytics_emit_stt_model_load_completed?: (modelIdPtr: number, modelNamePtr: number, durationMs: number, framework: number) => void;
  _rac_analytics_emit_stt_model_load_failed?: (modelIdPtr: number, errorCode: number, errorMsgPtr: number) => void;
  _rac_analytics_emit_stt_transcription_completed?: (
    transcriptionIdPtr: number, modelIdPtr: number, textPtr: number, confidence: number,
    durationMs: number, audioLengthMs: number, audioSizeBytes: number, wordCount: number,
    realTimeFactor: number, languagePtr: number, sampleRate: number, framework: number,
  ) => void;
  _rac_analytics_emit_stt_transcription_failed?: (transcriptionIdPtr: number, modelIdPtr: number, errorCode: number, errorMsgPtr: number) => void;
  _rac_analytics_emit_tts_voice_load_completed?: (modelIdPtr: number, modelNamePtr: number, durationMs: number, framework: number) => void;
  _rac_analytics_emit_tts_voice_load_failed?: (modelIdPtr: number, errorCode: number, errorMsgPtr: number) => void;
  _rac_analytics_emit_tts_synthesis_completed?: (
    synthesisIdPtr: number, modelIdPtr: number, characterCount: number,
    audioDurationMs: number, audioSizeBytes: number, processingDurationMs: number,
    charactersPerSecond: number, sampleRate: number, framework: number,
  ) => void;
  _rac_analytics_emit_tts_synthesis_failed?: (synthesisIdPtr: number, modelIdPtr: number, errorCode: number, errorMsgPtr: number) => void;
  _rac_analytics_emit_vad_speech_started?: () => void;
  _rac_analytics_emit_vad_speech_ended?: (speechDurationMs: number, energyLevel: number) => void;
  _rac_analytics_emit_model_download_started?: (modelIdPtr: number) => void;
  _rac_analytics_emit_model_download_completed?: (modelIdPtr: number, fileSizeBytes: number, durationMs: number) => void;
  _rac_analytics_emit_model_download_failed?: (modelIdPtr: number, errorMsgPtr: number) => void;

  // Dev Config (WASM wrappers)
  _rac_wasm_dev_config_is_available?: () => number;
  _rac_wasm_dev_config_get_supabase_url?: () => number;
  _rac_wasm_dev_config_get_supabase_key?: () => number;
  _rac_wasm_dev_config_get_build_token?: () => number;

  // Emscripten FS helpers
  FS_createPath?: (parent: string, path: string, canRead: boolean, canWrite: boolean) => void;
  FS_createDataFile?: (parent: string, name: string, data: Uint8Array, canRead: boolean, canWrite: boolean, canOwn: boolean) => void;
  FS_unlink?: (path: string) => void;

  // Generic index access for dynamic function lookups
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// LlamaCppBridge
// ---------------------------------------------------------------------------

export class LlamaCppBridge {
  private static _instance: LlamaCppBridge | null = null;
  private _module: LlamaCppModule | null = null;
  private _loaded = false;
  private _loading: Promise<void> | null = null;
  private _accelerationMode: AccelerationMode = 'cpu';
  private _platformAdapter: PlatformAdapter | null = null;
  private _analyticsEventsBridge: AnalyticsEventsBridge | null = null;
  private _telemetryService: TelemetryService | null = null;

  /** Override the default URL to the racommons-llamacpp.js glue file. */
  wasmUrl: string | null = null;
  /** Override the URL for the WebGPU variant. */
  webgpuWasmUrl: string | null = null;

  static get shared(): LlamaCppBridge {
    if (!LlamaCppBridge._instance) {
      LlamaCppBridge._instance = new LlamaCppBridge();
    }
    return LlamaCppBridge._instance;
  }

  get isLoaded(): boolean {
    return this._loaded && this._module !== null;
  }

  get module(): LlamaCppModule {
    if (!this._module) {
      throw new SDKError(
        SDKErrorCode.WASMNotLoaded,
        'LlamaCpp WASM not loaded. Call LlamaCPP.register() first.',
      );
    }
    return this._module;
  }

  get accelerationMode(): AccelerationMode {
    return this._accelerationMode;
  }

  // -----------------------------------------------------------------------
  // Loading
  // -----------------------------------------------------------------------

  async ensureLoaded(acceleration: 'auto' | 'webgpu' | 'cpu' = 'auto'): Promise<void> {
    if (this._loaded) return;
    if (this._loading) {
      await this._loading;
      return;
    }
    this._loading = this._doLoad(acceleration);
    try {
      await this._loading;
    } finally {
      this._loading = null;
    }
  }

  private async _doLoad(acceleration: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
    logger.info('Loading LlamaCpp WASM module...');

    try {
      // Determine acceleration mode
      const useWebGPU = acceleration === 'webgpu' ||
        (acceleration === 'auto' && await this.detectWebGPUWithJSPI());
      this._accelerationMode = useWebGPU ? 'webgpu' : 'cpu';

      // Select module URL
      const moduleUrl = useWebGPU
        ? (this.webgpuWasmUrl ?? new URL('../../wasm/racommons-llamacpp-webgpu.js', import.meta.url).href)
        : (this.wasmUrl ?? new URL('../../wasm/racommons-llamacpp.js', import.meta.url).href);

      logger.info(`Loading ${useWebGPU ? 'WebGPU' : 'CPU'} variant: ${moduleUrl}`);

      // Persist the resolved URL so VLMWorkerBridge (and others) can read it
      if (useWebGPU) {
        this.webgpuWasmUrl = moduleUrl;
      }
      this.wasmUrl = moduleUrl;

      // Dynamic import of Emscripten glue JS
      const { default: createModule } = await import(/* @vite-ignore */ moduleUrl);

      // Instantiate the WASM module
      this._module = await createModule({
        print: (text: string) => logger.info(text),
        printErr: (text: string) => logger.error(text),
      }) as LlamaCppModule;

      // Verify module loaded
      const pingResult = this._module._rac_wasm_ping();
      const ping = typeof pingResult === 'object' && pingResult !== null && 'then' in pingResult
        ? await (pingResult as unknown as Promise<number>)
        : pingResult as number;
      if (ping !== 42) {
        throw new Error(`WASM ping failed: expected 42, got ${ping}`);
      }

      // Register platform adapter (browser callbacks for logging, file ops, etc.)
      this._platformAdapter = new PlatformAdapter();
      this._platformAdapter.register();

      // Initialize RACommons core within this WASM module
      await this.initRACommons(this._platformAdapter.getAdapterPtr());

      // Register the llama.cpp backend
      await this.registerBackend();

      // Initialize analytics events bridge (subscribe to C++ events → TypeScript EventBus)
      this._analyticsEventsBridge = new AnalyticsEventsBridge();

      // Initialize telemetry service (C++ telemetry manager → browser fetch)
      this._telemetryService = TelemetryService.shared;
      const deviceInfo = await getDeviceInfo();
      const environment = RunAnywhere.environment ?? SDKEnvironment.Production;
      await this._telemetryService.initialize(this._module!, environment, deviceInfo);

      // Wire analytics bridge: forwards C++ events to EventBus + TelemetryService
      this._analyticsEventsBridge.register(
        this._module!,
        (eventType, dataPtr) => this._telemetryService?.trackAnalyticsEvent(eventType, dataPtr),
      );

      this._loaded = true;
      logger.info(`LlamaCpp WASM module loaded successfully (${this._accelerationMode})`);

      EventBus.shared.emit('llamacpp.wasmLoaded', SDKEventType.Initialization, {
        accelerationMode: this._accelerationMode,
      });
    } catch (error) {
      // WebGPU fallback to CPU
      if (this._accelerationMode === 'webgpu' && acceleration === 'auto') {
        const reason = error instanceof Error ? error.message : String(error);
        logger.warning(`WebGPU WASM failed (${reason}), falling back to CPU`);
        this._module = null;
        this._loaded = false;
        this._accelerationMode = 'cpu';
        return this._doLoad('cpu');
      }

      this._module = null;
      this._loaded = false;
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to load LlamaCpp WASM: ${message}`);
      throw new SDKError(
        SDKErrorCode.WASMLoadFailed,
        `Failed to load LlamaCpp WASM module: ${message}`,
      );
    }
  }

  private async initRACommons(adapterPtr: number): Promise<void> {
    const m = this._module!;

    // Create rac_config_t
    const configSize = m._rac_wasm_sizeof_config();
    const configPtr = m._malloc(configSize);
    for (let i = 0; i < configSize; i++) {
      m.setValue(configPtr + i, 0, 'i8');
    }

    // Set platform_adapter pointer (offset 0)
    m.setValue(configPtr, adapterPtr, '*');
    // Set log_level (offset queried at runtime)
    const logLevelOffset = this.wasmOffsetOf('config_log_level');
    m.setValue(configPtr + logLevelOffset, 2, 'i32'); // INFO level

    const result = await (m.ccall('rac_init', 'number', ['number'], [configPtr], { async: true }) as unknown as Promise<number>);
    m._free(configPtr);

    if (result !== 0) {
      const errMsg = this.readString(m._rac_error_message(result));
      throw new Error(`rac_init failed in LlamaCpp module: ${errMsg}`);
    }

    logger.info('RACommons initialized within LlamaCpp WASM module');
  }

  private async registerBackend(): Promise<void> {
    const m = this._module!;

    if (typeof m._rac_backend_llamacpp_register === 'function') {
      const result = await (m.ccall(
        'rac_backend_llamacpp_register', 'number', [], [], { async: true },
      ) as unknown as Promise<number>);
      if (result === 0) {
        logger.info('llama.cpp C++ backend registered');
      } else {
        logger.warning(`llama.cpp backend registration returned: ${result}`);
      }
    }

    if (typeof m._rac_backend_llamacpp_vlm_register === 'function') {
      const result = await (m.ccall(
        'rac_backend_llamacpp_vlm_register', 'number', [], [], { async: true },
      ) as unknown as Promise<number>);
      if (result === 0) {
        logger.info('llama.cpp VLM backend registered');
      }
    }
  }

  // -----------------------------------------------------------------------
  // Filesystem (model files written to this module's MEMFS)
  // -----------------------------------------------------------------------

  /**
   * Write a model file to this WASM module's Emscripten virtual filesystem.
   */
  writeFile(path: string, data: Uint8Array): void {
    const m = this.module;
    const dir = path.substring(0, path.lastIndexOf('/'));
    if (dir && typeof m.FS_createPath === 'function') {
      m.FS_createPath('/', dir.replace(/^\//, ''), true, true);
    }

    if (typeof m.FS_createDataFile === 'function') {
      const parentDir = dir || '/';
      const filename = path.substring(path.lastIndexOf('/') + 1);
      try { m.FS_unlink?.(path); } catch { /* doesn't exist */ }
      m.FS_createDataFile(parentDir, filename, data, true, true, true);
      logger.debug(`Wrote ${data.length} bytes to LlamaCpp FS: ${path}`);
    }
  }

  /**
   * Remove a file from this WASM module's filesystem.
   */
  unlinkFile(path: string): void {
    try { this.module.FS_unlink?.(path); } catch { /* doesn't exist */ }
  }

  // -----------------------------------------------------------------------
  // WebGPU Detection
  // -----------------------------------------------------------------------

  private async detectWebGPUWithJSPI(): Promise<boolean> {
    if (typeof navigator === 'undefined' || !('gpu' in navigator)) return false;
    try {
      const gpu = (navigator as any).gpu;
      const adapter = await gpu?.requestAdapter();
      if (!adapter) return false;

      // Also need JSPI
      return typeof WebAssembly !== 'undefined' &&
        'promising' in WebAssembly &&
        'Suspending' in WebAssembly;
    } catch {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // String / Memory Helpers (same as WASMBridge)
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

  writeBytes(src: Uint8Array, destPtr: number): void {
    const m = this.module;
    if (m.HEAPU8) { m.HEAPU8.set(src, destPtr); return; }
    for (let i = 0; i < src.length; i++) m.setValue(destPtr + i, src[i], 'i8');
  }

  readBytes(srcPtr: number, length: number): Uint8Array {
    const m = this.module;
    if (m.HEAPU8) return m.HEAPU8.slice(srcPtr, srcPtr + length);
    const result = new Uint8Array(length);
    for (let i = 0; i < length; i++) result[i] = m.getValue(srcPtr + i, 'i8') & 0xFF;
    return result;
  }

  readFloat32Array(srcPtr: number, count: number): Float32Array {
    const m = this.module;
    if (m.HEAPF32) return m.HEAPF32.slice(srcPtr >> 2, (srcPtr >> 2) + count);
    const result = new Float32Array(count);
    for (let i = 0; i < count; i++) result[i] = m.getValue(srcPtr + i * 4, 'float');
    return result;
  }

  writeFloat32Array(src: Float32Array, destPtr: number): void {
    const m = this.module;
    if (m.HEAPF32) { m.HEAPF32.set(src, destPtr >> 2); return; }
    for (let i = 0; i < src.length; i++) m.setValue(destPtr + i * 4, src[i], 'float');
  }

  readFloat32(ptr: number): number {
    const m = this.module;
    if (m.HEAPF32) return m.HEAPF32[ptr >> 2];
    return m.getValue(ptr, 'float');
  }

  checkResult(result: number, operation: string): void {
    if (result !== 0) {
      const errMsgPtr = this.module._rac_error_message(result);
      const errMsg = this.readString(errMsgPtr);
      throw new SDKError(SDKErrorCode.BackendError, `${operation}: ${errMsg}`);
    }
  }

  getErrorMessage(resultCode: number): string {
    return this.readString(this.module._rac_error_message(resultCode));
  }

  callFunction<T = number>(
    funcName: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): T {
    if (!this._module) throw new SDKError(SDKErrorCode.WASMNotLoaded, 'LlamaCpp WASM not loaded');
    return this._module.ccall(funcName, returnType, argTypes, args, opts) as T;
  }

  // -----------------------------------------------------------------------
  // Offset Helpers
  // -----------------------------------------------------------------------

  wasmOffsetOf(name: string): number {
    const fn = this.module[`_rac_wasm_offsetof_${name}`];
    return typeof fn === 'function' ? (fn as () => number)() : 0;
  }

  wasmSizeOf(name: string): number {
    const fn = this.module[`_rac_wasm_sizeof_${name}`];
    return typeof fn === 'function' ? (fn as () => number)() : 0;
  }

  // -----------------------------------------------------------------------
  // Cleanup
  // -----------------------------------------------------------------------

  shutdown(): void {
    // Flush and teardown telemetry before shutting down WASM
    if (this._analyticsEventsBridge) {
      try { this._analyticsEventsBridge.cleanup(); } catch { /* ignore */ }
      this._analyticsEventsBridge = null;
    }

    if (this._telemetryService) {
      try { this._telemetryService.shutdown(); } catch { /* ignore */ }
      this._telemetryService = null;
    }

    if (this._module && this._loaded) {
      try { this._module._rac_shutdown(); } catch { /* ignore */ }
    }

    // Clean up platform adapter
    if (this._platformAdapter) {
      try { this._platformAdapter.cleanup(); } catch { /* ignore */ }
      this._platformAdapter = null;
    }

    this._module = null;
    this._loaded = false;
    this._loading = null;
    this._accelerationMode = 'cpu';
    LlamaCppBridge._instance = null;
    logger.info('LlamaCpp bridge shut down');
  }
}
