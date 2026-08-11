/**
 * Worker-local ONNX + Sherpa runtime. This deliberately owns a separate
 * Emscripten module from SherpaONNXBridge: model lifecycle state is per heap.
 *
 * Acceleration policy:
 *   - `'webgpu'`: require browser WebGPU + artifact + ORT WebGPU EP probe
 *   - `'auto'`: try WebGPU path; on any failure fall back to CPU and report cpu
 *   - `'cpu'`: CPU artifact only
 *
 * Never report `acceleration: 'webgpu'` unless the ORT append probe succeeds.
 */
import {
  PlatformAdapter,
  RAC_ERROR_MODULE_ALREADY_REGISTERED,
  type PlatformAdapterModule,
} from '@runanywhere/web/backend';

export type OnnxAccelerationMode = 'auto' | 'cpu' | 'webgpu';

export interface WorkerOnnxLoadOptions {
  acceleration?: OnnxAccelerationMode;
  threads?: number;
  wasmUrl?: string;
  webgpuWasmUrl?: string;
}

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
  _rac_sherpa_set_wasm_compute?(numThreads: number, providerPtr: number): number;
  _rac_onnxrt_set_wasm_thread_counts?(intraOp: number, interOp: number): number;
  _rac_onnxrt_probe_webgpu_ep?(): number | Promise<number>;
  _rac_onnxrt_activate_preferred_wasm_ep?(preferWebgpu: number): number | Promise<number>;
  _rac_onnxrt_last_webgpu_probe_error?(): number;
  [key: string]: unknown;
}

type CreateModuleFn = (options?: {
  print?: (text: string) => void;
  printErr?: (text: string) => void;
  locateFile?: (path: string) => string;
  mainScriptUrlOrBlob?: string;
}) => Promise<WorkerOnnxModule>;

async function detectWebGPU(): Promise<boolean> {
  try {
    const gpu = (globalThis as { navigator?: { gpu?: unknown } }).navigator?.gpu as
      | { requestAdapter?: () => Promise<{ features: { has: (name: string) => boolean } } | null> }
      | undefined;
    if (!gpu?.requestAdapter) return false;
    const adapter = await gpu.requestAdapter();
    return Boolean(adapter?.features?.has('shader-f16'));
  } catch {
    return false;
  }
}

export class WorkerOnnxRuntime {
  private module: WorkerOnnxModule | null = null;
  private adapter: PlatformAdapter | null = null;
  private loaded = false;
  private accelerationMode: 'cpu' | 'webgpu' = 'cpu';
  private threads = 1;
  private fallbackReason: string | null = null;
  private readonly diagnosticsLog: string[] = [];

  get isLoaded(): boolean {
    return this.loaded && this.module !== null;
  }

  get acceleration(): 'cpu' | 'webgpu' {
    return this.accelerationMode;
  }

  get threadCount(): number {
    return this.threads;
  }

  /** Why WebGPU was not used when acceleration was auto/webgpu. */
  get lastFallbackReason(): string | null {
    return this.fallbackReason;
  }

  get recentDiagnostics(): string[] {
    return this.diagnosticsLog.slice(-40);
  }

  requireModule(): WorkerOnnxModule {
    if (!this.module) throw new Error('Worker ONNX/Sherpa WASM is not loaded');
    return this.module;
  }

  async ensureLoaded(options: WorkerOnnxLoadOptions = {}): Promise<void> {
    if (this.loaded) return;
    await this.doLoad(options);
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
    this.accelerationMode = 'cpu';
    this.threads = 1;
  }

  private clampThreads(value: number | undefined): number {
    if (value == null || !Number.isFinite(value)) return 2;
    return Math.max(1, Math.min(8, Math.floor(value)));
  }

