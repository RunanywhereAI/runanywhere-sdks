/**
 * Worker-local LlamaCpp WASM runtime.
 *
 * Owns a full Emscripten module inside a DedicatedWorker so load/unload and
 * inference do not contend with the UI thread. Unlike the main-thread
 * LlamaCppBridge, this path does NOT touch the core capability registry —
 * the worker speaks only through BackendWorker RPC.
 */

import {
  PlatformAdapter,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  SDKLogger,
  type AccelerationMode,
  type PlatformAdapterModule,
} from '@runanywhere/web/backend';

const logger = new SDKLogger('WorkerLlamaRuntime');

export interface WorkerLlamaModule {
  HEAPU8: Uint8Array;
  _malloc(size: number): number;
  _free(ptr: number): void;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): void | number;
  lengthBytesUTF8(str: string): number;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  addFunction(fn: (...args: number[]) => number | void, signature: string): number;
  removeFunction(ptr: number): void;
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;
  FS?: {
    analyzePath(path: string): { exists: boolean };
    readFile(path: string): Uint8Array;
    writeFile(path: string, data: Uint8Array): void;
    unlink(path: string): void;
    mkdir?(path: string): void;
  };
  FS_createPath?(parent: string, path: string, canRead: boolean, canWrite: boolean): void;

  _rac_init?(configPtr: number): number;
  _rac_shutdown?(): void;
  _rac_set_platform_adapter?(adapterPtr: number): number;
  _rac_error_message?(code: number): number;
  _rac_model_paths_set_base_dir?(basePtr: number): number;
  _rac_wasm_ping?(): number;
  _rac_wasm_sizeof_platform_adapter?(): number;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;
  _rac_backend_llamacpp_register(): number;
  _rac_get_model_registry?(): number;
  _rac_model_lifecycle_load_proto?(
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number>;
  _rac_model_lifecycle_unload_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number>;
  _rac_llm_generate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number | Promise<number>;
  _rac_llm_generate_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number | Promise<number>;
  _rac_llm_cancel_proto?(outEvent: number): number;
  _rac_proto_buffer_init?(bufferPtr: number): void;
  _rac_proto_buffer_free?(bufferPtr: number): void;
  _rac_wasm_sizeof_proto_buffer?(): number;
  _rac_wasm_offsetof_proto_buffer_data?(): number;
  _rac_wasm_offsetof_proto_buffer_size?(): number;
  _rac_wasm_offsetof_proto_buffer_status?(): number;
  [key: string]: unknown;
}

type CreateModuleFn = (options?: {
  print?: (text: string) => void;
  printErr?: (text: string) => void;
  locateFile?: (path: string) => string;
}) => Promise<WorkerLlamaModule>;

interface WebGPUAdapterLike {
  features?: { has(name: string): boolean };
}

export class WorkerLlamaRuntime {
  private module: WorkerLlamaModule | null = null;
  private platformAdapter: PlatformAdapter | null = null;
  private accelerationMode: AccelerationMode = 'cpu';
  private loaded = false;

  get isLoaded(): boolean {
    return this.loaded && this.module !== null;
  }

  get acceleration(): AccelerationMode {
    return this.accelerationMode;
  }

  requireModule(): WorkerLlamaModule {
    if (!this.module) {
      throw new Error('Worker LlamaCpp WASM is not loaded');
    }
    return this.module;
  }

  async ensureLoaded(acceleration: 'auto' | 'webgpu' | 'cpu' = 'auto'): Promise<void> {
    if (this.loaded) return;
    await this.doLoad(acceleration);
  }

