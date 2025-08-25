/**
 * Model Cache implementation using IndexedDB for persistent storage
 * and memory cache for fast access
 */

import { logger } from '../utils/logger';

const DB_NAME = 'runanywhere-model-cache';
const DB_VERSION = 1;
const STORE_NAME = 'models';

export interface CachedModel {
  id: string;
  data: ArrayBuffer;
  timestamp: number;
  size: number;
  metadata?: {
    version?: string;
    type?: string;
  };
}

export class ModelCache {
  private memory = new Map<string, ArrayBuffer>();
  private db?: IDBDatabase;
  private initPromise?: Promise<void>;
  private maxMemorySize = 500 * 1024 * 1024; // 500MB default memory cache limit
  private currentMemorySize = 0;

  async initialize(): Promise<void> {
    // Prevent multiple initialization
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = this.openDatabase();
    await this.initPromise;
  }

  private async openDatabase(): Promise<void> {
    return new Promise((resolve, reject) => {
      // Check if IndexedDB is available
      if (!('indexedDB' in window)) {
        logger.warn('IndexedDB not available, using memory cache only', 'ModelCache');
        resolve();
        return;
      }

      const request = indexedDB.open(DB_NAME, DB_VERSION);

      request.onerror = () => {
        logger.error('Failed to open IndexedDB', 'ModelCache', {
          error: request.error
        });
        // Don't reject, just use memory cache
        resolve();
      };

      request.onsuccess = () => {
        this.db = request.result;
        logger.info('IndexedDB opened successfully', 'ModelCache');

        // Handle database errors
        this.db.onerror = (event) => {
          logger.error('Database error', 'ModelCache', { event });
        };

        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;

        // Create object store if it doesn't exist
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const store = db.createObjectStore(STORE_NAME, { keyPath: 'id' });

          // Create indexes for efficient queries
          store.createIndex('timestamp', 'timestamp', { unique: false });
          store.createIndex('size', 'size', { unique: false });

          logger.info('Created object store for models', 'ModelCache');
        }
      };
    });
  }

  async get(modelId: string): Promise<ArrayBuffer | null> {
    // Check memory cache first
    if (this.memory.has(modelId)) {
      logger.debug(`Model ${modelId} found in memory cache`, 'ModelCache');
      return this.memory.get(modelId)!;
    }

    // Check IndexedDB
    if (this.db) {
      try {
        const data = await this.getFromDB(modelId);
        if (data) {
          // Add to memory cache if there's space
          await this.addToMemoryCache(modelId, data);
          return data;
        }
      } catch (error) {
        logger.error(`Failed to get model ${modelId} from IndexedDB`, 'ModelCache', {
          error
        });
      }
    }

    return null;
  }

  private async getFromDB(modelId: string): Promise<ArrayBuffer | null> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve(null);
        return;
      }

      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.get(modelId);

      request.onsuccess = () => {
        const result = request.result as CachedModel | undefined;
        if (result) {
          logger.debug(`Model ${modelId} found in IndexedDB`, 'ModelCache', {
            size: result.size,
            timestamp: new Date(result.timestamp).toISOString()
          });
          resolve(result.data);
        } else {
          resolve(null);
        }
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  async set(modelId: string, data: ArrayBuffer): Promise<void> {
    const size = data.byteLength;

    // Add to memory cache
    await this.addToMemoryCache(modelId, data);

    // Store in IndexedDB
    if (this.db) {
      try {
        await this.saveToDB(modelId, data);
        logger.info(`Model ${modelId} cached successfully`, 'ModelCache', {
          size,
          memoryCache: true,
          persistentCache: true
        });
      } catch (error) {
        logger.error(`Failed to save model ${modelId} to IndexedDB`, 'ModelCache', {
          error
        });
      }
    } else {
      logger.info(`Model ${modelId} cached in memory only`, 'ModelCache', {
        size,
        memoryCache: true,
        persistentCache: false
      });
    }
  }

  private async saveToDB(modelId: string, data: ArrayBuffer): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve();
        return;
      }

      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const store = transaction.objectStore(STORE_NAME);

      const cachedModel: CachedModel = {
        id: modelId,
        data,
        timestamp: Date.now(),
        size: data.byteLength
      };

      const request = store.put(cachedModel);

      request.onsuccess = () => {
        resolve();
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  private async addToMemoryCache(modelId: string, data: ArrayBuffer): Promise<void> {
    const size = data.byteLength;

    // Check if we need to evict models to make space
    if (this.currentMemorySize + size > this.maxMemorySize) {
      await this.evictFromMemory(size);
    }

    // Add to memory cache
    this.memory.set(modelId, data);
    this.currentMemorySize += size;

    logger.debug(`Added model ${modelId} to memory cache`, 'ModelCache', {
      modelSize: size,
      totalMemorySize: this.currentMemorySize,
      maxMemorySize: this.maxMemorySize
    });
  }

  private async evictFromMemory(requiredSpace: number): Promise<void> {
    const entries = Array.from(this.memory.entries());
    let freedSpace = 0;

    // Simple LRU eviction - remove oldest entries first
    // In a production implementation, we'd track access times
    for (const [id, buffer] of entries) {
      if (freedSpace >= requiredSpace) break;

      const size = buffer.byteLength;
      this.memory.delete(id);
      this.currentMemorySize -= size;
      freedSpace += size;

      logger.debug(`Evicted model ${id} from memory cache`, 'ModelCache', {
        freedSpace,
        requiredSpace
      });
    }
  }

  async delete(modelId: string): Promise<void> {
    // Remove from memory cache
    const memoryData = this.memory.get(modelId);
    if (memoryData) {
      this.currentMemorySize -= memoryData.byteLength;
      this.memory.delete(modelId);
    }

    // Remove from IndexedDB
    if (this.db) {
      try {
        await this.deleteFromDB(modelId);
        logger.info(`Model ${modelId} deleted from cache`, 'ModelCache');
      } catch (error) {
        logger.error(`Failed to delete model ${modelId} from IndexedDB`, 'ModelCache', {
          error
        });
      }
    }
  }

  private async deleteFromDB(modelId: string): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve();
        return;
      }

      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.delete(modelId);

      request.onsuccess = () => {
        resolve();
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  async clear(): Promise<void> {
    // Clear memory cache
    this.memory.clear();
    this.currentMemorySize = 0;

    // Clear IndexedDB
    if (this.db) {
      try {
        await this.clearDB();
        logger.info('All models cleared from cache', 'ModelCache');
      } catch (error) {
        logger.error('Failed to clear IndexedDB', 'ModelCache', { error });
      }
    }
  }

  private async clearDB(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve();
        return;
      }

      const transaction = this.db.transaction([STORE_NAME], 'readwrite');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.clear();

      request.onsuccess = () => {
        resolve();
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  async getSize(): Promise<number> {
    let totalSize = this.currentMemorySize;

    if (this.db) {
      try {
        const dbSize = await this.getDBSize();
        totalSize += dbSize;
      } catch (error) {
        logger.error('Failed to get DB size', 'ModelCache', { error });
      }
    }

    return totalSize;
  }

  private async getDBSize(): Promise<number> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve(0);
        return;
      }

      let totalSize = 0;
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.openCursor();

      request.onsuccess = (event) => {
        const cursor = (event.target as IDBRequest).result;
        if (cursor) {
          const model = cursor.value as CachedModel;
          totalSize += model.size;
          cursor.continue();
        } else {
          resolve(totalSize);
        }
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  async getKeys(): Promise<string[]> {
    const memoryKeys = Array.from(this.memory.keys());

    if (this.db) {
      try {
        const dbKeys = await this.getDBKeys();
        // Merge and dedupe keys
        const allKeys = new Set([...memoryKeys, ...dbKeys]);
        return Array.from(allKeys);
      } catch (error) {
        logger.error('Failed to get DB keys', 'ModelCache', { error });
        return memoryKeys;
      }
    }

    return memoryKeys;
  }

  private async getDBKeys(): Promise<string[]> {
    return new Promise((resolve, reject) => {
      if (!this.db) {
        resolve([]);
        return;
      }

      const keys: string[] = [];
      const transaction = this.db.transaction([STORE_NAME], 'readonly');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.openCursor();

      request.onsuccess = (event) => {
        const cursor = (event.target as IDBRequest).result;
        if (cursor) {
          keys.push(cursor.key as string);
          cursor.continue();
        } else {
          resolve(keys);
        }
      };

      request.onerror = () => {
        reject(request.error);
      };
    });
  }

  setMaxMemorySize(bytes: number): void {
    this.maxMemorySize = bytes;
    logger.info(`Max memory cache size set to ${bytes} bytes`, 'ModelCache');
  }

  getMemoryCacheInfo(): {
    currentSize: number;
    maxSize: number;
    usage: number;
    modelCount: number;
  } {
    return {
      currentSize: this.currentMemorySize,
      maxSize: this.maxMemorySize,
      usage: this.currentMemorySize / this.maxMemorySize,
      modelCount: this.memory.size
    };
  }

  async clearCache(modelId?: string): Promise<void> {
    if (modelId) {
      // Clear specific model
      await this.delete(modelId);
    } else {
      // Clear all models
      await this.clear();
    }
  }
}
