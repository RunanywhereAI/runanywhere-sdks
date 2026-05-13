/**
 * SecureStorageService.ts
 *
 * Thin adapter over native secure storage. Keychain/Keystore behavior and
 * persistent identity ownership live below the JS layer.
 */

import { requireNativeCoreModule } from '../../native/NativeRunAnywhereCore';
import { SecureStorageError, isItemNotFoundError } from './SecureStorageError';
import { SecureStorageKeys, type SecureStorageKey } from './SecureStorageKeys';
import type { SDKInitParams } from '../Initialization';
import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

function asError(error: unknown): Error | undefined {
  return error instanceof Error ? error : undefined;
}

class SecureStorageServiceImpl {
  async isAvailable(): Promise<boolean> {
    try {
      const native = requireNativeCoreModule();
      return (
        typeof native.secureStorageSet === 'function' &&
        typeof native.secureStorageGet === 'function' &&
        typeof native.secureStorageDelete === 'function' &&
        typeof native.secureStorageExists === 'function'
      );
    } catch {
      return false;
    }
  }

  async store(value: string, key: SecureStorageKey | string): Promise<void> {
    try {
      const didStore = await requireNativeCoreModule().secureStorageSet(key, value);
      if (!didStore) {
        throw new Error(`Native secure storage rejected key: ${key}`);
      }
    } catch (error) {
      throw SecureStorageError.storageError(asError(error));
    }
  }

  async retrieve(key: SecureStorageKey | string): Promise<string | null> {
    try {
      return await requireNativeCoreModule().secureStorageGet(key);
    } catch (error) {
      if (isItemNotFoundError(error)) {
        return null;
      }
      throw SecureStorageError.retrievalError(asError(error));
    }
  }

  async delete(key: SecureStorageKey | string): Promise<void> {
    try {
      await requireNativeCoreModule().secureStorageDelete(key);
    } catch (error) {
      if (!isItemNotFoundError(error)) {
        throw SecureStorageError.deletionError(asError(error));
      }
    }
  }

  async exists(key: SecureStorageKey | string): Promise<boolean> {
    try {
      return await requireNativeCoreModule().secureStorageExists(key);
    } catch {
      return false;
    }
  }

  async storeSDKParams(params: SDKInitParams): Promise<void> {
    const writes: Promise<void>[] = [
      this.store(String(params.environment), SecureStorageKeys.environment),
    ];

    if (params.apiKey) {
      writes.push(this.store(params.apiKey, SecureStorageKeys.apiKey));
    }
    if (params.baseURL) {
      writes.push(this.store(params.baseURL, SecureStorageKeys.baseURL));
    }

    await Promise.all(writes);
  }

  async retrieveSDKParams(): Promise<SDKInitParams | null> {
    const [apiKey, baseURL, environment] = await Promise.all([
      this.retrieve(SecureStorageKeys.apiKey),
      this.retrieve(SecureStorageKeys.baseURL),
      this.retrieve(SecureStorageKeys.environment),
    ]);

    if (!apiKey || !baseURL || !environment) {
      return null;
    }

    return {
      apiKey,
      baseURL,
      environment: Number(environment) as SDKEnvironment,
    };
  }

  async clearSDKParams(): Promise<void> {
    await Promise.all([
      this.delete(SecureStorageKeys.apiKey),
      this.delete(SecureStorageKeys.baseURL),
      this.delete(SecureStorageKeys.environment),
    ]);
  }

  async storeDeviceUUID(uuid: string): Promise<void> {
    await this.store(uuid, SecureStorageKeys.deviceUUID);
  }

  async retrieveDeviceUUID(): Promise<string | null> {
    return this.retrieve(SecureStorageKeys.deviceUUID);
  }

  clearCache(): void {}

  async clearAll(): Promise<void> {
    await Promise.all([
      this.clearSDKParams(),
      this.delete(SecureStorageKeys.deviceUUID),
    ]);
  }
}

export const SecureStorageService = new SecureStorageServiceImpl();
