/**
 * PlatformAdapter — registers `rac_platform_adapter_t` callbacks with a
 * loaded RACommons WASM module.
 *
 * The C struct is a flat list of function pointers. JavaScript provides
 * implementations via Emscripten's `addFunction()`, then writes the resulting
 * function-table indices into the struct in WASM memory.
 *
 * Shared by every WASM-owning bridge (the core Commons module and the
 * backend packages) so the browser platform services — MEMFS file I/O,
 * localStorage "secure" storage, console logging, Date.now, memory info,
 * vendor id — are populated once, identically, for each module.
 * `rac_init` enforces that the mandatory slots are non-NULL, so a
 * zero-filled stub adapter is NOT a valid substitute.
 *
 * IMPORTANT: every field offset comes from a runtime
 * `_rac_wasm_offsetof_platform_adapter_<field>()` helper compiled into
 * `wasm/src/wasm_exports.cpp`. We do NOT hard-code `PTR_SIZE = 4` or a
 * sequential accumulator — the struct layout depends on alignment/padding
 * and would silently corrupt memory on any reorder/add if TypeScript baked
 * it in.
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('PlatformAdapter');

// rac_error.h ranges
const RAC_OK = 0;
const RAC_ERROR_FILE_NOT_FOUND = -183;
const RAC_ERROR_FILE_WRITE_FAILED = -185;
const RAC_ERROR_PLATFORM = -180;
const RAC_ERROR_INVALID_ARGUMENT = -259;
const RAC_ERROR_CANCELLED = -380;
const RAC_DIRECTORY_ENTRY_NAME_MAX = 512;

// In-flight async downloads started through the `http_download` adapter slot,
// keyed by the task id handed back to C++. Used by `http_download_cancel`.
let httpDownloadCounter = 0;
const httpDownloadTasks = new Map<string, AbortController>();

/**
 * Structural Emscripten-module surface the adapter needs. Any RACommons
 * WASM module (core, llamacpp, onnx) satisfies this.
 */
export interface PlatformAdapterModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  addFunction(fn: (...args: never[]) => unknown, signature: string): number;
  removeFunction(ptr: number): void;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): void | number;
  lengthBytesUTF8(str: string): number;
  HEAPU8?: Uint8Array;
  FS?: unknown;
  _rac_wasm_sizeof_platform_adapter?(): number;
}

interface CallbackPtrs {
  fileExists: number;
  fileRead: number;
  fileWrite: number;
  fileDelete: number;
  secureGet: number;
  secureSet: number;
  secureDelete: number;
  log: number;
  nowMs: number;
  getMemoryInfo: number;
  fileListDirectory: number;
  isNonEmptyDirectory: number;
  getVendorId: number;
  httpDownload: number;
  httpDownloadCancel: number;
}

export class PlatformAdapter {
  private callbacks: CallbackPtrs | null = null;
  private adapterPtr = 0;

  constructor(private readonly m: PlatformAdapterModule) {}

