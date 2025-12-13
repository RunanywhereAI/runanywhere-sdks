// Model Cache for storing and retrieving AI models efficiently
import type { Result } from '@runanywhere/core';

export interface ModelMetadata {
  id: string;
  name: string;
  version: string;
  size: number;
  type: 'vad' | 'whisper' | 'llm' | 'other';
  format: 'onnx' | 'tflite' | 'gguf' | 'other';
  checksum?: string;
  url?: string;
  lastAccessed?: number;
  accessCount?: number;
  tags?: string[];
}

export interface CachedModel {
  id: string;
  data: ArrayBuffer;
  metadata: ModelMetadata;
  timestamp: number;
  accessCount: number;
}

export interface CacheConfig {
  maxSize: number; // Maximum cache size in bytes
  maxAge: number; // Maximum age in milliseconds
  maxItems: number; // Maximum number of items
  memoryThreshold: number; // Memory cache threshold in bytes
  enablePersistence: boolean; // Enable IndexedDB persistence
}

export class ModelCache {
  private db: IDBDatabase | null = null;
  private memoryCache = new Map<string, ArrayBuffer>();
  private metadata = new Map<string, ModelMetadata>();
  private config: CacheConfig;
  private currentMemorySize = 0;
  private dbName = 'RunAnywhereModelCache';
  private dbVersion = 1;