  private async doLoad(options: WorkerOnnxLoadOptions): Promise<void> {
    const acceleration = options.acceleration ?? 'auto';
    const requestedThreads = this.clampThreads(options.threads);
    this.threads = requestedThreads;
    this.fallbackReason = null;

    const defaultCpuUrl = new URL('../wasm/racommons-onnx-sherpa.js', import.meta.url).href;
    const defaultWebgpuUrl = new URL('../wasm/racommons-onnx-sherpa-webgpu.js', import.meta.url).href;
    const cpuUrl = options.wasmUrl ?? defaultCpuUrl;
    const webgpuUrl = options.webgpuWasmUrl ?? defaultWebgpuUrl;

    const browserWebGPU = acceleration !== 'cpu' ? await detectWebGPU() : false;

    // Match llama: do NOT preflight with HEAD/Range (Vite @fs often rejects those
    // and we falsely skip the WebGPU twin). Try the import; fall back on failure.
    if (acceleration === 'webgpu') {
      if (!browserWebGPU) {
        throw new Error(
          'WebGPU speech acceleration requested but navigator.gpu / shader-f16 is unavailable',
        );
      }
      const ok = await this.tryLoadPath({
        moduleUrl: webgpuUrl,
        threads: requestedThreads,
        preferWebGPU: true,
      });
      if (!ok) {
        throw new Error(
          this.fallbackReason
            ?? `WebGPU speech acceleration requested but ORT WebGPU path failed (${webgpuUrl})`,
        );
      }
      return;
    }

    if (acceleration === 'auto' && browserWebGPU) {
      const ok = await this.tryLoadPath({
        moduleUrl: webgpuUrl,
        threads: requestedThreads,
        preferWebGPU: true,
      });
      if (ok) return;
      this.pushDiagnostic(
        'info',
        `WebGPU path unavailable (${this.fallbackReason ?? 'probe/load failed'}); falling back to CPU`,
      );
      await this.teardown();
    } else if (acceleration === 'auto' && !browserWebGPU) {
      this.fallbackReason = 'browser WebGPU / shader-f16 unavailable';
    }

    const cpuOk = await this.tryLoadPath({
      moduleUrl: cpuUrl,
      threads: requestedThreads,
      preferWebGPU: false,
    });
    if (!cpuOk) {
      throw new Error(this.fallbackReason ?? 'Failed to load ONNX/Sherpa CPU WASM');
    }
  }

  private async tryLoadPath(args: {
    moduleUrl: string;
    threads: number;
    preferWebGPU: boolean;
  }): Promise<boolean> {
    const { moduleUrl, threads, preferWebGPU } = args;
    const baseUrl = moduleUrl.substring(0, moduleUrl.lastIndexOf('/') + 1);
    try {
      const glue = await import(/* @vite-ignore */ moduleUrl) as { default: CreateModuleFn };
      this.module = await glue.default({
        print: (text) => this.pushDiagnostic('out', text),
        printErr: (text) => this.pushDiagnostic('err', text),
        locateFile: (path) => baseUrl + path,
        mainScriptUrlOrBlob: moduleUrl,
      });
      const ping = await this.module._rac_wasm_ping?.();
      if (ping !== 42) throw new Error(`WASM ping failed: expected 42, got ${String(ping)}`);

      this.adapter = new PlatformAdapter(this.module as unknown as PlatformAdapterModule);
      this.adapter.register();
      await this.initCommons(this.adapter.getAdapterPtr());

      // Thread pools must be configured before SharedOrt / EP probe.
      this.setThreadCounts(threads);

      // WebGPU twin is Asyncify-linked: EP probe/append can unwind through
      // Dawn waits and return a Promise. A sync `=== 1` check would always
      // fail and force an honest CPU fallback even with a real WebGPU EP.
      const webgpuActive = await this.activatePreferredEp(preferWebGPU);
      if (preferWebGPU && !webgpuActive) {
        this.fallbackReason =
          this.fallbackReason
          ?? 'ORT WebGPU EP append probe failed (CPU ORT archive or missing EP); using CPU';
        await this.teardown();
        return false;
      }

      this.accelerationMode = webgpuActive ? 'webgpu' : 'cpu';
      this.setSherpaProvider(this.accelerationMode, threads);
      await this.registerBackend('rac_backend_onnx_register');
      await this.registerBackend('rac_backend_sherpa_register');
      this.loaded = true;
      if (webgpuActive) this.fallbackReason = null;
      return true;
    } catch (error) {
      this.fallbackReason = error instanceof Error ? error.message : String(error);
      await this.teardown();
      return false;
    }
  }