  /**
   * Allocate the rac_platform_adapter_t struct, install JS callbacks via
   * `addFunction()`, and write the resulting indices into the struct in WASM
   * memory. The caller is responsible for passing `getAdapterPtr()` to
   * `rac_init` via `config.platform_adapter` — that single install is
   * authoritative. `_rac_set_platform_adapter` is NOT called here to avoid
   * a redundant double-write when `rac_init` already stores the same pointer.
   */
  register(): void {
    const m = this.m;
    const sizeofPlatformAdapter = m._rac_wasm_sizeof_platform_adapter;
    if (typeof sizeofPlatformAdapter !== 'function') {
      throw new Error(
        'WASM module missing _rac_wasm_sizeof_platform_adapter export',
      );
    }

    logger.info('Registering platform adapter callbacks...');

    const adapterSize = sizeofPlatformAdapter();
    this.adapterPtr = m._malloc(adapterSize);
    for (let i = 0; i < adapterSize; i++) {
      m.setValue(this.adapterPtr + i, 0, 'i8');
    }

    this.callbacks = {
      fileExists: this.registerFileExists(),
      fileRead: this.registerFileRead(),
      fileWrite: this.registerFileWrite(),
      fileDelete: this.registerFileDelete(),
      secureGet: this.registerSecureGet(),
      secureSet: this.registerSecureSet(),
      secureDelete: this.registerSecureDelete(),
      log: this.registerLog(),
      nowMs: this.registerNowMs(),
      getMemoryInfo: this.registerGetMemoryInfo(),
      fileListDirectory: this.registerFileListDirectory(),
      isNonEmptyDirectory: this.registerIsNonEmptyDirectory(),
      getVendorId: this.registerGetVendorId(),
      httpDownload: this.registerHttpDownload(),
      httpDownloadCancel: this.registerHttpDownloadCancel(),
    };

    // Runtime struct offsets — each helper must be exported by
    // wasm/src/wasm_exports.cpp. If any is missing, fail loudly rather than
    // silently corrupting memory with a bad fallback.
    const getOffset = (name: string): number => {
      const fn = (m as unknown as Record<string, unknown>)[
        `_rac_wasm_offsetof_platform_adapter_${name}`
      ];
      if (typeof fn !== 'function') {
        throw new Error(
          `WASM module missing _rac_wasm_offsetof_platform_adapter_${name} export; ` +
          'rebuild the RACommons WASM from wasm/src/wasm_exports.cpp.',
        );
      }
      return (fn as () => number)();
    };

    // ABI guard (MUST be the first two fields). rac_init rejects the adapter
    // with RAC_ERROR_ABI_VERSION_MISMATCH unless these match the commons build.
    // 1 == RAC_PLATFORM_ADAPTER_ABI_VERSION.
    m.setValue(this.adapterPtr + getOffset('abi_version'), 1, 'i32');
    m.setValue(this.adapterPtr + getOffset('struct_size'), adapterSize, 'i32');

    m.setValue(this.adapterPtr + getOffset('file_exists'), this.callbacks.fileExists, '*');
    m.setValue(this.adapterPtr + getOffset('file_read'), this.callbacks.fileRead, '*');
    m.setValue(this.adapterPtr + getOffset('file_write'), this.callbacks.fileWrite, '*');
    m.setValue(this.adapterPtr + getOffset('file_delete'), this.callbacks.fileDelete, '*');
    m.setValue(this.adapterPtr + getOffset('secure_get'), this.callbacks.secureGet, '*');
    m.setValue(this.adapterPtr + getOffset('secure_set'), this.callbacks.secureSet, '*');
    m.setValue(this.adapterPtr + getOffset('secure_delete'), this.callbacks.secureDelete, '*');
    m.setValue(this.adapterPtr + getOffset('log'), this.callbacks.log, '*');
    m.setValue(this.adapterPtr + getOffset('now_ms'), this.callbacks.nowMs, '*');
    m.setValue(this.adapterPtr + getOffset('get_memory_info'), this.callbacks.getMemoryInfo, '*');
    // http_download (async streaming slot). The C++ download orchestrator
    // prefers this slot on Emscripten (event-driven, non-blocking) so progress
    // ticks live; without it, the synchronous FetchHttpTransport path buffers
    // the whole body on the main thread and the UI freezes at 0% until 100%.
    m.setValue(this.adapterPtr + getOffset('http_download'), this.callbacks.httpDownload, '*');
    m.setValue(this.adapterPtr + getOffset('http_download_cancel'), this.callbacks.httpDownloadCancel, '*');
    // extract_archive — native libarchive is compiled into WASM.
    m.setValue(this.adapterPtr + getOffset('extract_archive'), 0, '*');
    m.setValue(this.adapterPtr + getOffset('file_list_directory'), this.callbacks.fileListDirectory, '*');
    m.setValue(this.adapterPtr + getOffset('is_non_empty_directory'), this.callbacks.isNonEmptyDirectory, '*');
    m.setValue(this.adapterPtr + getOffset('get_vendor_id'), this.callbacks.getVendorId, '*');
    // user_data
    m.setValue(this.adapterPtr + getOffset('user_data'), 0, '*');

    logger.info('Platform adapter struct populated; caller installs via rac_init config.platform_adapter');
  }

  /** Pointer to the rac_platform_adapter_t struct in WASM memory. */
  getAdapterPtr(): number {
    return this.adapterPtr;
  }

  cleanup(): void {
    const m = this.m;
    if (this.callbacks) {
      for (const ptr of Object.values(this.callbacks)) {
        if (ptr !== 0) {
          try { m.removeFunction(ptr); } catch { /* ignore */ }
        }
      }
      this.callbacks = null;
    }
    if (this.adapterPtr !== 0) {
      m._free(this.adapterPtr);
      this.adapterPtr = 0;
    }
  }

