/**
 * Worker-local ONNX + Sherpa runtime. This deliberately owns a separate
 * Emscripten module from SherpaONNXBridge: model lifecycle state is per heap.
 */
import {
  PlatformAdapter,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  type PlatformAdapterModule,
} from '@runanywhere/web/backend';

export interface WorkerOnnxModule {
  HEAPU8: Uint8Array;
  _malloc(size: number): number;
  _free(ptr: number): void;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8(text: string, ptr: number, maxBytesToWrite: number): void | number;
  lengthBytesUTF8(text: string): number;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  addFunction?(fn: (...args: number[]) => number | void, signature: string): number;
  removeFunction?(ptr: number): void;
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;
  _rac_wasm_ping?(): number | Promise<number>;
  _rac_wasm_sizeof_config?(): number;
  _rac_wasm_offsetof_config_platform_adapter?(): number;
  _rac_wasm_offsetof_config_log_level?(): number;
  _rac_error_message?(code: number): number;
  _rac_init?(configPtr: number): number | Promise<number>;
  _rac_shutdown?(): void;
  _rac_model_paths_set_base_dir?(basePtr: number): number;
  _rac_backend_onnx_register?(): number | Promise<number>;
  _rac_backend_sherpa_register?(): number | Promise<number>;
  [key: string]: unknown;
}

type CreateModuleFn = (options?: {
  print?: (text: string) => void;
  printErr?: (text: string) => void;
  locateFile?: (path: string) => string;
  mainScriptUrlOrBlob?: string;
}) => Promise<WorkerOnnxModule>;

export class WorkerOnnxRuntime {
  private module: WorkerOnnxModule | null = null;
  private adapter: PlatformAdapter | null = null;
  private loaded = false;
  private readonly diagnosticsLog: string[] = [];

  get isLoaded(): boolean {
    return this.loaded && this.module !== null;
  }

  get recentDiagnostics(): string[] {
    return this.diagnosticsLog.slice(-40);
  }

  requireModule(): WorkerOnnxModule {
    if (!this.module) throw new Error('Worker ONNX/Sherpa WASM is not loaded');
    return this.module;
  }

  async ensureLoaded(): Promise<void> {
    if (this.loaded) return;
    const moduleUrl = new URL('../wasm/racommons-onnx-sherpa.js', import.meta.url).href;
    const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);
    const glue = await import(/* @vite-ignore */ moduleUrl) as { default: CreateModuleFn };
    try {
      this.module = await glue.default({
        print: (text) => this.pushDiagnostic('out', text),
        printErr: (text) => this.pushDiagnostic('err', text),
        locateFile: (path) => baseUrl + path,
        // Required if this artifact is built with pthreads: child workers must
        // reload the original glue rather than this BackendWorker entrypoint.
        mainScriptUrlOrBlob: moduleUrl,
      });
      const ping = await this.module._rac_wasm_ping?.();
      if (ping !== 42) throw new Error(`WASM ping failed: expected 42, got ${String(ping)}`);

      this.adapter = new PlatformAdapter(this.module as unknown as PlatformAdapterModule);
      this.adapter.register();
      await this.initCommons(this.adapter.getAdapterPtr());
      await this.registerBackend('rac_backend_onnx_register');
      await this.registerBackend('rac_backend_sherpa_register');
      this.loaded = true;
    } catch (error) {
      await this.teardown();
      throw error;
    }
  }

  async teardown(): Promise<void> {
    try {
      this.module?._rac_shutdown?.();
    } catch {
      /* best effort */
    }
    try {
      this.adapter?.cleanup();
    } catch {
      /* best effort */
    }
    this.adapter = null;
    this.module = null;
    this.loaded = false;
  }

  private pushDiagnostic(level: string, text: string): void {
    this.diagnosticsLog.push(`[${level}] ${text}`);
    if (this.diagnosticsLog.length > 200) this.diagnosticsLog.splice(0, this.diagnosticsLog.length - 200);
  }

  private async initCommons(adapterPtr: number): Promise<void> {
    const module = this.requireModule();
    const size = module._rac_wasm_sizeof_config?.() ?? 0;
    const offset = module._rac_wasm_offsetof_config_platform_adapter?.();
    if (!size || offset === undefined || typeof module._rac_init !== 'function') {
      throw new Error('Worker WASM missing rac_init/config exports');
    }
    const configPtr = module._malloc(size);
    if (!configPtr) throw new Error('Worker rac_config allocation failed');
    try {
      for (let index = 0; index < size; index += 1) module.setValue(configPtr + index, 0, 'i8');
      module.setValue(configPtr + offset, adapterPtr, '*');
      const logOffset = module._rac_wasm_offsetof_config_log_level?.();
      if (logOffset !== undefined) module.setValue(configPtr + logOffset, 2, 'i32');
      const rc = await module.ccall('rac_init', 'number', ['number'], [configPtr], { async: true }) as number;
      if (rc !== 0) {
        const messagePtr = module._rac_error_message?.(rc) ?? 0;
        throw new Error(messagePtr ? module.UTF8ToString(messagePtr) : `rac_init failed (${rc})`);
      }
      this.setModelPathsBaseDir('/opfs');
    } finally {
      module._free(configPtr);
    }
  }

  private setModelPathsBaseDir(baseDir: string): void {
    const module = this.requireModule();
    if (typeof module._rac_model_paths_set_base_dir !== 'function') return;
    const size = module.lengthBytesUTF8(baseDir) + 1;
    const ptr = module._malloc(size);
    try {
      module.stringToUTF8(baseDir, ptr, size);
      module._rac_model_paths_set_base_dir(ptr);
    } finally {
      module._free(ptr);
    }
  }

  private async registerBackend(name: 'rac_backend_onnx_register' | 'rac_backend_sherpa_register'): Promise<void> {
    const rc = await this.requireModule().ccall(name, 'number', [], [], { async: true }) as number;
    if (rc !== 0 && rc !== RAC_ERROR_MODULE_ALREADY_REGISTERED) {
      throw new Error(`${name} returned ${rc}`);
    }
  }
}
