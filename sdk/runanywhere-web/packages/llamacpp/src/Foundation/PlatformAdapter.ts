/**
 * RunAnywhere Web SDK - Platform Adapter
 *
 * Implements rac_platform_adapter_t callbacks using browser Web APIs.
 * This is the web equivalent of:
 *   - SwiftPlatformAdapter (iOS)
 *   - KotlinPlatformAdapter (Android/JVM)
 *   - DartPlatformAdapter (Flutter)
 *
 * Each callback is registered as a C function pointer via Emscripten's
 * Module.addFunction(), then written into the rac_platform_adapter_t
 * struct in WASM memory.
 */

import type { LlamaCppModule } from './LlamaCppBridge';
import { LlamaCppBridge } from './LlamaCppBridge';
import { SDKLogger } from '@runanywhere/web';

const logger = new SDKLogger('PlatformAdapter');

/**
 * Registered callback function pointers (for cleanup).
 */
interface RegisteredCallbacks {
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
  httpDownload: number;
  extractArchive: number;
}

/**
 * PlatformAdapter - Bridges browser Web APIs to RACommons C callbacks.
 *
 * The rac_platform_adapter_t struct is a collection of C function pointers.
 * JavaScript provides implementations via Emscripten's addFunction(),
 * which creates callable C function pointers from JS closures.
 */
export class PlatformAdapter {
  private callbacks: RegisteredCallbacks | null = null;
  private adapterPtr = 0;

  /**
   * Create and register the platform adapter with RACommons.
   * Must be called after WASM module is loaded but before rac_init().
   */
  register(): void {
    const bridge = LlamaCppBridge.shared;
    const m = bridge.module;

    logger.info('Registering platform adapter callbacks...');

    // Allocate the rac_platform_adapter_t struct
    const adapterSize = m._rac_wasm_sizeof_platform_adapter();
    this.adapterPtr = m._malloc(adapterSize);

    // Zero-initialize
    for (let i = 0; i < adapterSize; i++) {
      m.setValue(this.adapterPtr + i, 0, 'i8');
    }

    // Register each callback as a C function pointer
    this.callbacks = {
      fileExists: this.registerFileExists(m),
      fileRead: this.registerFileRead(m),
      fileWrite: this.registerFileWrite(m),
      fileDelete: this.registerFileDelete(m),
      secureGet: this.registerSecureGet(m),
      secureSet: this.registerSecureSet(m),
      secureDelete: this.registerSecureDelete(m),
      log: this.registerLog(m),
      nowMs: this.registerNowMs(m),
      getMemoryInfo: this.registerGetMemoryInfo(m),
      httpDownload: this.registerHttpDownload(m),
      extractArchive: this.registerExtractArchive(m),
    };

    // Write function pointers into the struct.
    // The struct layout matches rac_platform_adapter.h field order.
    // Each field is a function pointer (4 bytes on wasm32).
    const PTR_SIZE = 4;
    let offset = 0;

    m.setValue(this.adapterPtr + offset, this.callbacks.fileExists, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.fileRead, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.fileWrite, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.fileDelete, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.secureGet, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.secureSet, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.secureDelete, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.log, '*'); offset += PTR_SIZE;
    // track_error: optional, set to 0 (null)
    m.setValue(this.adapterPtr + offset, 0, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.nowMs, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.getMemoryInfo, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.httpDownload, '*'); offset += PTR_SIZE;
    // http_download_cancel: optional, set to 0 (null)
    m.setValue(this.adapterPtr + offset, 0, '*'); offset += PTR_SIZE;
    m.setValue(this.adapterPtr + offset, this.callbacks.extractArchive, '*'); offset += PTR_SIZE;
    // user_data: set to 0 (null)
    m.setValue(this.adapterPtr + offset, 0, '*');

    // Register with RACommons
    const result = m._rac_set_platform_adapter(this.adapterPtr);
    if (result !== 0) {
      logger.error(`Failed to set platform adapter: ${result}`);
      this.cleanup();
      return;
    }

    logger.info('Platform adapter registered successfully');
  }

  /**
   * Get the WASM pointer to the adapter struct.
   * Used by RunAnywhere.initialize() to populate rac_config_t.
   */
  getAdapterPtr(): number {
    return this.adapterPtr;
  }

