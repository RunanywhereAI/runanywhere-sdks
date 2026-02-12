/**
 * RunAnywhere Web SDK - OPFS (Origin Private File System) Storage
 *
 * Persistent model storage using the browser's Origin Private File System.
 * OPFS provides a sandboxed, high-performance file system for large model files
 * that persists across page reloads (unlike Emscripten MEMFS).
 *
 * Fallback: If OPFS is not available, models stay in MEMFS (volatile).
 *
 * Usage:
 *   import { OPFSStorage } from '@runanywhere/web';
 *
 *   const storage = new OPFSStorage();
 *   await storage.saveModel('whisper-base', modelArrayBuffer);
 *   const data = await storage.loadModel('whisper-base');
 *   const models = await storage.listModels();
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('OPFSStorage');

export interface StoredModelInfo {
  id: string;
  sizeBytes: number;
  lastModified: number;
}

/**
 * OPFSStorage - Persistent model file storage using Origin Private File System.
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
      this.modelsDir = await this.rootDir.getDirectoryHandle('runanywhere-models', { create: true });
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

  /**
   * Save model data to OPFS.
   *
   * @param modelId - Unique model identifier (used as filename)
   * @param data - Model file data
   */
  async saveModel(modelId: string, data: ArrayBuffer): Promise<void> {
    if (!this.modelsDir) throw new Error('OPFS not initialized. Call initialize() first.');

    const filename = this.sanitizeFilename(modelId);
    logger.info(`Saving model to OPFS: ${filename} (${(data.byteLength / 1024 / 1024).toFixed(1)} MB)`);

    const fileHandle = await this.modelsDir.getFileHandle(filename, { create: true });
    const writable = await fileHandle.createWritable();

    try {
      await writable.write(data);
    } finally {
      await writable.close();
    }

    logger.info(`Model saved: ${filename}`);
  }

  /**
   * Load model data from OPFS.
   *
   * @param modelId - Model identifier
   * @returns Model data, or null if not found
   */
  async loadModel(modelId: string): Promise<ArrayBuffer | null> {
    if (!this.modelsDir) return null;

    const filename = this.sanitizeFilename(modelId);

    try {
      const fileHandle = await this.modelsDir.getFileHandle(filename);
      const file = await fileHandle.getFile();
      logger.info(`Loaded model from OPFS: ${filename} (${(file.size / 1024 / 1024).toFixed(1)} MB)`);
      return await file.arrayBuffer();
    } catch {
      return null; // File not found
    }
  }

  /**
   * Check if a model exists in OPFS.
   */
  async hasModel(modelId: string): Promise<boolean> {
    if (!this.modelsDir) return false;

    const filename = this.sanitizeFilename(modelId);
    try {
      await this.modelsDir.getFileHandle(filename);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Delete a model from OPFS.
   */
  async deleteModel(modelId: string): Promise<void> {
    if (!this.modelsDir) return;

    const filename = this.sanitizeFilename(modelId);
    try {
      await this.modelsDir.removeEntry(filename);
      logger.info(`Deleted model from OPFS: ${filename}`);
    } catch {
      // File doesn't exist, ignore
    }
  }

  /**
   * List all stored models.
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
      await this.rootDir.removeEntry('runanywhere-models', { recursive: true });
      this.modelsDir = await this.rootDir.getDirectoryHandle('runanywhere-models', { create: true });
      logger.info('All OPFS models cleared');
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to clear OPFS: ${msg}`);
    }
  }

  private sanitizeFilename(id: string): string {
    return id.replace(/[^a-zA-Z0-9._-]/g, '_');
  }
}