  async teardown(): Promise<void> {
    if (this.module && this.loaded) {
      try {
        this.module._rac_shutdown?.();
      } catch (error) {
        logger.warning(
          `rac_shutdown threw: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
    if (this.platformAdapter) {
      try {
        this.platformAdapter.cleanup();
      } catch {
        /* ignore */
      }
      this.platformAdapter = null;
    }
    this.module = null;
    this.loaded = false;
    this.accelerationMode = 'cpu';
  }

  private async doLoad(acceleration: 'auto' | 'webgpu' | 'cpu'): Promise<void> {
    const webgpuAvailable = acceleration !== 'cpu' ? await detectWebGPU() : false;
    const useWebGPU = acceleration !== 'cpu' && webgpuAvailable;
    this.accelerationMode = useWebGPU ? 'webgpu' : 'cpu';

    const glueName = useWebGPU
      ? 'racommons-llamacpp-webgpu.js'
      : 'racommons-llamacpp.js';
    const moduleUrl = new URL(`../wasm/${glueName}`, import.meta.url).href;
    const glue = (await import(/* @vite-ignore */ moduleUrl)) as { default: CreateModuleFn };
    const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);

    try {
      this.module = await glue.default({
        print: (text) => logger.info(text),
        printErr: (text) => logger.info(text),
        locateFile: (path) => baseUrl + path,
      });

      const ping = this.module._rac_wasm_ping?.();
      const pingValue = typeof ping === 'object' && ping !== null && 'then' in ping
        ? await (ping as Promise<number>)
        : Number(ping);
      if (pingValue !== 42) {
        throw new Error(`WASM ping failed: expected 42, got ${pingValue}`);
      }

      this.platformAdapter = new PlatformAdapter(
        this.module as unknown as PlatformAdapterModule,
      );
      this.platformAdapter.register();
      await this.initRACommons(this.platformAdapter.getAdapterPtr());
      this.loaded = true;
      await this.registerBackend();
      logger.info(`Worker LlamaCpp WASM ready (${this.accelerationMode})`);
    } catch (error) {
      if (this.accelerationMode === 'webgpu' && acceleration === 'auto') {
        const reason = error instanceof Error ? error.message : String(error);
        logger.warning(`Worker WebGPU WASM failed (${reason}); falling back to CPU`);
        await this.teardown();
        return this.doLoad('cpu');
      }
      await this.teardown();
      throw error;
    }
  }

  private async initRACommons(adapterPtr: number): Promise<void> {
    const m = this.requireModule();
    const sizeofConfig = m._rac_wasm_sizeof_config;
    if (typeof sizeofConfig !== 'function' || typeof m._rac_init !== 'function') {
      throw new Error('Worker WASM missing rac_init / sizeof_config');
    }
    const configSize = sizeofConfig();
    const configPtr = m._malloc(configSize);
    try {
      for (let i = 0; i < configSize; i++) m.setValue(configPtr + i, 0, 'i8');
      if (typeof m._rac_wasm_offsetof_config_platform_adapter !== 'function') {
        throw new Error('Worker WASM missing config platform_adapter offset helper');
      }
      m.setValue(
        configPtr + m._rac_wasm_offsetof_config_platform_adapter(),
        adapterPtr,
        '*',
      );
      if (typeof m._rac_wasm_offsetof_config_log_level === 'function') {
        m.setValue(configPtr + m._rac_wasm_offsetof_config_log_level(), 2, 'i32');
      }
      const result = (await m.ccall(
        'rac_init',
        'number',
        ['number'],
        [configPtr],
        { async: true },
      )) as number;
      if (result !== 0) {
        const errPtr = m._rac_error_message?.(result) ?? 0;
        const errMsg = errPtr ? m.UTF8ToString(errPtr) : `rac_init failed (${result})`;
        throw new Error(errMsg);
      }
      this.setModelPathsBaseDir('/opfs');
    } finally {
      m._free(configPtr);
    }
  }

  private setModelPathsBaseDir(base: string): void {
    const m = this.requireModule();
    const setFn = m._rac_model_paths_set_base_dir;
    if (typeof setFn !== 'function') return;
    const len = m.lengthBytesUTF8(base) + 1;
    const ptr = m._malloc(len);
    try {
      m.stringToUTF8(base, ptr, len);
      setFn(ptr);
    } finally {
      m._free(ptr);
    }
  }

  private async registerBackend(): Promise<void> {
    const m = this.requireModule();
    if (typeof m._rac_backend_llamacpp_register !== 'function') {
      throw new Error('Worker WASM missing rac_backend_llamacpp_register');
    }
    const result = (await m.ccall(
      'rac_backend_llamacpp_register',
      'number',
      [],
      [],
      { async: true },
    )) as number;
    if (result !== 0 && result !== RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      throw new Error(`rac_backend_llamacpp_register returned ${result}`);
    }
  }
}

async function detectWebGPU(): Promise<boolean> {
  if (typeof navigator === 'undefined' || !('gpu' in navigator)) return false;
  try {
    const gpu = (navigator as Navigator & {
      gpu?: { requestAdapter(): Promise<WebGPUAdapterLike | null> };
    }).gpu;
    const adapter = await gpu?.requestAdapter();
    if (!adapter) return false;
    return adapter.features?.has('shader-f16') === true;
  } catch {
    return false;
  }
}
