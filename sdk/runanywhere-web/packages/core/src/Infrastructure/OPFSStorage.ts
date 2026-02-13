/**
 * RunAnywhere Web SDK - OPFS (Origin Private File System) Storage
 *
 * Persistent model storage using the browser's Origin Private File System.
 * OPFS provides a sandboxed, high-performance file system for large model files
 * that persists across page reloads (unlike Emscripten MEMFS).
 *
 * Supports nested paths: keys containing `/` are treated as subdirectory paths.
 *   e.g. `saveModel('org/model/file.gguf', data)` creates `models/org/model/file.gguf`
 *
 * Fallback: If OPFS is not available, models stay in MEMFS (volatile).
 *
 * Usage:
 *   import { OPFSStorage } from '@runanywhere/web';
 *
 *   const storage = new OPFSStorage();
 *   await storage.saveModel('whisper-base', modelArrayBuffer);
 *   await storage.saveModel('org/model/file.gguf', modelArrayBuffer);
 *   const data = await storage.loadModel('whisper-base');
 *   const models = await storage.listModels();
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('OPFSStorage');

/** OPFS root directory name for model storage. */
const MODELS_DIR = 'models';

export interface StoredModelInfo {
  id: string;
  sizeBytes: number;
  lastModified: number;
}

/**
 * OPFSStorage - Persistent model file storage using Origin Private File System.
 *
 * Keys can be flat (`whisper-base`) or nested (`org/model/file.gguf`).
 * Nested keys are stored in the corresponding subdirectory hierarchy under the
 * `models/` OPFS root.
 */
export class OPFSStorage {
  private rootDir: FileSystemDirectoryHandle | null = null;
  private modelsDir: FileSystemDirectoryHandle | null = null;
  private _isAvailable: boolean | null = null;

  /**
   * Check if OPFS is available in this browser.
   */
  static get isSupported(): boolean {
    return typeof navigator !== 'undefined' &&
           'storage' in navigator &&
           'getDirectory' in (navigator.storage || {});
  }

