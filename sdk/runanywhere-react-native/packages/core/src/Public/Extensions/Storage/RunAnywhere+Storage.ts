/**
 * RunAnywhere+Storage.ts
 *
 * Storage management extension.
 * Delegates to C++ via native module for storage info (C++ handles recursive traversal).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import {
  StorageDeleteRequest,
  StorageDeleteResult as StorageDeleteResultCodec,
  StorageInfoRequest,
  StorageInfoResult as StorageInfoResultCodec,
} from '@runanywhere/proto-ts/storage_types';
import type {
  StorageInfo,
  StorageDeleteResult,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.Storage');

export type {
  StorageDeleteCandidate,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfo,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';

function encode<T>(
  message: T,
  codec: { encode(value: T, writer?: { finish(): Uint8Array }): { finish(): Uint8Array } }
): ArrayBuffer {
  return encodeProtoMessage(message, codec);
}

function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  fallback: T
): T {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? fallback : codec.decode(bytes);
}


/**
 * Get canonical generated storage info from native commons.
 * Internal proto plumbing for [getStorageInfo] — Swift has no public
 * `getStorageInfoProto` counterpart, so this stays module-private.
 */
async function getStorageInfoProto(
  request: StorageInfoRequest = {
    includeDevice: true,
    includeApp: true,
    includeModels: true,
    includeCache: true,
  }
): Promise<StorageInfoResult> {
  if (!isNativeModuleAvailable()) {
    return StorageInfoResultCodec.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageInfoProto(
    encode(request, StorageInfoRequest)
  );
  return decode(
    buffer,
    StorageInfoResultCodec,
    StorageInfoResultCodec.fromPartial({
      success: false,
      errorMessage: 'storageInfoProto returned an empty result',
    })
  );
}

/**
 * Execute or dry-run native storage deletion.
 */
export async function deleteStorage(
  request: StorageDeleteRequest
): Promise<StorageDeleteResult> {
  if (!isNativeModuleAvailable()) {
    return StorageDeleteResultCodec.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.storageDeleteProto(
    encode(request, StorageDeleteRequest)
  );
  return decode(
    buffer,
    StorageDeleteResultCodec,
    StorageDeleteResultCodec.fromPartial({
      success: false,
      errorMessage: 'storageDeleteProto returned an empty result',
    })
  );
}

/**
 * Get generated storage information.
 * Delegates to C++ FileManagerBridge for recursive directory traversal.
 */
export async function getStorageInfo(): Promise<StorageInfo | null> {
  try {
    const result = await getStorageInfoProto();
    return result.success ? result.info ?? null : null;
  } catch (error) {
    logger.warning('Failed to get storage info:', { error });
    return null;
  }
}

/**
 * Clear the SDK's Cache directory. Mirrors Swift `clearCache()` →
 * `CppBridge.FileManager.clearCache()` (cache only — temp files are cleaned
 * by [cleanTempFiles]).
 */
export async function clearCache(): Promise<void> {
  // Clear file caches via native module (C++ handles directory clearing)
  if (isNativeModuleAvailable()) {
    try {
      // Swift parity: RunAnywhere+Storage.swift:309 gates on ensureServicesReady.
      await ensureServicesReady();
      const native = requireNativeModule();
      await native.clearCache();
    } catch (error) {
      logger.warning('Failed to clear native cache:', { error });
    }
  }

  logger.info('Cache cleared');
}

/**
 * Delete one downloaded model end-to-end: unload it if loaded, remove its
 * files through the platform adapter, and clear its registry path so the
 * entry returns to registered-not-downloaded (re-downloadable). Convenience
 * over `deleteStorage` with the canonical flag set — mirrors Swift
 * `RunAnywhere.deleteModel(_:)`.
 */
export async function deleteModel(
  modelId: string
): Promise<StorageDeleteResult> {
  return deleteStorage(
    StorageDeleteRequest.fromPartial({
      modelIds: [modelId],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
    })
  );
}

/**
 * Clear the SDK's Temp directory. Mirrors Swift `cleanTempFiles()` →
 * `CppBridge.FileManager.clearTemp()`.
 */
export async function cleanTempFiles(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  try {
    // Swift parity: RunAnywhere+Storage.swift:321 gates on ensureServicesReady.
    await ensureServicesReady();
    const native = requireNativeModule();
    return await native.cleanTempFiles();
  } catch (error) {
    logger.warning('Failed to clean temp files:', { error });
    return false;
  }
}
