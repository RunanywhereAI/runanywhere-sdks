/**
 * RunAnywhere+Storage.ts
 *
 * Storage namespace matching the Swift public shape while keeping Web's
 * browser-native storage affordances behind this capability.
 */

import type {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import { SDKException } from '../../Foundation/SDKException';
import { StorageAdapter } from '../../Adapters/StorageAdapter';

function requireNativeStorage(operation: string): StorageAdapter {
  const adapter = StorageAdapter.tryDefault();
  if (!adapter || !adapter.supportsProtoStorage()) {
    throw SDKException.backendNotAvailable(
      operation,
      'No Web WASM storage analyzer handle is registered.',
    );
  }
  return adapter;
}

export interface BrowserStorageControls {
  readonly isLocalStorageSupported: boolean;
  readonly isLocalStorageReady: boolean;
  readonly hasLocalStorageHandle: boolean;
  readonly localStorageDirectoryName: string | null;
  readonly storageBackend: 'fsAccess' | 'opfs' | 'memory';
  chooseLocalStorageDirectory(): Promise<boolean>;
  restoreLocalStorage(): Promise<boolean>;
  requestLocalStorageAccess(): Promise<boolean>;
}

export function createStorageNamespace(browser: BrowserStorageControls) {
  return {
    get isLocalStorageSupported(): boolean {
      return browser.isLocalStorageSupported;
    },

    get isLocalStorageReady(): boolean {
      return browser.isLocalStorageReady;
    },

    get hasLocalStorageHandle(): boolean {
      return browser.hasLocalStorageHandle;
    },

    get localStorageDirectoryName(): string | null {
      return browser.localStorageDirectoryName;
    },

    get backend(): 'fsAccess' | 'opfs' | 'memory' {
      return browser.storageBackend;
    },

    chooseLocalStorageDirectory(): Promise<boolean> {
      return browser.chooseLocalStorageDirectory();
    },

    restoreLocalStorage(): Promise<boolean> {
      return browser.restoreLocalStorage();
    },

    requestLocalStorageAccess(): Promise<boolean> {
      return browser.requestLocalStorageAccess();
    },

    supportsNativeAnalyzer(): boolean {
      return StorageAdapter.tryDefault()?.supportsProtoStorage() ?? false;
    },

    info(request: StorageInfoRequest): StorageInfoResult {
      const result = requireNativeStorage('storage.info').info(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.info', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    availability(request: StorageAvailabilityRequest): StorageAvailabilityResult {
      const result = requireNativeStorage('storage.availability').availability(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.availability', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    deletePlan(request: StorageDeletePlanRequest): StorageDeletePlan {
      const result = requireNativeStorage('storage.deletePlan').deletePlan(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.deletePlan', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    delete(request: StorageDeleteRequest): StorageDeleteResult {
      const result = requireNativeStorage('storage.delete').delete(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.delete', 'Native storage analyzer returned no result.');
      }
      return result;
    },
  };
}

export type StorageNamespace = ReturnType<typeof createStorageNamespace>;