  // -----------------------------------------------------------------------
  // Callback Implementations
  // -----------------------------------------------------------------------

  /** rac_bool_t (*)(const char* path, void* user_data) */
  private registerFileExists(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const exists = fsOf(m)?.analyzePath(path).exists ?? false;
        return exists ? 1 : 0;
      } catch {
        return 0;
      }
    }, 'iii');
  }

  /** rac_result_t (*)(const char* path, void** out_data, size_t* out_size, void* user_data) */
  private registerFileRead(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, outDataPtr: number, outSizePtr: number, _userData: number) => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const fs = fsOf(m);
        if (!fs) return RAC_ERROR_FILE_NOT_FOUND;
        const data = fs.readFile(path);
        const wasmPtr = m._malloc(data.length);
        writeBytes(m, data, wasmPtr);
        m.setValue(outDataPtr, wasmPtr, '*');
        m.setValue(outSizePtr, data.length, 'i32');
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_NOT_FOUND;
      }
    }, 'iiiii');
  }

  /** rac_result_t (*)(const char* path, const void* data, size_t size, void* user_data) */
  private registerFileWrite(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, dataPtr: number, size: number, _userData: number) => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const fs = fsOf(m);
        if (!fs) return RAC_ERROR_FILE_WRITE_FAILED;
        const data = readBytes(m, dataPtr, size);
        fs.writeFile(path, data);
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_WRITE_FAILED;
      }
    }, 'iiiii');
  }

  /** rac_result_t (*)(const char* path, void* user_data) */
  private registerFileDelete(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        const path = m.UTF8ToString(pathPtr);
        fsOf(m)?.unlink(path);
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_NOT_FOUND;
      }
    }, 'iii');
  }

  /**
   * localStorage is plaintext — no OS-level encryption equivalent to
   * Keychain/KeyStore. Restricted to non-sensitive SDK metadata (device/vendor
   * IDs). The `rac_sdk_plaintext_` prefix makes the storage class visible in
   * DevTools at a glance.
   */
  private registerSecureGet(): number {
    const m = this.m;
    return m.addFunction((keyPtr: number, outValuePtr: number, _userData: number) => {
      try {
        const key = m.UTF8ToString(keyPtr);
        const value = localStorage.getItem(`rac_sdk_plaintext_${key}`);
        if (value === null) {
          m.setValue(outValuePtr, 0, '*');
          return RAC_ERROR_FILE_NOT_FOUND;
        }
        const len = m.lengthBytesUTF8(value) + 1;
        const strPtr = m._malloc(len);
        m.stringToUTF8(value, strPtr, len);
        m.setValue(outValuePtr, strPtr, '*');
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiii');
  }

  private registerSecureSet(): number {
    const m = this.m;
    return m.addFunction((keyPtr: number, valuePtr: number, _userData: number) => {
      try {
        const key = m.UTF8ToString(keyPtr);
        const value = m.UTF8ToString(valuePtr);
        localStorage.setItem(`rac_sdk_plaintext_${key}`, value);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiii');
  }

  private registerSecureDelete(): number {
    const m = this.m;
    return m.addFunction((keyPtr: number, _userData: number) => {
      try {
        const key = m.UTF8ToString(keyPtr);
        localStorage.removeItem(`rac_sdk_plaintext_${key}`);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iii');
  }

  /** void (*)(rac_log_level_t level, const char* category, const char* message, void* user_data) */
  private registerLog(): number {
    const m = this.m;
    return m.addFunction((level: number, categoryPtr: number, messagePtr: number, _userData: number) => {
      const category = m.UTF8ToString(categoryPtr);
      const message = m.UTF8ToString(messagePtr);
      const prefix = `[RAC:${category}]`;
      switch (level) {
        case 0: case 1: console.debug(prefix, message); break;
        case 2: console.info(prefix, message); break;
        case 3: console.warn(prefix, message); break;
        case 4: case 5: console.error(prefix, message); break;
        default: console.log(prefix, message);
      }
    }, 'viiii');
  }

  /** int64_t (*)(void* user_data) */
  private registerNowMs(): number {
    const m = this.m;
    return m.addFunction((_userData: number) => {
      return BigInt(Date.now());
    }, 'ji');
  }

  /** rac_result_t (*)(rac_memory_info_t* out_info, void* user_data) */
  private registerGetMemoryInfo(): number {
    const m = this.m;
    return m.addFunction((outInfoPtr: number, _userData: number) => {
      try {
        const nav = navigator as Navigator & { deviceMemory?: number };
        const deviceMemoryGiB = nav.deviceMemory ?? 4;
        const deviceMemoryBytes = deviceMemoryGiB * 1024 * 1024 * 1024;

        const perf = performance as Performance & {
          memory?: { usedJSHeapSize?: number; jsHeapSizeLimit?: number };
        };
        const jsHeapUsed = perf.memory?.usedJSHeapSize ?? 0;
        const jsHeapTotal = perf.memory?.jsHeapSizeLimit ?? deviceMemoryBytes;
        // Clamp to avoid negative available when perf.memory disagrees with deviceMemory.
        const jsHeapAvailable = Math.max(0, jsHeapTotal - jsHeapUsed);

        // rac_memory_info_t: { uint64_t total, available, used } — 8 bytes each.
        setI64(m, outInfoPtr, jsHeapTotal);
        setI64(m, outInfoPtr + 8, jsHeapAvailable);
        setI64(m, outInfoPtr + 16, jsHeapUsed);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iii');
  }

  /**
   * rac_result_t (*)(const char* dir_path, rac_directory_entry_t* out_entries,
   *                  size_t* in_out_count, void* user_data)
   */
  private registerFileListDirectory(): number {
    const m = this.m;
    return m.addFunction((dirPathPtr: number, outEntriesPtr: number, countPtr: number, _userData: number) => {
      try {
        if (!fsOf(m) || !countPtr) return RAC_ERROR_INVALID_ARGUMENT;
        const dirPath = m.UTF8ToString(dirPathPtr);
        const entries = listDirectoryEntries(m, dirPath);
        if (!entries) return RAC_ERROR_FILE_NOT_FOUND;

        if (!outEntriesPtr) {
          m.setValue(countPtr, entries.length, 'i32');
          return RAC_OK;
        }

        const capacity = m.getValue(countPtr, 'i32') >>> 0;
        const count = Math.min(capacity, entries.length);
        const layout = directoryEntryLayout(m);
        for (let i = 0; i < count; i += 1) {
          const entryPtr = outEntriesPtr + i * layout.size;
          const entry = entries[i];
          const namePtr = entryPtr + layout.nameOffset;
          const safeName = entry.name.slice(0, RAC_DIRECTORY_ENTRY_NAME_MAX - 1);
          m.stringToUTF8(safeName, namePtr, RAC_DIRECTORY_ENTRY_NAME_MAX);
          m.setValue(entryPtr + layout.isDirOffset, entry.isDir ? 1 : 0, 'i32');
          setI64(m, entryPtr + layout.sizeBytesOffset, entry.sizeBytes);
        }
        m.setValue(countPtr, count, 'i32');
        return RAC_OK;
      } catch (error) {
        logger.warning(`file_list_directory failed: ${error instanceof Error ? error.message : String(error)}`);
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiiii');
  }

  /** rac_bool_t (*)(const char* path, void* user_data) */
  private registerIsNonEmptyDirectory(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        if (!fsOf(m)) return 0;
        const path = m.UTF8ToString(pathPtr);
        const entries = listDirectoryEntries(m, path);
        return entries && entries.length > 0 ? 1 : 0;
      } catch {
        return 0;
      }
    }, 'iii');
  }

  /** rac_result_t (*)(char* out_buffer, size_t buffer_size, void* user_data) */
  private registerGetVendorId(): number {
    const m = this.m;
    return m.addFunction((outBufferPtr: number, bufferSize: number, _userData: number) => {
      try {
        if (!outBufferPtr || bufferSize < 37) return RAC_ERROR_INVALID_ARGUMENT;
        const vendorId = stableVendorId();
        m.stringToUTF8(vendorId, outBufferPtr, bufferSize);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiii');
  }

  /**
   * rac_result_t (*http_download)(const char* url, const char* destination_path,
   *     rac_http_progress_callback_fn progress_callback,
   *     rac_http_complete_callback_fn complete_callback,
   *     void* callback_user_data, char** out_task_id, void* user_data)
   *
   * Async by contract: start the transfer, return RAC_OK immediately with a
   * task id, then stream bytes to MEMFS while calling progress_callback per
   * chunk and complete_callback at the end. Because it returns immediately and
   * the fetch runs on the event loop, the main thread is never blocked — the
   * C++ download orchestrator's poll loop sees live byte counts and the UI does
   * not freeze (unlike the synchronous FetchHttpTransport fallback).
   */
  private registerHttpDownload(): number {
    const m = this.m;
    return m.addFunction((
      urlPtr: number,
      destPtr: number,
      progressCbPtr: number,
      completeCbPtr: number,
      cbUserData: number,
      outTaskIdPtr: number,
      _userData: number,
    ) => {
      try {
        const url = m.UTF8ToString(urlPtr);
        const dest = m.UTF8ToString(destPtr);
        const taskId = `webdl_${++httpDownloadCounter}`;

        // Hand the task id back to C++ as an owned C string (orchestrator frees).
        if (outTaskIdPtr) {
          const len = m.lengthBytesUTF8(taskId) + 1;
          const idPtr = m._malloc(len);
          m.stringToUTF8(taskId, idPtr, len);
          m.setValue(outTaskIdPtr, idPtr, '*');
        }

        const controller = new AbortController();
        httpDownloadTasks.set(taskId, controller);

        // Fire-and-forget: the transfer drives itself on the event loop and
        // reports back through the C callbacks. Errors are surfaced via
        // complete_callback, never thrown out of this synchronous start call.
        void runHttpDownload(m, {
          url,
          dest,
          progressCbPtr,
          completeCbPtr,
          cbUserData,
          controller,
        }).finally(() => httpDownloadTasks.delete(taskId));

        return RAC_OK;
      } catch (error) {
        logger.warning(`http_download start failed: ${error instanceof Error ? error.message : String(error)}`);
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiiiiiii');
  }

  /** rac_result_t (*http_download_cancel)(const char* task_id, void* user_data) */
  private registerHttpDownloadCancel(): number {
    const m = this.m;
    return m.addFunction((taskIdPtr: number, _userData: number) => {
      try {
        const taskId = m.UTF8ToString(taskIdPtr);
        const controller = httpDownloadTasks.get(taskId);
        if (controller) {
          controller.abort();
          httpDownloadTasks.delete(taskId);
        }
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iii');
  }
}

// ---------------------------------------------------------------------------
// HEAP helpers — `addFunction` callbacks run before any `_malloc`, so the
// HEAP views can be stale; always re-read off the module.
// ---------------------------------------------------------------------------

function writeBytes(m: PlatformAdapterModule, src: Uint8Array, destPtr: number): void {
  if (m.HEAPU8) {
    m.HEAPU8.set(src, destPtr);
    return;
  }
  for (let i = 0; i < src.length; i++) m.setValue(destPtr + i, src[i], 'i8');
}

function readBytes(m: PlatformAdapterModule, srcPtr: number, length: number): Uint8Array {
  if (m.HEAPU8) return m.HEAPU8.slice(srcPtr, srcPtr + length);
  const out = new Uint8Array(length);
  for (let i = 0; i < length; i++) out[i] = m.getValue(srcPtr + i, 'i8') & 0xff;
  return out;
}

// ---------------------------------------------------------------------------
// http_download slot — async streaming fetch → MEMFS with progress callbacks.
// ---------------------------------------------------------------------------

/** Emscripten FS stream-write surface needed to write chunks incrementally. */
interface StreamingFS {
  open(path: string, flags: string): unknown;
  write(stream: unknown, buffer: ArrayBufferView, offset: number, length: number, position?: number): number;
  close(stream: unknown): void;
  mkdirTree?(path: string): void;
  analyzePath?(path: string): { exists: boolean };
  stat?(path: string): { size?: number };
}

function streamingFsOf(m: PlatformAdapterModule): StreamingFS | null {
  const fs = (m as { FS?: unknown }).FS as Partial<StreamingFS> | undefined;
  if (fs && typeof fs.open === 'function' && typeof fs.write === 'function'
    && typeof fs.close === 'function') {
    return fs as StreamingFS;
  }
  return null;
}

function memfsFileSize(fs: StreamingFS, path: string): number {
  try {
    if (fs.analyzePath && !fs.analyzePath(path)?.exists) return 0;
    return fs.stat?.(path)?.size ?? 0;
  } catch {
    return 0;
  }
}

/** Resolve a WASM-table entry as a callable (i64 args are passed as BigInt). */
function wasmCallable(
  m: PlatformAdapterModule,
  ptr: number,
): ((...args: Array<number | bigint>) => number) | null {
  if (ptr === 0) return null;
  const tbl = m as unknown as {
    getWasmTableEntry?: (p: number) => (...args: Array<number | bigint>) => number;
    wasmTable?: { get(p: number): (...args: Array<number | bigint>) => number };
  };
  if (typeof tbl.getWasmTableEntry === 'function') return tbl.getWasmTableEntry(ptr);
  if (tbl.wasmTable && typeof tbl.wasmTable.get === 'function') return tbl.wasmTable.get(ptr);
  return null;
}

/** Invoke rac_http_progress_callback_fn — void (int64, int64, void*). */
function invokeProgressCallback(
  m: PlatformAdapterModule,
  cbPtr: number,
  bytesDownloaded: number,
  totalBytes: number,
  userData: number,
): void {
  const callable = wasmCallable(m, cbPtr);
  if (!callable) return;
  try {
    callable(BigInt(bytesDownloaded), BigInt(totalBytes), userData);
  } catch (error) {
    logger.warning(`http_download progress callback threw: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/** Invoke rac_http_complete_callback_fn — void (rac_result_t, const char*, void*). */
function invokeCompleteCallback(
  m: PlatformAdapterModule,
  cbPtr: number,
  result: number,
  downloadedPath: string | null,
  userData: number,
): void {
  const callable = wasmCallable(m, cbPtr);
  if (!callable) return;
  let pathPtr = 0;
  try {
    if (downloadedPath) {
      const len = m.lengthBytesUTF8(downloadedPath) + 1;
      pathPtr = m._malloc(len);
      m.stringToUTF8(downloadedPath, pathPtr, len);
    }
    callable(result, pathPtr, userData);
  } catch (error) {
    logger.warning(`http_download complete callback threw: ${error instanceof Error ? error.message : String(error)}`);
  } finally {
    if (pathPtr) {
      try { m._free(pathPtr); } catch { /* noop */ }
    }
  }
}

interface HttpDownloadArgs {
  url: string;
  dest: string;
  progressCbPtr: number;
  completeCbPtr: number;
  cbUserData: number;
  controller: AbortController;
}

/**
 * Stream `url` into the MEMFS file at `dest`, reporting incremental progress.
 * Resumes from any bytes already on disk via a Range request when the server
 * honours it (HTTP 206); otherwise restarts from zero. Always finishes by
 * invoking the C complete callback (success, cancel, or error) exactly once.
 */
async function runHttpDownload(m: PlatformAdapterModule, args: HttpDownloadArgs): Promise<void> {
  const { url, dest, progressCbPtr, completeCbPtr, cbUserData, controller } = args;
  const fs = streamingFsOf(m);
  if (!fs) {
    invokeCompleteCallback(m, completeCbPtr, RAC_ERROR_PLATFORM, null, cbUserData);
    return;
  }

  let stream: unknown = null;
  try {
    const parent = dest.slice(0, dest.lastIndexOf('/')) || '/';
    try { fs.mkdirTree?.(parent); } catch { /* dir may already exist */ }

    const existing = memfsFileSize(fs, dest);
    const headers: Record<string, string> = {};
    if (existing > 0) headers.Range = `bytes=${existing}-`;

    const response = await fetch(url, { headers, signal: controller.signal });

    // 416 Range Not Satisfiable on a resume request means the file on disk is
    // already at/past the requested offset — i.e. the download is complete.
    // Report success without rewriting so a re-trigger of an already-present
    // model is a no-op rather than a hard failure.
    if (existing > 0 && response.status === 416) {
      invokeCompleteCallback(m, completeCbPtr, RAC_OK, dest, cbUserData);
      return;
    }

    let received = 0;
    let position = 0;
    if (existing > 0 && response.status === 206) {
      // Server honoured the range — append to the partial file.
      received = existing;
      position = existing;
      stream = fs.open(dest, 'r+');
    } else {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      // Fresh download (or server ignored Range) — truncate and restart.
      stream = fs.open(dest, 'w');
    }

    const contentLength = Number(response.headers.get('Content-Length') ?? 0);
    const totalBytes = contentLength > 0 ? received + contentLength : 0;

    if (!response.body) throw new Error('response has no readable body');
    const reader = response.body.getReader();

    invokeProgressCallback(m, progressCbPtr, received, totalBytes, cbUserData);

    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value && value.length > 0) {
        fs.write(stream, value, 0, value.length, position);
        position += value.length;
        received += value.length;
        invokeProgressCallback(m, progressCbPtr, received, totalBytes, cbUserData);
      }
    }

    fs.close(stream);
    stream = null;
    invokeCompleteCallback(m, completeCbPtr, RAC_OK, dest, cbUserData);
  } catch (error) {
    if (stream) {
      try { fs.close(stream); } catch { /* noop */ }
    }
    const aborted = controller.signal.aborted
      || (error instanceof DOMException && error.name === 'AbortError');
    if (!aborted) {
      logger.warning(`http_download '${url}' failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    invokeCompleteCallback(
      m,
      completeCbPtr,
      aborted ? RAC_ERROR_CANCELLED : RAC_ERROR_PLATFORM,
      null,
      cbUserData,
    );
  }
}

interface DirectoryEntryInfo {
  name: string;
  isDir: boolean;
  sizeBytes: number;
}

interface DirectoryEntryLayout {
  size: number;
  nameOffset: number;
  isDirOffset: number;
  sizeBytesOffset: number;
}

interface EmscriptenFS {
  analyzePath(path: string): { exists: boolean };
  readFile(path: string): Uint8Array;
  writeFile(path: string, data: Uint8Array): void;
  unlink(path: string): void;
  mkdir?(path: string): void;
  readdir?(path: string): string[];
  stat?(path: string): { mode?: number; size?: number };
  isDir?(mode: number): boolean;
}

function fsOf(m: PlatformAdapterModule): EmscriptenFS | undefined {
  return m.FS as EmscriptenFS | undefined;
}

function joinPath(parent: string, name: string): string {
  if (parent.endsWith('/')) return `${parent}${name}`;
  return `${parent}/${name}`;
}

function listDirectoryEntries(m: PlatformAdapterModule, dirPath: string): DirectoryEntryInfo[] | null {
  const fs = fsOf(m);
  if (!fs?.readdir) return null;
  const analyzed = fs.analyzePath(dirPath);
  if (!analyzed.exists) return null;
  const names = fs.readdir(dirPath).filter((name) => name !== '.' && name !== '..' && !name.startsWith('.'));
  return names.map((name) => {
    const path = joinPath(dirPath, name);
    const stat = fs.stat?.(path);
    const isDir = typeof stat?.mode === 'number' && typeof fs.isDir === 'function'
      ? fs.isDir(stat.mode)
      : false;
    return {
      name,
      isDir,
      sizeBytes: isDir ? 0 : stat?.size ?? 0,
    };
  });
}

function directoryEntryLayout(m: PlatformAdapterModule): DirectoryEntryLayout {
  const record = m as unknown as Record<string, unknown>;
  const required = (name: string): number => {
    const fn = record[name];
    if (typeof fn !== 'function') {
      throw new Error(`WASM module missing ${name}`);
    }
    return (fn as () => number)();
  };
  return {
    size: required('_rac_wasm_sizeof_directory_entry'),
    nameOffset: required('_rac_wasm_offsetof_directory_entry_name'),
    isDirOffset: required('_rac_wasm_offsetof_directory_entry_is_dir'),
    sizeBytesOffset: required('_rac_wasm_offsetof_directory_entry_size_bytes'),
  };
}

function setI64(m: PlatformAdapterModule, ptr: number, value: number): void {
  const low = value >>> 0;
  const high = Math.floor(value / 0x100000000) >>> 0;
  m.setValue(ptr, low, 'i32');
  m.setValue(ptr + 4, high, 'i32');
}

function stableVendorId(): string {
  const key = 'rac_sdk_plaintext_vendor_id';
  try {
    const existing = localStorage.getItem(key);
    if (existing) return existing;
  } catch {
    /* ignore */
  }
  const generated = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  try {
    localStorage.setItem(key, generated);
  } catch {
    /* ignore */
  }
  return generated;
}
