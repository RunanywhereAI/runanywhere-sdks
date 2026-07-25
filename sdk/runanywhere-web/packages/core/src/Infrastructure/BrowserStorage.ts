/**
 * BrowserStorage — Origin Private File System quota helpers.
 *
 * Requests durable storage via `navigator.storage.persist()` so large model
 * downloads are less likely to hit transient eviction quotas. Browsers may
 * still deny persist without a user gesture (common in headless automation).
 *
 * Note: `persist()` does not show a permission dialog — the browser decides
 * silently. For an explicit user prompt, use the File System Access API via
 * `RunAnywhere.storage.chooseLocalStorageDirectory()`.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';

const logger = new SDKLogger('BrowserStorage');

/** Models at/above this size should prefer durable storage or a picked folder. */
export const LARGE_DOWNLOAD_BYTES = 256 * 1024 * 1024;

interface StorageManagerWithPersist {
  persist?: () => Promise<boolean>;
  persisted?: () => Promise<boolean>;
  estimate?: () => Promise<{ usage?: number; quota?: number }>;
}

export interface BrowserStorageEstimate {
  persisted: boolean;
  quotaBytes: number;
  usageBytes: number;
  availableBytes: number;
}

export interface BrowserStorageReadiness extends BrowserStorageEstimate {
  /** When `requiredBytes > 0`, false only if quota is known and too small. */
  sufficient: boolean;
}

/**
 * Read OPFS/origin quota. Returns zeros when `estimate()` is unavailable.
 */
export async function readBrowserStorageEstimate(): Promise<BrowserStorageEstimate> {
  if (typeof navigator === 'undefined') {
    return { persisted: false, quotaBytes: 0, usageBytes: 0, availableBytes: 0 };
  }

  const storage = navigator.storage as StorageManagerWithPersist | undefined;
  let persisted = false;
  if (storage?.persisted) {
    try {
      persisted = await storage.persisted();
    } catch {
      persisted = false;
    }
  }

  if (!storage?.estimate) {
    return { persisted, quotaBytes: 0, usageBytes: 0, availableBytes: 0 };
  }

  try {
    const estimate = await storage.estimate();
    const quotaBytes = Number(estimate.quota ?? 0);
    const usageBytes = Number(estimate.usage ?? 0);
    if (!Number.isFinite(quotaBytes) || quotaBytes <= 0) {
      return { persisted, quotaBytes: 0, usageBytes: 0, availableBytes: 0 };
    }
    const usage = Number.isFinite(usageBytes) ? Math.min(quotaBytes, usageBytes) : 0;
    return {
      persisted,
      quotaBytes,
      usageBytes: usage,
      availableBytes: Math.max(0, quotaBytes - usage),
    };
  } catch {
    return { persisted, quotaBytes: 0, usageBytes: 0, availableBytes: 0 };
  }
}

/**
 * Ask the browser to treat origin storage as persistent (not evicted under
 * pressure). Call this as the first async step of a download button handler so
 * the user gesture is still active. Returns whether persistence was granted.
 */
export async function requestPersistentStorage(): Promise<boolean> {
  if (typeof navigator === 'undefined') return false;

  const storage = navigator.storage as StorageManagerWithPersist | undefined;
  if (!storage?.persist) {
    logger.debug('navigator.storage.persist() not available');
    return false;
  }

  try {
    if (storage.persisted) {
      const already = await storage.persisted();
      if (already) {
        logger.debug('Storage already marked persistent');
        await logStorageEstimate(storage);
        return true;
      }
    }

    const granted = await storage.persist();
    if (granted) {
      logger.info('Persistent browser storage granted');
    } else {
      logger.warning(
        'Persistent browser storage not granted — large OPFS downloads may hit quota. '
          + 'Use Storage → Choose Storage Folder for reliable multi-GB downloads.',
      );
    }

    await logStorageEstimate(storage);
    return granted;
  } catch (err) {
    logger.warning(
      `Failed to request persistent storage: ${err instanceof Error ? err.message : String(err)}`,
    );
    return false;
  }
}

/**
 * Pre-download gate: request durable storage, then read quota. Intended to be
 * awaited immediately after the user clicks Download.
 */
export async function ensureDownloadStorageReady(options: {
  requiredBytes?: number;
} = {}): Promise<BrowserStorageReadiness> {
  await requestPersistentStorage();
  const estimate = await readBrowserStorageEstimate();
  const requiredBytes = Math.max(0, options.requiredBytes ?? 0);
  const sufficient = requiredBytes <= 0
    || estimate.availableBytes <= 0
    || estimate.availableBytes >= requiredBytes;
  return { ...estimate, sufficient };
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