  /**
   * Initialize OPFS storage. Must be called before other methods.
   *
   * @returns true if OPFS was initialized, false if not available
   */
  async initialize(): Promise<boolean> {
    if (this._isAvailable !== null) return this._isAvailable;

    if (!OPFSStorage.isSupported) {
      logger.warning('OPFS not available in this browser. Models will use volatile MEMFS.');
      this._isAvailable = false;
      return false;
    }

    try {
      this.rootDir = await navigator.storage.getDirectory();
      this.modelsDir = await this.rootDir.getDirectoryHandle(MODELS_DIR, { create: true });
      this._isAvailable = true;
      logger.info('OPFS storage initialized');
      return true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`OPFS initialization failed: ${msg}`);
      this._isAvailable = false;
      return false;
    }
  }

  get isAvailable(): boolean {
    return this._isAvailable === true;
  }

  // ---------------------------------------------------------------------------
  // Core operations
  // ---------------------------------------------------------------------------

  /**
   * Save model data to OPFS.
   *
   * Supports nested paths: `saveModel('org/model/file.gguf', data)` creates
   * `models/org/model/` directories and writes `file.gguf`.
   *
   * @param key - Model identifier or nested path (used as filename / path)
   * @param data - Model file data
   */
  async saveModel(key: string, data: ArrayBuffer): Promise<void> {
    if (!this.modelsDir) throw new Error('OPFS not initialized. Call initialize() first.');

    logger.info(`Saving model to OPFS: ${key} (${(data.byteLength / 1024 / 1024).toFixed(1)} MB)`);

    const dir = await this.resolveParentDir(key, /* create */ true);
    const filename = this.resolveFilename(key);

    const fileHandle = await dir.getFileHandle(filename, { create: true });
    const writable = await fileHandle.createWritable();

    try {
      await writable.write(data);
    } finally {
      await writable.close();
    }

    logger.info(`Model saved: ${key}`);
  }

  /**
   * Load model data from OPFS.
   *
   * @param key - Model identifier or nested path
   * @returns Model data, or null if not found
   */
  async loadModel(key: string): Promise<ArrayBuffer | null> {
    if (!this.modelsDir) return null;

    try {
      const dir = await this.resolveParentDir(key, /* create */ false);
      const filename = this.resolveFilename(key);
      const fileHandle = await dir.getFileHandle(filename);
      const file = await fileHandle.getFile();
      logger.info(`Loaded model from OPFS: ${key} (${(file.size / 1024 / 1024).toFixed(1)} MB)`);
      return await file.arrayBuffer();
    } catch {
      return null; // File not found
    }
  }

  /**
   * Check if a model exists in OPFS.
   *
   * @param key - Model identifier or nested path
   */
  async hasModel(key: string): Promise<boolean> {
    if (!this.modelsDir) return false;

    try {
      const dir = await this.resolveParentDir(key, /* create */ false);
      const filename = this.resolveFilename(key);
      await dir.getFileHandle(filename);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Delete a model from OPFS.
   *
   * @param key - Model identifier or nested path
   */
  async deleteModel(key: string): Promise<void> {
    if (!this.modelsDir) return;

    try {
      const dir = await this.resolveParentDir(key, /* create */ false);
      const filename = this.resolveFilename(key);
      await dir.removeEntry(filename);
      logger.info(`Deleted model from OPFS: ${key}`);
    } catch {
      // File doesn't exist, ignore
    }
  }

  /**
   * Get the byte size of a stored file without reading it into memory.
   *
   * @param key - Model identifier or nested path
   * @returns File size in bytes, or null if the file doesn't exist
   */
  async getFileSize(key: string): Promise<number | null> {
    if (!this.modelsDir) return null;

    try {
      const dir = await this.resolveParentDir(key, /* create */ false);
      const filename = this.resolveFilename(key);
      const fileHandle = await dir.getFileHandle(filename);
      const file = await fileHandle.getFile();
      return file.size;
    } catch {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Bulk operations
  // ---------------------------------------------------------------------------

  /**
   * List all stored models (top-level files only).
   */
  async listModels(): Promise<StoredModelInfo[]> {
    if (!this.modelsDir) return [];

    const models: StoredModelInfo[] = [];

    for await (const [name, handle] of (this.modelsDir as any).entries()) {
      if (handle.kind === 'file') {
        const file = await (handle as FileSystemFileHandle).getFile();
        models.push({
          id: name,
          sizeBytes: file.size,
          lastModified: file.lastModified,
        });
      }
    }

    return models;
  }

  /**
   * Get total storage usage.
   */
  async getStorageUsage(): Promise<{ usedBytes: number; quotaBytes: number }> {
    if (!navigator.storage?.estimate) {
      return { usedBytes: 0, quotaBytes: 0 };
    }

    const estimate = await navigator.storage.estimate();
    return {
      usedBytes: estimate.usage ?? 0,
      quotaBytes: estimate.quota ?? 0,
    };
  }

  /**
   * Clear all stored models.
   */
  async clearAll(): Promise<void> {
    if (!this.rootDir) return;

    try {
      await this.rootDir.removeEntry(MODELS_DIR, { recursive: true });
      this.modelsDir = await this.rootDir.getDirectoryHandle(MODELS_DIR, { create: true });
      logger.info('All OPFS models cleared');
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to clear OPFS: ${msg}`);
    }
  }

  // ---------------------------------------------------------------------------
  // Path resolution helpers
  // ---------------------------------------------------------------------------

  /**
   * For a key that may contain `/`, traverse (and optionally create) the
   * intermediate directories and return the parent directory handle.
   *
   * For a flat key (no `/`) this returns `this.modelsDir` directly.
   */
  private async resolveParentDir(
    key: string,
    create: boolean,
  ): Promise<FileSystemDirectoryHandle> {
    const dir = this.modelsDir!;

    if (!key.includes('/')) return dir;

    const parts = key.split('/');
    // All parts except the last are directory segments
    let current = dir;
    for (let i = 0; i < parts.length - 1; i++) {
      current = await current.getDirectoryHandle(parts[i], { create });
    }
    return current;
  }

  /**
   * Extract the final filename segment from a key.
   *
   * For flat keys this returns a sanitized version of the whole key.
   * For nested keys (`org/model/file.gguf`) this returns the last segment
   * with only the filename portion sanitized (directory separators are handled
   * by `resolveParentDir`).
   */
  private resolveFilename(key: string): string {
    const raw = key.includes('/') ? key.split('/').pop()! : key;
    return this.sanitizeFilename(raw);
  }

  /**
   * Sanitize a single filename segment.
   *
   * Only strips characters that are invalid in filenames. Keeps `.`, `-`, `_`,
   * and all alphanumeric characters. This is intentionally lenient compared to
   * the old implementation which also stripped `/` — directory separators are
   * now handled structurally by `resolveParentDir`.
   */
  private sanitizeFilename(name: string): string {
    // Replace characters that are problematic in filenames across platforms.
    // Keeps: alphanumeric, dot, dash, underscore, plus, space, parentheses.
    return name.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_');
  }
}
