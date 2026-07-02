import { SDKLogger } from '../Foundation/SDKLogger';
import { OPFS_ROOT } from './OpfsModelStore';

const logger = new SDKLogger('PlatformAdapter');

const RAC_OK = 0;
const RAC_ERROR_FILE_NOT_FOUND = -183;
const RAC_ERROR_FILE_WRITE_FAILED = -185;
const RAC_ERROR_PLATFORM = -180;
const RAC_ERROR_INVALID_ARGUMENT = -259;
const RAC_ERROR_CANCELLED = -380;
const RAC_DIRECTORY_ENTRY_NAME_MAX = 512;

let httpDownloadCounter = 0;
const httpDownloadTasks = new Map<string, AbortController>();

export interface SecureStore {
  get(key: string): string | null;
  set(key: string, value: string): void;
  delete(key: string): void;
}

export class InMemorySecureStore implements SecureStore {
  private readonly map = new Map<string, string>();
  get(key: string): string | null { return this.map.get(key) ?? null; }
  set(key: string, value: string): void { this.map.set(key, value); }
  delete(key: string): void { this.map.delete(key); }
}

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

  constructor(
    private readonly m: PlatformAdapterModule,
    private readonly secure: SecureStore = new InMemorySecureStore(),
  ) {}

  register(): void {
    const m = this.m;
    const sizeofPlatformAdapter = m._rac_wasm_sizeof_platform_adapter;
    if (typeof sizeofPlatformAdapter !== 'function') {
      throw new Error('WASM module missing _rac_wasm_sizeof_platform_adapter export');
    }

    const adapterSize = sizeofPlatformAdapter();
    this.adapterPtr = m._malloc(adapterSize);
    for (let i = 0; i < adapterSize; i++) m.setValue(this.adapterPtr + i, 0, 'i8');

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

    const getOffset = (name: string): number => {
      const fn = (m as unknown as Record<string, unknown>)[`_rac_wasm_offsetof_platform_adapter_${name}`];
      if (typeof fn !== 'function') {
        throw new Error(
          `WASM module missing _rac_wasm_offsetof_platform_adapter_${name} export; ` +
          'rebuild the RACommons WASM from wasm/src/wasm_exports.cpp.',
        );
      }
      return (fn as () => number)();
    };

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
    m.setValue(this.adapterPtr + getOffset('http_download'), this.callbacks.httpDownload, '*');
    m.setValue(this.adapterPtr + getOffset('http_download_cancel'), this.callbacks.httpDownloadCancel, '*');
    m.setValue(this.adapterPtr + getOffset('extract_archive'), 0, '*');
    m.setValue(this.adapterPtr + getOffset('file_list_directory'), this.callbacks.fileListDirectory, '*');
    m.setValue(this.adapterPtr + getOffset('is_non_empty_directory'), this.callbacks.isNonEmptyDirectory, '*');
    m.setValue(this.adapterPtr + getOffset('get_vendor_id'), this.callbacks.getVendorId, '*');
    m.setValue(this.adapterPtr + getOffset('user_data'), 0, '*');
  }

  getAdapterPtr(): number {
    return this.adapterPtr;
  }

  cleanup(): void {
    const m = this.m;
    if (this.callbacks) {
      for (const ptr of Object.values(this.callbacks)) {
        if (ptr !== 0) {
          try { m.removeFunction(ptr); } catch {}
        }
      }
      this.callbacks = null;
    }
    if (this.adapterPtr !== 0) {
      m._free(this.adapterPtr);
      this.adapterPtr = 0;
    }
  }

  private registerFileExists(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        return fsOf(m)?.analyzePath(m.UTF8ToString(pathPtr)).exists ? 1 : 0;
      } catch {
        return 0;
      }
    }, 'iii');
  }

  private registerFileRead(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, outDataPtr: number, outSizePtr: number, _userData: number) => {
      try {
        const fs = fsOf(m);
        if (!fs) return RAC_ERROR_FILE_NOT_FOUND;
        const data = fs.readFile(m.UTF8ToString(pathPtr));
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

  private registerFileWrite(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, dataPtr: number, size: number, _userData: number) => {
      try {
        const fs = fsOf(m);
        if (!fs) return RAC_ERROR_FILE_WRITE_FAILED;
        fs.writeFile(m.UTF8ToString(pathPtr), readBytes(m, dataPtr, size));
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_WRITE_FAILED;
      }
    }, 'iiiii');
  }

  private registerFileDelete(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        fsOf(m)?.unlink(m.UTF8ToString(pathPtr));
        return RAC_OK;
      } catch {
        return RAC_ERROR_FILE_NOT_FOUND;
      }
    }, 'iii');
  }

  private registerSecureGet(): number {
    const m = this.m;
    return m.addFunction((keyPtr: number, outValuePtr: number, _userData: number) => {
      try {
        const value = this.secure.get(m.UTF8ToString(keyPtr));
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
        this.secure.set(m.UTF8ToString(keyPtr), m.UTF8ToString(valuePtr));
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
        this.secure.delete(m.UTF8ToString(keyPtr));
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iii');
  }

  private registerLog(): number {
    const m = this.m;
    return m.addFunction((level: number, categoryPtr: number, messagePtr: number, _userData: number) => {
      const prefix = `[RAC:${m.UTF8ToString(categoryPtr)}]`;
      const message = m.UTF8ToString(messagePtr);
      switch (level) {
        case 0: case 1: console.debug(prefix, message); break;
        case 2: console.info(prefix, message); break;
        case 3: console.warn(prefix, message); break;
        case 4: case 5: console.error(prefix, message); break;
        default: console.log(prefix, message);
      }
    }, 'viiii');
  }

  private registerNowMs(): number {
    const m = this.m;
    return m.addFunction((_userData: number) => BigInt(Date.now()), 'ji');
  }

  private registerGetMemoryInfo(): number {
    const m = this.m;
    return m.addFunction((outInfoPtr: number, _userData: number) => {
      try {
        const nav = navigator as Navigator & { deviceMemory?: number };
        const deviceMemoryBytes = (nav.deviceMemory ?? 4) * 1024 * 1024 * 1024;
        const perf = performance as Performance & {
          memory?: { usedJSHeapSize?: number; jsHeapSizeLimit?: number };
        };
        const jsHeapUsed = perf.memory?.usedJSHeapSize ?? 0;
        const jsHeapTotal = perf.memory?.jsHeapSizeLimit ?? deviceMemoryBytes;
        const jsHeapAvailable = Math.max(0, jsHeapTotal - jsHeapUsed);
        setI64(m, outInfoPtr, jsHeapTotal);
        setI64(m, outInfoPtr + 8, jsHeapAvailable);
        setI64(m, outInfoPtr + 16, jsHeapUsed);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iii');
  }

  private registerFileListDirectory(): number {
    const m = this.m;
    return m.addFunction((dirPathPtr: number, outEntriesPtr: number, countPtr: number, _userData: number) => {
      try {
        if (!fsOf(m) || !countPtr) return RAC_ERROR_INVALID_ARGUMENT;
        const entries = listDirectoryEntries(m, m.UTF8ToString(dirPathPtr));
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
          const safeName = entry.name.slice(0, RAC_DIRECTORY_ENTRY_NAME_MAX - 1);
          m.stringToUTF8(safeName, entryPtr + layout.nameOffset, RAC_DIRECTORY_ENTRY_NAME_MAX);
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

  private registerIsNonEmptyDirectory(): number {
    const m = this.m;
    return m.addFunction((pathPtr: number, _userData: number) => {
      try {
        if (!fsOf(m)) return 0;
        const entries = listDirectoryEntries(m, m.UTF8ToString(pathPtr));
        return entries && entries.length > 0 ? 1 : 0;
      } catch {
        return 0;
      }
    }, 'iii');
  }

  private registerGetVendorId(): number {
    const m = this.m;
    return m.addFunction((outBufferPtr: number, bufferSize: number, _userData: number) => {
      try {
        if (!outBufferPtr || bufferSize < 37) return RAC_ERROR_INVALID_ARGUMENT;
        m.stringToUTF8(stableVendorId(this.secure), outBufferPtr, bufferSize);
        return RAC_OK;
      } catch {
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiii');
  }

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

        if (outTaskIdPtr) {
          const len = m.lengthBytesUTF8(taskId) + 1;
          const idPtr = m._malloc(len);
          m.stringToUTF8(taskId, idPtr, len);
          m.setValue(outTaskIdPtr, idPtr, '*');
        }

        const controller = new AbortController();
        httpDownloadTasks.set(taskId, controller);
        void runHttpDownload(m, { url, dest, progressCbPtr, completeCbPtr, cbUserData, controller })
          .finally(() => httpDownloadTasks.delete(taskId));
        return RAC_OK;
      } catch (error) {
        logger.warning(`http_download start failed: ${error instanceof Error ? error.message : String(error)}`);
        return RAC_ERROR_PLATFORM;
      }
    }, 'iiiiiiii');
  }

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

function writeBytes(m: PlatformAdapterModule, src: Uint8Array, destPtr: number): void {
  if (m.HEAPU8) { m.HEAPU8.set(src, destPtr); return; }
  for (let i = 0; i < src.length; i++) m.setValue(destPtr + i, src[i], 'i8');
}

function readBytes(m: PlatformAdapterModule, srcPtr: number, length: number): Uint8Array {
  if (m.HEAPU8) return m.HEAPU8.slice(srcPtr, srcPtr + length);
  const out = new Uint8Array(length);
  for (let i = 0; i < length; i++) out[i] = m.getValue(srcPtr + i, 'i8') & 0xff;
  return out;
}

interface StreamingFS {
  open(path: string, flags: string): unknown;
  write(stream: unknown, buffer: ArrayBufferView, offset: number, length: number, position?: number): number;
  read?(stream: unknown, buffer: ArrayBufferView, offset: number, length: number, position?: number): number;
  close(stream: unknown): void;
  mkdirTree?(path: string): void;
  analyzePath?(path: string): { exists: boolean };
  stat?(path: string): { size?: number };
}

const OPFS_CHUNK = 8 * 1024 * 1024;

interface OpfsDirectoryHandle {
  getDirectoryHandle(name: string, options?: { create?: boolean }): Promise<OpfsDirectoryHandle>;
  getFileHandle(name: string, options?: { create?: boolean }): Promise<OpfsFileHandle>;
}
interface OpfsSyncAccessHandle {
  write(buffer: ArrayBufferView, options?: { at?: number }): number;
  truncate(size: number): void;
  flush(): void;
  close(): void;
}
interface OpfsWritable {
  write(data: ArrayBufferView): Promise<void>;
  close(): Promise<void>;
}
interface OpfsFileHandle {
  getFile(): Promise<{ size: number; slice(start: number, end: number): { arrayBuffer(): Promise<ArrayBuffer> } }>;
  createSyncAccessHandle?(): Promise<OpfsSyncAccessHandle>;
  createWritable?(options?: { keepExistingData?: boolean }): Promise<OpfsWritable>;
}

async function opfsRoot(): Promise<OpfsDirectoryHandle | null> {
  const storage = (globalThis as { navigator?: { storage?: { getDirectory?: () => Promise<OpfsDirectoryHandle> } } }).navigator?.storage;
  if (!storage?.getDirectory) return null;
  try {
    return await storage.getDirectory();
  } catch {
    return null;
  }
}

async function opfsFileHandle(dest: string, create: boolean): Promise<OpfsFileHandle | null> {
  const root = await opfsRoot();
  if (!root) return null;
  const parts = `${OPFS_ROOT}/${dest.replace(/^\/+/, '')}`.split('/').filter(Boolean);
  const fileName = parts.pop();
  if (!fileName) return null;
  let dir = root;
  for (const part of parts) {
    try {
      dir = await dir.getDirectoryHandle(part, { create });
    } catch {
      return null;
    }
  }
  try {
    return await dir.getFileHandle(fileName, { create });
  } catch {
    return null;
  }
}

async function hydrateFromOpfs(fs: StreamingFS, dest: string): Promise<number> {
  const handle = await opfsFileHandle(dest, false);
  if (!handle) return 0;
  let file: { size: number; slice(start: number, end: number): { arrayBuffer(): Promise<ArrayBuffer> } };
  try {
    file = await handle.getFile();
  } catch {
    return 0;
  }
  const size = file.size;
  if (size <= 0) return 0;

  const parent = dest.slice(0, dest.lastIndexOf('/')) || '/';
  try { fs.mkdirTree?.(parent); } catch {}
  const stream = fs.open(dest, 'w');
  try {
    let position = 0;
    while (position < size) {
      const end = Math.min(position + OPFS_CHUNK, size);
      const chunk = new Uint8Array(await file.slice(position, end).arrayBuffer());
      fs.write(stream, chunk, 0, chunk.length, position);
      position += chunk.length;
      if (chunk.length === 0) break;
    }
  } finally {
    fs.close(stream);
  }
  logger.info(`opfs hydrate hit: ${dest} (${size} bytes)`);
  return size;
}

async function mirrorToOpfs(fs: StreamingFS, dest: string): Promise<void> {
  const size = memfsFileSize(fs, dest);
  if (size <= 0) {
    logger.warning(`opfs mirror skipped: ${dest} has no MEMFS bytes`);
    return;
  }
  const handle = await opfsFileHandle(dest, true);
  if (!handle) {
    logger.warning(`opfs mirror skipped: cannot open OPFS handle for ${dest}`);
    return;
  }

  const readChunk = readChunkFn(fs);
  if (!readChunk) {
    logger.warning(`opfs mirror skipped: FS has no readable chunk API for ${dest}`);
    return;
  }

  if (handle.createSyncAccessHandle) {
    const access = await handle.createSyncAccessHandle();
    const stream = fs.open(dest, 'r');
    try {
      access.truncate(0);
      const buffer = new Uint8Array(OPFS_CHUNK);
      let position = 0;
      while (position < size) {
        const length = Math.min(OPFS_CHUNK, size - position);
        const read = readChunk(stream, buffer, length, position);
        if (read <= 0) break;
        access.write(buffer.subarray(0, read), { at: position });
        position += read;
      }
      access.flush();
    } finally {
      access.close();
      fs.close(stream);
    }
    logger.info(`opfs mirror ok (sync): ${dest} (${size} bytes)`);
    return;
  }

  if (handle.createWritable) {
    const writable = await handle.createWritable();
    const stream = fs.open(dest, 'r');
    try {
      const buffer = new Uint8Array(OPFS_CHUNK);
      let position = 0;
      while (position < size) {
        const length = Math.min(OPFS_CHUNK, size - position);
        const read = readChunk(stream, buffer, length, position);
        if (read <= 0) break;
        await writable.write(buffer.subarray(0, read));
        position += read;
      }
    } finally {
      fs.close(stream);
      await writable.close();
    }
    logger.info(`opfs mirror ok (writable): ${dest} (${size} bytes)`);
    return;
  }

  logger.warning(`opfs mirror skipped: no OPFS write API available for ${dest}`);
}

type ChunkReader = (stream: unknown, buffer: Uint8Array, length: number, position: number) => number;

function readChunkFn(fs: StreamingFS): ChunkReader | null {
  const read = fs.read;
  if (typeof read !== 'function') return null;
  return (stream, buffer, length, position) => read(stream, buffer, 0, length, position);
}

function streamingFsOf(m: PlatformAdapterModule): StreamingFS | null {
  const fs = (m as { FS?: unknown }).FS as Partial<StreamingFS> | undefined;
  if (fs && typeof fs.open === 'function' && typeof fs.write === 'function' && typeof fs.close === 'function') {
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
      try { m._free(pathPtr); } catch {}
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
    try { fs.mkdirTree?.(parent); } catch {}

    const hydrated = await hydrateFromOpfs(fs, dest);
    if (hydrated > 0) {
      invokeProgressCallback(m, progressCbPtr, hydrated, hydrated, cbUserData);
      invokeCompleteCallback(m, completeCbPtr, RAC_OK, dest, cbUserData);
      return;
    }

    const existing = memfsFileSize(fs, dest);
    const headers: Record<string, string> = {};
    if (existing > 0) headers.Range = `bytes=${existing}-`;

    const response = await fetch(url, { headers, signal: controller.signal });

    if (existing > 0 && response.status === 416) {
      invokeCompleteCallback(m, completeCbPtr, RAC_OK, dest, cbUserData);
      return;
    }

    let received = 0;
    let position = 0;
    if (existing > 0 && response.status === 206) {
      received = existing;
      position = existing;
      stream = fs.open(dest, 'r+');
    } else {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
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
    try {
      await mirrorToOpfs(fs, dest);
    } catch (error) {
      logger.warning(`opfs mirror failed for '${dest}': ${error instanceof Error ? error.message : String(error)}`);
    }
    invokeCompleteCallback(m, completeCbPtr, RAC_OK, dest, cbUserData);
  } catch (error) {
    if (stream) {
      try { fs.close(stream); } catch {}
    }
    const aborted = controller.signal.aborted
      || (error instanceof DOMException && error.name === 'AbortError');
    if (!aborted) {
      logger.warning(`http_download '${url}' failed: ${error instanceof Error ? error.message : String(error)}`);
    }
    invokeCompleteCallback(m, completeCbPtr, aborted ? RAC_ERROR_CANCELLED : RAC_ERROR_PLATFORM, null, cbUserData);
  }
}

interface DirectoryEntryInfo { name: string; isDir: boolean; sizeBytes: number; }
interface DirectoryEntryLayout { size: number; nameOffset: number; isDirOffset: number; sizeBytesOffset: number; }

interface EmscriptenFS {
  analyzePath(path: string): { exists: boolean };
  readFile(path: string): Uint8Array;
  writeFile(path: string, data: Uint8Array): void;
  unlink(path: string): void;
  readdir?(path: string): string[];
  stat?(path: string): { mode?: number; size?: number };
  isDir?(mode: number): boolean;
}

function fsOf(m: PlatformAdapterModule): EmscriptenFS | undefined {
  return m.FS as EmscriptenFS | undefined;
}

function joinPath(parent: string, name: string): string {
  return parent.endsWith('/') ? `${parent}${name}` : `${parent}/${name}`;
}

function listDirectoryEntries(m: PlatformAdapterModule, dirPath: string): DirectoryEntryInfo[] | null {
  const fs = fsOf(m);
  if (!fs?.readdir) return null;
  if (!fs.analyzePath(dirPath).exists) return null;
  const names = fs.readdir(dirPath).filter((name) => name !== '.' && name !== '..' && !name.startsWith('.'));
  return names.map((name) => {
    const path = joinPath(dirPath, name);
    const stat = fs.stat?.(path);
    const isDir = typeof stat?.mode === 'number' && typeof fs.isDir === 'function' ? fs.isDir(stat.mode) : false;
    return { name, isDir, sizeBytes: isDir ? 0 : stat?.size ?? 0 };
  });
}

function directoryEntryLayout(m: PlatformAdapterModule): DirectoryEntryLayout {
  const record = m as unknown as Record<string, unknown>;
  const required = (name: string): number => {
    const fn = record[name];
    if (typeof fn !== 'function') throw new Error(`WASM module missing ${name}`);
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

function stableVendorId(store: SecureStore): string {
  const key = 'vendor_id';
  const existing = store.get(key);
  if (existing) return existing;
  const generated = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  store.set(key, generated);
  return generated;
}
