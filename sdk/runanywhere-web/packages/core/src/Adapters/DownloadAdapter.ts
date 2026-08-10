import {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
  type DownloadCancelRequest as ProtoDownloadCancelRequest,
  type DownloadCancelResult as ProtoDownloadCancelResult,
  type DownloadPlanRequest as ProtoDownloadPlanRequest,
  type DownloadPlanResult as ProtoDownloadPlanResult,
  type DownloadProgress as ProtoDownloadProgress,
  type DownloadStartRequest as ProtoDownloadStartRequest,
  type DownloadStartResult as ProtoDownloadStartResult,
  type DownloadSubscribeRequest as ProtoDownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
import { SDKLogger } from '../Foundation/SDKLogger.js';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm.js';

const logger = new SDKLogger('DownloadAdapter');

export interface DownloadModule extends ProtoWasmModule {
  addFunction?(fn: (...args: number[]) => number | bigint | void, signature: string): number;
  removeFunction?(ptr: number): void;
  _rac_download_set_progress_proto_callback?(
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_download_plan_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_start_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_cancel_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_progress_poll_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
}

export type ProtoDownloadProgressHandler = (progress: ProtoDownloadProgress) => void;

let defaultModule: DownloadModule | null = null;
let defaultProgressCallbackPtr = 0;

export class DownloadAdapter {
  static setDefaultModule(module: DownloadModule): void {
    defaultModule = module;
  }

  static clearDefaultModule(): void {
    if (defaultModule && defaultProgressCallbackPtr) {
      defaultModule._rac_download_set_progress_proto_callback?.(0, 0);
      defaultModule.removeFunction?.(defaultProgressCallbackPtr);
    }
    defaultProgressCallbackPtr = 0;
    defaultModule = null;
  }

  static tryDefault(): DownloadAdapter | null {
    return defaultModule ? new DownloadAdapter(defaultModule) : null;
  }

  constructor(private readonly module: DownloadModule) {}

  supportsProtoDownloads(): boolean {
    return this.missingExports().length === 0;
  }

  /**
   * Plan a download. Asynchronous because the native planner reaches the
   * network.
   *
   * `build_download_plan` runs a HEAD size probe (`rac_http_request_send`) to
   * confirm the catalog's byte count before any bytes are fetched. On WASM that
   * probe is served by the browser's fetch, so the export can suspend through
   * Asyncify. Called as a plain synchronous export, the suspension unwinds the
   * stack and returns immediately with the out-buffer still zero-initialised —
   * which decodes to an all-default plan (no model id, zero files) that reads
   * as "no files were resolved", and then corrupts the heap when the rewind
   * writes into the buffer the caller has already freed. Every bare `.gguf` in
   * the web catalog failed this way. `ccall({ async: true })` is the contract
   * for a suspending export, exactly as HTTPAdapter documents.
   */
  async plan(request: ProtoDownloadPlanRequest): Promise<ProtoDownloadPlanResult | null> {
    if (!this.ensureExports('plan', ['_rac_download_plan_proto'])) return null;
    return this.bridge().withEncodedRequestAsync(
      request,
      DownloadPlanRequest,
      DownloadPlanResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_download_plan_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_download_plan_proto!(requestPtr, requestSize, outResult),
      ),
      'rac_download_plan_proto',
    );
  }

  start(request: ProtoDownloadStartRequest): ProtoDownloadStartResult | null {
    if (!this.ensureExports('start', ['_rac_download_start_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      DownloadStartRequest,
      DownloadStartResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_download_start_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_download_start_proto',
    );
  }

  cancel(request: ProtoDownloadCancelRequest): ProtoDownloadCancelResult | null {
    if (!this.ensureExports('cancel', ['_rac_download_cancel_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      DownloadCancelRequest,
      DownloadCancelResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_download_cancel_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_download_cancel_proto',
    );
  }

  poll(request: ProtoDownloadSubscribeRequest): ProtoDownloadProgress | null {
    if (!this.ensureExports('poll', ['_rac_download_progress_poll_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      DownloadSubscribeRequest,
      DownloadProgress,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_download_progress_poll_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_download_progress_poll_proto',
    );
  }

  setProgressHandler(handler: ProtoDownloadProgressHandler | null): boolean {
    const mod = this.module;
    if (!this.ensureExports('setProgressHandler', ['_rac_download_set_progress_proto_callback'])) {
      return false;
    }
    if (!mod.addFunction || !mod.removeFunction || !mod.HEAPU8) {
      logger.warning('setProgressHandler: module missing addFunction/removeFunction/HEAPU8');
      return false;
    }

    if (defaultProgressCallbackPtr) {
      mod._rac_download_set_progress_proto_callback!(0, 0);
      mod.removeFunction(defaultProgressCallbackPtr);
      defaultProgressCallbackPtr = 0;
    }
    if (!handler) return true;

    const callbackPtr = mod.addFunction((bytesPtr: number, size: number) => {
      if (!bytesPtr || size <= 0) return;
      const bytes = mod.HEAPU8!.slice(bytesPtr, bytesPtr + size);
      handler(DownloadProgress.decode(bytes));
    }, 'viii');

    const rc = mod._rac_download_set_progress_proto_callback!(callbackPtr, 0);
    if (rc !== 0) {
      mod.removeFunction(callbackPtr);
      logger.warning(`rac_download_set_progress_proto_callback returned rc=${rc}`);
      return false;
    }
    defaultProgressCallbackPtr = callbackPtr;
    return true;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private missingExports(): string[] {
    const bridge = this.bridge();
    const required: Array<keyof DownloadModule> = [
      '_rac_download_set_progress_proto_callback',
      '_rac_download_plan_proto',
      '_rac_download_start_proto',
      '_rac_download_cancel_proto',
      '_rac_download_progress_poll_proto',
    ];
    return [
      ...bridge.missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
  }

  private ensureExports(operation: string, required: Array<keyof DownloadModule>): boolean {
    const bridgeMissing = this.bridge().missingProtoBufferExports();
    const missing = [
      ...bridgeMissing,
      ...required.filter((key) => !this.module[key]).map(String),
    ];
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing download proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }
}
