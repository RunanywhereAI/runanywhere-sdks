/**
 * PlatformAdapter — registers `rac_platform_adapter_t` callbacks with the
 * loaded WASM module.
 *
 * The C struct is a flat list of function pointers. JavaScript provides
 * implementations via Emscripten's `addFunction()`, then writes the resulting
 * function-table indices into the struct in WASM memory.
 *
 * IMPORTANT: every field offset comes from a runtime
 * `_rac_wasm_offsetof_platform_adapter_<field>()` helper compiled into
 * `wasm/src/wasm_exports.cpp`. We do NOT hard-code `PTR_SIZE = 4` or a
 * sequential accumulator — the struct layout depends on alignment/padding
 * and would silently corrupt memory on any reorder/add if TypeScript baked
 * it in.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { LlamaCppModule } from './LlamaCppBridge';

const logger = new SDKLogger('PlatformAdapter');

// rac_error.h ranges
const RAC_OK = 0;
const RAC_ERROR_FILE_NOT_FOUND = -182;
const RAC_ERROR_FILE_WRITE_FAILED = -183;
const RAC_ERROR_PLATFORM = -180;

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
}

export class PlatformAdapter {
  private callbacks: CallbackPtrs | null = null;
  private adapterPtr = 0;

  constructor(private readonly m: LlamaCppModule) {}

  /**
   * Allocate the rac_platform_adapter_t struct, install JS callbacks via
   * `addFunction()`, write the resulting indices into the struct in WASM
   * memory, then call `_rac_set_platform_adapter()`.
   */
  register(): void {
    const m = this.m;
    const sizeofPlatformAdapter = m._rac_wasm_sizeof_platform_adapter;
    const setPlatformAdapter = m._rac_set_platform_adapter;
    if (typeof sizeofPlatformAdapter !== 'function' || typeof setPlatformAdapter !== 'function') {
      throw new Error(
        'WASM module missing _rac_wasm_sizeof_platform_adapter or _rac_set_platform_adapter exports',
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
          `rebuild racommons-llamacpp.wasm from wasm/src/wasm_exports.cpp.`,
        );
      }
      return (fn as () => number)();
    };

    m.setValue(this.adapterPtr + getOffset('file_exists'), this.callbacks.fileExists, '*');
    m.setValue(this.adapterPtr + getOffset('file_read'), this.callbacks.fileRead, '*');
    m.setValue(this.adapterPtr + getOffset('file_write'), this.callbacks.fileWrite, '*');
    m.setValue(this.adapterPtr + getOffset('file_delete'), this.callbacks.fileDelete, '*');
    m.setValue(this.adapterPtr + getOffset('secure_get'), this.callbacks.secureGet, '*');
    m.setValue(this.adapterPtr + getOffset('secure_set'), this.callbacks.secureSet, '*');
    m.setValue(this.adapterPtr + getOffset('secure_delete'), this.callbacks.secureDelete, '*');
    m.setValue(this.adapterPtr + getOffset('log'), this.callbacks.log, '*');
    // track_error (optional) → null. Web does not forward platform errors
    // into Sentry today; leaving NULL preserves the commons null-check path.
    m.setValue(this.adapterPtr + getOffset('track_error'), 0, '*');
    m.setValue(this.adapterPtr + getOffset('now_ms'), this.callbacks.nowMs, '*');
    m.setValue(this.adapterPtr + getOffset('get_memory_info'), this.callbacks.getMemoryInfo, '*');
    // http_download (optional) → null. The HTTPAdapter / FetchHttpTransport
    // path takes over once setRunanywhereModule installs the module.
    m.setValue(this.adapterPtr + getOffset('http_download'), 0, '*');
    m.setValue(this.adapterPtr + getOffset('http_download_cancel'), 0, '*');
    // extract_archive — native libarchive is compiled into WASM.
    m.setValue(this.adapterPtr + getOffset('extract_archive'), 0, '*');
    // user_data
    m.setValue(this.adapterPtr + getOffset('user_data'), 0, '*');

    const result = setPlatformAdapter(this.adapterPtr);
    if (result !== 0) {
      logger.error(`Failed to set platform adapter: ${result}`);
      this.cleanup();
      throw new Error(`rac_set_platform_adapter returned ${result}`);
    }
    logger.info('Platform adapter registered successfully');
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
        const exists = m.FS?.analyzePath(path).exists ?? false;
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
        if (!m.FS) return RAC_ERROR_FILE_NOT_FOUND;
        const data = m.FS.readFile(path);
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
        if (!m.FS) return RAC_ERROR_FILE_WRITE_FAILED;
        const data = readBytes(m, dataPtr, size);
        m.FS.writeFile(path, data);
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
        m.FS?.unlink(path);
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_NOT_FOUND;
      }
    }, 'iii');
  }

  /**
   * SECURITY NOTE: localStorage is **not** secure. Used only for the small
   * SDK metadata C-side reads/writes (e.g. cached environment). Do not
   * store API keys or PII here. Native platforms back this with Keychain /
   * KeyStore which is hardware-encrypted; the browser has no equivalent.
   */
  private registerSecureGet(): number {
    const m = this.m;
    return m.addFunction((keyPtr: number, outValuePtr: number, _userData: number) => {
      try {
        const key = m.UTF8ToString(keyPtr);
        const value = localStorage.getItem(`rac_sdk_${key}`);
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
        localStorage.setItem(`rac_sdk_${key}`, value);
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
        localStorage.removeItem(`rac_sdk_${key}`);
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
        const totalMB = nav.deviceMemory ?? 4;
        const totalBytes = totalMB * 1024 * 1024 * 1024;

        const perf = performance as Performance & {
          memory?: { usedJSHeapSize?: number; jsHeapSizeLimit?: number };
        };
        const jsHeapUsed = perf.memory?.usedJSHeapSize ?? 0;
        const jsHeapTotal = perf.memory?.jsHeapSizeLimit ?? totalBytes;

        // rac_memory_info_t: { uint64_t total, available, used } — write low/high pairs
        m.setValue(outInfoPtr, jsHeapTotal & 0xFFFFFFFF, 'i32');
        m.setValue(outInfoPtr + 4, 0, 'i32');
        m.setValue(outInfoPtr + 8, (jsHeapTotal - jsHeapUsed) & 0xFFFFFFFF, 'i32');
        m.setValue(outInfoPtr + 12, 0, 'i32');
        m.setValue(outInfoPtr + 16, jsHeapUsed & 0xFFFFFFFF, 'i32');
        m.setValue(outInfoPtr + 20, 0, 'i32');
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

function writeBytes(m: LlamaCppModule, src: Uint8Array, destPtr: number): void {
  if (m.HEAPU8) {
    m.HEAPU8.set(src, destPtr);
    return;
  }
  for (let i = 0; i < src.length; i++) m.setValue(destPtr + i, src[i], 'i8');
}

function readBytes(m: LlamaCppModule, srcPtr: number, length: number): Uint8Array {
  if (m.HEAPU8) return m.HEAPU8.slice(srcPtr, srcPtr + length);
  const out = new Uint8Array(length);
  for (let i = 0; i < length; i++) out[i] = m.getValue(srcPtr + i, 'i8') & 0xff;
  return out;
}