  /**
   * Clean up allocated callbacks and memory.
   */
  cleanup(): void {
    const m = LlamaCppBridge.shared.module;

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

  /** file_exists: rac_bool_t (*)(const char* path, void* user_data) */
  private registerFileExists(m: LlamaCppModule): number {
    return m.addFunction((pathPtr: number, _userData: number): number => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const result = m.FS.analyzePath(path);
        return result.exists ? 1 : 0;
      } catch {
        return 0;
      }
    }, 'iii');
  }

  /** file_read: rac_result_t (*)(const char* path, void** out_data, size_t* out_size, void* user_data) */
  private registerFileRead(m: LlamaCppModule): number {
    return m.addFunction((pathPtr: number, outDataPtr: number, outSizePtr: number, _userData: number): number => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const data = m.FS.readFile(path);
        const wasmPtr = m._malloc(data.length);
        LlamaCppBridge.shared.writeBytes(data, wasmPtr);
        m.setValue(outDataPtr, wasmPtr, '*');
        m.setValue(outSizePtr, data.length, 'i32');
        return 0; // RAC_OK
      } catch {
        return -182; // RAC_ERROR_FILE_NOT_FOUND
      }
    }, 'iiiii');
  }

  /** file_write: rac_result_t (*)(const char* path, const void* data, size_t size, void* user_data) */
  private registerFileWrite(m: LlamaCppModule): number {
    return m.addFunction((pathPtr: number, dataPtr: number, size: number, _userData: number): number => {
      try {
        const path = m.UTF8ToString(pathPtr);
        const data = LlamaCppBridge.shared.readBytes(dataPtr, size);
        m.FS.writeFile(path, data);
        return 0;
      } catch {
        return -183; // RAC_ERROR_FILE_WRITE_FAILED
      }
    }, 'iiiii');
  }

  /** file_delete: rac_result_t (*)(const char* path, void* user_data) */
  private registerFileDelete(m: LlamaCppModule): number {
    return m.addFunction((pathPtr: number, _userData: number): number => {
      try {
        const path = m.UTF8ToString(pathPtr);
        m.FS.unlink(path);
        return 0;
      } catch {
        return -182;
      }
    }, 'iii');
  }

  /**
   * secure_get: rac_result_t (*)(const char* key, char** out_value, void* user_data)
   *
   * SECURITY NOTE: On web, "secure" storage uses localStorage which is NOT
   * truly secure. Data is accessible to any script running on the same origin
   * (including XSS attacks). Do NOT store sensitive secrets (API keys, tokens,
   * PII) here. On native platforms (iOS/Android) the equivalent callback uses
   * Keychain / KeyStore which are hardware-backed and encrypted.
   *
   * For the web platform this is intentionally best-effort: the RACommons C
   * layer only uses it for non-sensitive SDK state (e.g. cached environment).
   */
  private registerSecureGet(m: LlamaCppModule): number {
    return m.addFunction((keyPtr: number, outValuePtr: number, _userData: number): number => {
      try {
        const key = m.UTF8ToString(keyPtr);
        const value = localStorage.getItem(`rac_sdk_${key}`);
        if (value === null) {
          m.setValue(outValuePtr, 0, '*');
          return -182;
        }
        const strPtr = LlamaCppBridge.shared.allocString(value);
        m.setValue(outValuePtr, strPtr, '*');
        return 0;
      } catch {
        return -180;
      }
    }, 'iiii');
  }

  /**
   * secure_set: rac_result_t (*)(const char* key, const char* value, void* user_data)
   *
   * SECURITY NOTE: See registerSecureGet — localStorage is NOT secure on web.
   * Do not use for sensitive data.
   */
  private registerSecureSet(m: LlamaCppModule): number {
    return m.addFunction((keyPtr: number, valuePtr: number, _userData: number): number => {
      try {
        const key = m.UTF8ToString(keyPtr);
        const value = m.UTF8ToString(valuePtr);
        localStorage.setItem(`rac_sdk_${key}`, value);
        return 0;
      } catch {
        return -180;
      }
    }, 'iiii');
  }

  /**
   * secure_delete: rac_result_t (*)(const char* key, void* user_data)
   *
   * SECURITY NOTE: See registerSecureGet — localStorage is NOT secure on web.
   */
  private registerSecureDelete(m: LlamaCppModule): number {
    return m.addFunction((keyPtr: number, _userData: number): number => {
      try {
        const key = m.UTF8ToString(keyPtr);
        localStorage.removeItem(`rac_sdk_${key}`);
        return 0;
      } catch {
        return -180;
      }
    }, 'iii');
  }

  /** log: void (*)(rac_log_level_t level, const char* category, const char* message, void* user_data) */
  private registerLog(m: LlamaCppModule): number {
    return m.addFunction((level: number, categoryPtr: number, messagePtr: number, _userData: number): void => {
      const category = m.UTF8ToString(categoryPtr);
      const message = m.UTF8ToString(messagePtr);
      const prefix = `[RAC:${category}]`;

      switch (level) {
        case 0: // TRACE
        case 1: // DEBUG
          console.debug(prefix, message);
          break;
        case 2: // INFO
          console.info(prefix, message);
          break;
        case 3: // WARNING
          console.warn(prefix, message);
          break;
        case 4: // ERROR
        case 5: // FATAL
          console.error(prefix, message);
          break;
        default:
          console.log(prefix, message);
      }
    }, 'viiii');
  }

  /** now_ms: int64_t (*)(void* user_data) */
  private registerNowMs(m: LlamaCppModule): number {
    // Note: Emscripten represents int64_t as two i32 values (lo, hi) in some cases.
    // For simplicity, we use 'ii' return (returns i32 which truncates but is fine for ms).
    return m.addFunction((_userData: number): number => {
      return Date.now();
    }, 'ii');
  }

  /** get_memory_info: rac_result_t (*)(rac_memory_info_t* out_info, void* user_data) */
  private registerGetMemoryInfo(m: LlamaCppModule): number {
    return m.addFunction((outInfoPtr: number, _userData: number): number => {
      try {
        // rac_memory_info_t: { uint64_t total, available, used }
        // Estimate browser memory
        const nav = navigator as NavigatorWithMemory;
        const totalMB = nav.deviceMemory ?? 4; // deviceMemory API (GB)
        const totalBytes = totalMB * 1024 * 1024 * 1024;

        // performance.memory is Chrome-only (non-standard)
        const perf = performance as PerformanceWithMemory;
        const jsHeapUsed = perf.memory?.usedJSHeapSize ?? 0;
        const jsHeapTotal = perf.memory?.jsHeapSizeLimit ?? totalBytes;

        // Write as uint64 (two i32 values each for wasm32)
        // Simplified: write lower 32 bits only
        m.setValue(outInfoPtr, jsHeapTotal & 0xFFFFFFFF, 'i32');      // total low
        m.setValue(outInfoPtr + 4, 0, 'i32');                          // total high
        m.setValue(outInfoPtr + 8, (jsHeapTotal - jsHeapUsed) & 0xFFFFFFFF, 'i32'); // available low
        m.setValue(outInfoPtr + 12, 0, 'i32');                         // available high
        m.setValue(outInfoPtr + 16, jsHeapUsed & 0xFFFFFFFF, 'i32');  // used low
        m.setValue(outInfoPtr + 20, 0, 'i32');                         // used high

        return 0;
      } catch {
        return -180;
      }
    }, 'iii');
  }

  /**
   * http_download: rac_result_t (*)(const char* url, const char* dest_path,
   *   progress_cb, complete_cb, void* cb_user_data, char** out_task_id, void* user_data)
   * Note: 7 params in C
   */
  private registerHttpDownload(m: LlamaCppModule): number {
    return m.addFunction(
      (urlPtr: number, destPathPtr: number, progressCbPtr: number, completeCbPtr: number, cbUserData: number, outTaskIdPtr: number, _userData: number): number => {
        const url = m.UTF8ToString(urlPtr);
        const destPath = m.UTF8ToString(destPathPtr);

        // Generate task ID string
        const taskId = `dl_${Date.now()}`;
        if (outTaskIdPtr !== 0) {
          const strPtr = LlamaCppBridge.shared.allocString(taskId);
          m.setValue(outTaskIdPtr, strPtr, '*');
        }

        // Async download via fetch
        this.performDownload(m, url, destPath, progressCbPtr, completeCbPtr, cbUserData)
          .catch((err) => {
            logger.error(`Download failed: ${err}`);
          });

        return 0;
      },
      'iiiiiiii',
    );
  }

  /**
   * extract_archive: rac_result_t (*)(const char* archive_path, const char* dest_dir,
   *   progress_cb, void* cb_user_data, void* user_data)
   *
   * NOTE: This callback is dead code as of Phase 2 (libarchive migration).
   * rac_extract_archive() in rac_core.cpp now calls rac_extract_archive_native()
   * directly (native libarchive compiled into WASM), bypassing the platform adapter.
   * Kept as a no-op for struct layout compatibility.
   */
  private registerExtractArchive(m: LlamaCppModule): number {
    return m.addFunction((archivePtr: number, destPtr: number, _progressCb: number, _cbUserData: number, _userData: number): number => {
      // Native libarchive extraction is compiled into the WASM module.
      // rac_extract_archive() calls rac_extract_archive_native() directly,
      // so this platform adapter callback should never be reached.
      const archivePath = m.UTF8ToString(archivePtr);
      const destPath = m.UTF8ToString(destPtr);
      logger.warning(`Unexpected extract_archive callback invocation: ${archivePath} -> ${destPath}`);
      return -180;
    }, 'iiiiii');
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /**
   * Perform an HTTP download using fetch() and stream to Emscripten FS.
   */
  private async performDownload(
    m: LlamaCppModule,
    url: string,
    destPath: string,
    progressCbPtr: number,
    completeCbPtr: number,
    cbUserData: number,
  ): Promise<void> {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const contentLength = parseInt(response.headers.get('content-length') ?? '0', 10);
      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('ReadableStream not supported');
      }

      const chunks: Uint8Array[] = [];
      let downloaded = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        chunks.push(value);
        downloaded += value.length;

        // Report progress via C callback
        if (progressCbPtr !== 0) {
          m.dynCall('viii', progressCbPtr, [downloaded, contentLength, cbUserData]);
        }
      }

      // Combine chunks and write to Emscripten FS
      const totalData = new Uint8Array(downloaded);
      let offset = 0;
      for (const chunk of chunks) {
        totalData.set(chunk, offset);
        offset += chunk.length;
      }

      // Ensure parent directory exists
      const parentDir = destPath.substring(0, destPath.lastIndexOf('/'));
      if (parentDir) {
        try { m.FS.mkdir(parentDir); } catch { /* exists */ }
      }

      m.FS.writeFile(destPath, totalData);

      // Report completion via C callback
      if (completeCbPtr !== 0) {
        const pathPtr = LlamaCppBridge.shared.allocString(destPath);
        m.dynCall('viii', completeCbPtr, [0, pathPtr, cbUserData]); // 0 = RAC_OK
        m._free(pathPtr);
      }
    } catch (error) {
      logger.error(`Download failed for ${url}: ${error}`);
      if (completeCbPtr !== 0) {
        const pathPtr = LlamaCppBridge.shared.allocString('');
        m.dynCall('viii', completeCbPtr, [-160, pathPtr, cbUserData]); // RAC_ERROR_DOWNLOAD_FAILED
        m._free(pathPtr);
      }
    }
  }
}

// Browser API type extensions
interface NavigatorWithMemory extends Navigator {
  deviceMemory?: number;
}

interface PerformanceWithMemory extends Performance {
  memory?: {
    usedJSHeapSize: number;
    totalJSHeapSize: number;
    jsHeapSizeLimit: number;
  };
}

// Extend LlamaCppModule with dynCall and FS
declare module './LlamaCppBridge' {
  interface LlamaCppModule {
    dynCall: (sig: string, ptr: number, args: number[]) => unknown;
    FS: {
      analyzePath: (path: string) => { exists: boolean };
      readFile: (path: string) => Uint8Array;
      writeFile: (path: string, data: Uint8Array) => void;
      unlink: (path: string) => void;
      mkdir: (path: string) => void;
    };
  }
}
