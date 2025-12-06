/**
 * AsyncStorageAdapter.example.ts
 *
 * Example adapter for using @react-native-async-storage/async-storage with AnalyticsQueueManager
 *
 * Installation:
 * npm install @react-native-async-storage/async-storage
 * or
 * yarn add @react-native-async-storage/async-storage
 *
 * Usage:
 * import AsyncStorage from '@react-native-async-storage/async-storage';
 * import { AnalyticsQueueManager } from '@runanywhere/react-native';
 * import { AsyncStorageAdapter } from './AsyncStorageAdapter.example';
 *
 * const storage = new AsyncStorageAdapter(AsyncStorage);
 * const queueManager = AnalyticsQueueManager.shared;
 * queueManager.setStorage(storage);
 */

/**
 * Storage interface required by AnalyticsQueueManager
 */
interface Storage {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
}

/**
 * Adapter for @react-native-async-storage/async-storage
 */
export class AsyncStorageAdapter implements Storage {
  constructor(private asyncStorage: any) {}

  async getItem(key: string): Promise<string | null> {
    return await this.asyncStorage.getItem(key);
  }

  async setItem(key: string, value: string): Promise<void> {
    await this.asyncStorage.setItem(key, value);
  }

  async removeItem(key: string): Promise<void> {
    await this.asyncStorage.removeItem(key);
  }
}

/**
 * Example usage with AnalyticsQueueManager
 */
export function setupAnalyticsWithAsyncStorage() {
  // This function would be called in your app initialization

  /*
  import AsyncStorage from '@react-native-async-storage/async-storage';
  import { AnalyticsQueueManager } from '@runanywhere/react-native';
  import { AsyncStorageAdapter } from './AsyncStorageAdapter.example';

  const storage = new AsyncStorageAdapter(AsyncStorage);
  const queueManager = AnalyticsQueueManager.shared;
  queueManager.setStorage(storage);
  */
}

/**
 * Example: Custom storage adapter for different platforms
 */
export class CustomStorageAdapter implements Storage {
  private cache = new Map<string, string>();

  constructor(
    private localStorage?: any,
    private useCache: boolean = true
  ) {}

  async getItem(key: string): Promise<string | null> {
    // Try cache first if enabled
    if (this.useCache && this.cache.has(key)) {
      return this.cache.get(key) || null;
    }

    // Fall back to localStorage
    if (this.localStorage) {
      try {
        const value = await this.localStorage.getItem(key);
        if (this.useCache && value) {
          this.cache.set(key, value);
        }
        return value;
      } catch (error) {
        console.warn('Storage getItem failed:', error);
        return null;
      }
    }

    return null;
  }

  async setItem(key: string, value: string): Promise<void> {
    // Update cache if enabled
    if (this.useCache) {
      this.cache.set(key, value);
    }

    // Persist to localStorage
    if (this.localStorage) {
      try {
        await this.localStorage.setItem(key, value);
      } catch (error) {
        console.warn('Storage setItem failed:', error);
      }
    }
  }

  async removeItem(key: string): Promise<void> {
    // Remove from cache
    if (this.useCache) {
      this.cache.delete(key);
    }

    // Remove from localStorage
    if (this.localStorage) {
      try {
        await this.localStorage.removeItem(key);
      } catch (error) {
        console.warn('Storage removeItem failed:', error);
      }
    }
  }

  // Additional utility methods
  clearCache(): void {
    this.cache.clear();
  }

  getCacheSize(): number {
    return this.cache.size;
  }
}

/**
 * Platform detection and storage setup
 */
export function getPlatformStorage(): Storage {
  // React Native
  if (typeof navigator !== 'undefined' && navigator.product === 'ReactNative') {
    try {
      // Try to import AsyncStorage
      const AsyncStorage = require('@react-native-async-storage/async-storage').default;
      return new AsyncStorageAdapter(AsyncStorage);
    } catch (error) {
      console.warn('AsyncStorage not available, using in-memory storage');
      return new CustomStorageAdapter(undefined, true);
    }
  }

  // Web/Browser
  if (typeof window !== 'undefined' && window.localStorage) {
    return new CustomStorageAdapter({
      getItem: (key: string) => Promise.resolve(window.localStorage.getItem(key)),
      setItem: (key: string, value: string) => {
        window.localStorage.setItem(key, value);
        return Promise.resolve();
      },
      removeItem: (key: string) => {
        window.localStorage.removeItem(key);
        return Promise.resolve();
      },
    });
  }

  // Fallback: In-memory only
  return new CustomStorageAdapter(undefined, true);
}

/**
 * Example: Initialize analytics with automatic platform detection
 */
export function initializeAnalytics(telemetryRepository: any) {
  /*
  import { AnalyticsQueueManager } from '@runanywhere/react-native';
  import { getPlatformStorage } from './AsyncStorageAdapter.example';

  const storage = getPlatformStorage();
  const queueManager = AnalyticsQueueManager.shared;
  queueManager.initialize(telemetryRepository, storage);
  */
}