  constructor(config: Partial<CacheConfig> = {}) {
    this.config = {
      maxSize: 500 * 1024 * 1024, // 500MB default
      maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days default
      maxItems: 50,
      memoryThreshold: 50 * 1024 * 1024, // 50MB in memory
      enablePersistence: true,
      ...config
    };
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      if (this.config.enablePersistence && typeof window !== 'undefined') {
        await this.initializeIndexedDB();
      }
      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  private async initializeIndexedDB(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!('indexedDB' in window)) {
        reject(new Error('IndexedDB not supported'));
        return;
      }

      const request = indexedDB.open(this.dbName, this.dbVersion);

      request.onerror = () => {
        reject(new Error(`IndexedDB error: ${request.error?.message}`));
      };

      request.onsuccess = () => {
        this.db = request.result;
        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;

        // Create models store
        if (!db.objectStoreNames.contains('models')) {
          const modelsStore = db.createObjectStore('models', { keyPath: 'id' });
          modelsStore.createIndex('type', 'metadata.type', { unique: false });
          modelsStore.createIndex('timestamp', 'timestamp', { unique: false });
          modelsStore.createIndex('lastAccessed', 'metadata.lastAccessed', { unique: false });
        }

        // Create metadata store for quick lookups
        if (!db.objectStoreNames.contains('metadata')) {
          db.createObjectStore('metadata', { keyPath: 'id' });
        }
      };
    });
  }

  async cacheModel(
    modelId: string,
    modelData: ArrayBuffer,
    metadata: ModelMetadata
  ): Promise<Result<void, Error>> {
    try {
      // Update metadata
      const enrichedMetadata: ModelMetadata = {
        ...metadata,
        lastAccessed: Date.now(),
        accessCount: (metadata.accessCount || 0) + 1
      };

      // Check if model fits in memory cache
      const modelSize = modelData.byteLength;
      if (modelSize <= this.config.memoryThreshold) {
        // Add to memory cache
        this.memoryCache.set(modelId, modelData);
        this.metadata.set(modelId, enrichedMetadata);
        this.currentMemorySize += modelSize;

        // Evict if memory cache is too large
        await this.evictMemoryCache();
      }

      // Persist to IndexedDB if enabled
      if (this.config.enablePersistence && this.db) {
        const cachedModel: CachedModel = {
          id: modelId,
          data: modelData,
          metadata: enrichedMetadata,
          timestamp: Date.now(),
          accessCount: enrichedMetadata.accessCount || 0
        };

        await this.persistModel(cachedModel);
        await this.cleanupPersistentCache();
      }

      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async getCachedModel(modelId: string): Promise<Result<ArrayBuffer | null, Error>> {
    try {
      // Check memory cache first
      if (this.memoryCache.has(modelId)) {
        const modelData = this.memoryCache.get(modelId)!;

        // Update access metadata
        const metadata = this.metadata.get(modelId);
        if (metadata) {
          metadata.lastAccessed = Date.now();
          metadata.accessCount = (metadata.accessCount || 0) + 1;
        }

        return { success: true, value: modelData };
      }

      // Check persistent cache
      if (this.config.enablePersistence && this.db) {
        const cachedModel = await this.retrievePersistedModel(modelId);
        if (cachedModel) {
          // Add to memory cache if it fits
          if (cachedModel.data.byteLength <= this.config.memoryThreshold) {
            this.memoryCache.set(modelId, cachedModel.data);
            this.metadata.set(modelId, cachedModel.metadata);
            this.currentMemorySize += cachedModel.data.byteLength;
            await this.evictMemoryCache();
          }

          // Update access count in persistent storage
          await this.updateAccessCount(modelId);

          return { success: true, value: cachedModel.data };
        }
      }

      return { success: true, value: null };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async getModelMetadata(modelId: string): Promise<Result<ModelMetadata | null, Error>> {
    try {
      // Check memory first
      if (this.metadata.has(modelId)) {
        return { success: true, value: this.metadata.get(modelId)! };
      }

      // Check persistent storage
      if (this.config.enablePersistence && this.db) {
        const metadata = await this.retrieveMetadata(modelId);
        return { success: true, value: metadata };
      }

      return { success: true, value: null };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async listCachedModels(): Promise<Result<ModelMetadata[], Error>> {
    try {
      const models: ModelMetadata[] = [];

      // Add from memory cache
      for (const metadata of this.metadata.values()) {
        models.push(metadata);
      }

      // Add from persistent storage
      if (this.config.enablePersistence && this.db) {
        const persistedModels = await this.listPersistedModels();

        // Merge, avoiding duplicates
        const existingIds = new Set(models.map(m => m.id));
        for (const model of persistedModels) {
          if (!existingIds.has(model.id)) {
            models.push(model);
          }
        }
      }

      return { success: true, value: models };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async removeModel(modelId: string): Promise<Result<void, Error>> {
    try {
      // Remove from memory cache
      if (this.memoryCache.has(modelId)) {
        const modelData = this.memoryCache.get(modelId)!;
        this.currentMemorySize -= modelData.byteLength;
        this.memoryCache.delete(modelId);
        this.metadata.delete(modelId);
      }

      // Remove from persistent storage
      if (this.config.enablePersistence && this.db) {
        const transaction = this.db.transaction(['models', 'metadata'], 'readwrite');

        const modelsStore = transaction.objectStore('models');
        const metadataStore = transaction.objectStore('metadata');

        await Promise.all([
          this.promisifyRequest(modelsStore.delete(modelId)),
          this.promisifyRequest(metadataStore.delete(modelId))
        ]);
      }

      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async clear(): Promise<Result<void, Error>> {
    try {
      // Clear memory cache
      this.memoryCache.clear();
      this.metadata.clear();
      this.currentMemorySize = 0;

      // Clear persistent storage
      if (this.config.enablePersistence && this.db) {
        const transaction = this.db.transaction(['models', 'metadata'], 'readwrite');

        const modelsStore = transaction.objectStore('models');
        const metadataStore = transaction.objectStore('metadata');

        await Promise.all([
          this.promisifyRequest(modelsStore.clear()),
          this.promisifyRequest(metadataStore.clear())
        ]);
      }

      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  getCacheStats(): {
    memorySize: number;
    memoryItems: number;
    maxSize: number;
    utilization: number;
  } {
    return {
      memorySize: this.currentMemorySize,
      memoryItems: this.memoryCache.size,
      maxSize: this.config.maxSize,
      utilization: this.currentMemorySize / this.config.maxSize
    };
  }

  // Private helper methods
  private async evictMemoryCache(): Promise<void> {
    if (this.currentMemorySize <= this.config.memoryThreshold) {
      return;
    }

    // Sort by last accessed time (LRU eviction)
    const entries = Array.from(this.metadata.entries()).sort((a, b) => {
      const aTime = a[1].lastAccessed || 0;
      const bTime = b[1].lastAccessed || 0;
      return aTime - bTime;
    });

    // Remove oldest entries until under threshold
    for (const [modelId, metadata] of entries) {
      if (this.currentMemorySize <= this.config.memoryThreshold) {
        break;
      }

      if (this.memoryCache.has(modelId)) {
        const modelData = this.memoryCache.get(modelId)!;
        this.currentMemorySize -= modelData.byteLength;
        this.memoryCache.delete(modelId);
        this.metadata.delete(modelId);
      }
    }
  }

  private async persistModel(model: CachedModel): Promise<void> {
    if (!this.db) return;

    const transaction = this.db.transaction(['models', 'metadata'], 'readwrite');
    const modelsStore = transaction.objectStore('models');
    const metadataStore = transaction.objectStore('metadata');

    await Promise.all([
      this.promisifyRequest(modelsStore.put(model)),
      this.promisifyRequest(metadataStore.put(model.metadata))
    ]);
  }

  private async retrievePersistedModel(modelId: string): Promise<CachedModel | null> {
    if (!this.db) return null;

    const transaction = this.db.transaction(['models'], 'readonly');
    const store = transaction.objectStore('models');
    const result = await this.promisifyRequest(store.get(modelId));

    return result || null;
  }

  private async retrieveMetadata(modelId: string): Promise<ModelMetadata | null> {
    if (!this.db) return null;

    const transaction = this.db.transaction(['metadata'], 'readonly');
    const store = transaction.objectStore('metadata');
    const result = await this.promisifyRequest(store.get(modelId));

    return result || null;
  }

  private async listPersistedModels(): Promise<ModelMetadata[]> {
    if (!this.db) return [];

    const transaction = this.db.transaction(['metadata'], 'readonly');
    const store = transaction.objectStore('metadata');
    const request = store.getAll();

    const results = await this.promisifyRequest(request);
    return results || [];
  }

  private async updateAccessCount(modelId: string): Promise<void> {
    if (!this.db) return;

    const transaction = this.db.transaction(['models', 'metadata'], 'readwrite');
    const modelsStore = transaction.objectStore('models');
    const metadataStore = transaction.objectStore('metadata');

    const model = await this.promisifyRequest(modelsStore.get(modelId));
    if (model) {
      model.accessCount += 1;
      model.metadata.lastAccessed = Date.now();
      model.metadata.accessCount = model.accessCount;

      await Promise.all([
        this.promisifyRequest(modelsStore.put(model)),
        this.promisifyRequest(metadataStore.put(model.metadata))
      ]);
    }
  }

  private async cleanupPersistentCache(): Promise<void> {
    if (!this.db) return;

    const transaction = this.db.transaction(['models'], 'readwrite');
    const store = transaction.objectStore('models');
    const index = store.index('timestamp');

    const oldModels = await this.promisifyRequest(
      index.getAll(IDBKeyRange.upperBound(Date.now() - this.config.maxAge))
    );

    // Remove old models
    for (const model of oldModels) {
      await this.promisifyRequest(store.delete(model.id));
    }
  }

  private promisifyRequest<T>(request: IDBRequest<T>): Promise<T> {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async destroy(): Promise<void> {
    // Clear memory cache
    this.memoryCache.clear();
    this.metadata.clear();
    this.currentMemorySize = 0;

    // Close IndexedDB connection
    if (this.db) {
      this.db.close();
      this.db = null;
    }
  }
}