  private setThreadCounts(threads: number): void {
    const module = this.requireModule();
    if (typeof module._rac_onnxrt_set_wasm_thread_counts === 'function') {
      module._rac_onnxrt_set_wasm_thread_counts(threads, 1);
    }
    this.threads = threads;
  }

  private readLastProbeError(): string | null {
    const module = this.module;
    if (!module || typeof module._rac_onnxrt_last_webgpu_probe_error !== 'function') {
      return null;
    }
    try {
      const ptr = module._rac_onnxrt_last_webgpu_probe_error();
      if (!ptr) return null;
      const text = module.UTF8ToString(ptr).trim();
      return text.length > 0 ? text : null;
    } catch {
      return null;
    }
  }

  private async activatePreferredEp(preferWebGPU: boolean): Promise<boolean> {
    const module = this.requireModule();
    const resolveRc = async (value: unknown): Promise<number> => {
      const settled = await Promise.resolve(value);
      return typeof settled === 'number' ? settled : Number(settled);
    };

    try {
      if (typeof module.ccall === 'function') {
        if (preferWebGPU) {
          // Prefer named ccall + Asyncify so Dawn/emdawn waits can resume.
          if (typeof module._rac_onnxrt_activate_preferred_wasm_ep === 'function') {
            const rc = await resolveRc(
              module.ccall(
                'rac_onnxrt_activate_preferred_wasm_ep',
                'number',
                ['number'],
                [1],
                { async: true },
              ),
            );
            if (rc === 1) return true;
            const detail = this.readLastProbeError();
            this.fallbackReason = detail
              ? `ORT WebGPU EP probe failed: ${detail}`
              : `ORT WebGPU EP activate returned ${String(rc)}`;
            this.pushDiagnostic('err', this.fallbackReason);
            return false;
          }
          if (typeof module._rac_onnxrt_probe_webgpu_ep === 'function') {
            const rc = await resolveRc(
              module.ccall('rac_onnxrt_probe_webgpu_ep', 'number', [], [], { async: true }),
            );
            if (rc === 1) return true;
            const detail = this.readLastProbeError();
            this.fallbackReason = detail
              ? `ORT WebGPU EP probe failed: ${detail}`
              : `ORT WebGPU EP probe returned ${String(rc)}`;
            this.pushDiagnostic('err', this.fallbackReason);
            return false;
          }
          this.fallbackReason = 'WebGPU artifact missing rac_onnxrt_activate/probe exports';
          return false;
        }
        // CPU path: still go through activate so EP state is explicit.
        if (typeof module._rac_onnxrt_activate_preferred_wasm_ep === 'function') {
          await resolveRc(
            module.ccall(
              'rac_onnxrt_activate_preferred_wasm_ep',
              'number',
              ['number'],
              [0],
              { async: true },
            ),
          );
        }
        return false;
      }

      // Fallback without ccall (tests / older glue).
      if (typeof module._rac_onnxrt_activate_preferred_wasm_ep === 'function') {
        return (await resolveRc(module._rac_onnxrt_activate_preferred_wasm_ep(preferWebGPU ? 1 : 0))) === 1;
      }
      if (preferWebGPU && typeof module._rac_onnxrt_probe_webgpu_ep === 'function') {
        return (await resolveRc(module._rac_onnxrt_probe_webgpu_ep())) === 1;
      }
      return false;
    } catch (error) {
      const detail = this.readLastProbeError();
      this.fallbackReason = error instanceof Error
        ? `ORT WebGPU EP probe threw: ${error.message}${detail ? ` (${detail})` : ''}`
        : `ORT WebGPU EP probe threw: ${String(error)}${detail ? ` (${detail})` : ''}`;
      this.pushDiagnostic('err', this.fallbackReason);
      return false;
    }
  }

  private setSherpaProvider(provider: 'cpu' | 'webgpu', threads: number): void {
    const module = this.requireModule();
    if (typeof module._rac_sherpa_set_wasm_compute !== 'function') return;
    const size = module.lengthBytesUTF8(provider) + 1;
    const ptr = module._malloc(size);
    try {
      module.stringToUTF8(provider, ptr, size);
      module._rac_sherpa_set_wasm_compute(threads, ptr);
    } finally {
      module._free(ptr);
    }
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
