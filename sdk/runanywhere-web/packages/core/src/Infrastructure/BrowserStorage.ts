/**
 * BrowserStorage — Origin Private File System quota helpers.
 *
 * Requests durable storage via `navigator.storage.persist()` so large model
 * downloads are less likely to hit transient eviction quotas. Browsers may
 * still deny persist without a user gesture (common in headless automation).
 */

import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('BrowserStorage');

interface StorageManagerWithPersist {
  persist?: () => Promise<boolean>;
  persisted?: () => Promise<boolean>;
  estimate?: () => Promise<{ usage?: number; quota?: number }>;
}

/**
 * Ask the browser to treat origin storage as persistent (not evicted under
 * pressure). No-op when the Storage API is unavailable. Failures are logged
 * and never thrown — init must not fail because persist was denied.
 */
export async function requestPersistentStorage(): Promise<void> {
  if (typeof navigator === 'undefined') return;

  const storage = navigator.storage as StorageManagerWithPersist | undefined;
  if (!storage?.persist) {
    logger.debug('navigator.storage.persist() not available');
    return;
  }

  try {
    if (storage.persisted) {
      const already = await storage.persisted();
      if (already) {
        logger.debug('Storage already marked persistent');
        await logStorageEstimate(storage);
        return;
      }
    }

    const granted = await storage.persist();
    if (granted) {
      logger.info('Persistent browser storage granted');
    } else {
      logger.warning(
        'Persistent browser storage not granted — large OPFS downloads may hit quota in headless or low-disk sessions',
      );
    }

    await logStorageEstimate(storage);
  } catch (err) {
    logger.warning(
      `Failed to request persistent storage: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

async function logStorageEstimate(storage: StorageManagerWithPersist): Promise<void> {
  if (!storage.estimate) return;
  try {
    const { usage, quota } = await storage.estimate();
    if (usage != null && quota != null) {
      logger.debug(`Storage estimate: ${usage} / ${quota} bytes`);
    }
  } catch {
    // estimate() is best-effort diagnostics only
  }
}
