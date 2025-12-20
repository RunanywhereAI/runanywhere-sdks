/**
 * SyncCoordinator.ts
 *
 * Centralized sync coordination for all repositories
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Sync/SyncCoordinator.swift
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

/**
 * Syncable item with required id field
 */
export interface SyncableItem {
  id: string;
  [key: string]: unknown;
}

/**
 * Remote data source interface for sync operations
 */
export interface RemoteDataSource {
  syncBatch(items: SyncableItem[]): Promise<string[]>;
}

/**
 * Repository interface for sync
 */
export interface Repository {
  fetchPendingSync(): Promise<SyncableItem[]>;
  markSynced(ids: string[]): Promise<void>;
  remoteDataSource?: RemoteDataSource;
}

/**
 * Centralized coordinator for syncing data between local storage and remote API
 */
export class SyncCoordinator {
  private logger: SDKLogger;
  private readonly batchSize: number = 100;
  private readonly maxRetries: number = 3;
  private activeSyncs: Set<string> = new Set();
  private syncTimer: NodeJS.Timeout | null = null;

  constructor(enableAutoSync: boolean = false) {
    this.logger = new SDKLogger('SyncCoordinator');
    if (enableAutoSync) {
      this.startAutoSync();
    }
  }

  /**
   * Sync any repository
   */
  public async sync(repository: Repository): Promise<void> {
    const typeName = 'Repository'; // Would get from repository type

    if (this.activeSyncs.has(typeName)) {
      this.logger.debug(`Sync already in progress for ${typeName}`);
      return;
    }

    // Check if remote data source is available
    if (!repository.remoteDataSource) {
      this.logger.debug(`No remote data source available for ${typeName}`);
      return;
    }

    this.activeSyncs.add(typeName);
    try {
      // Fetch pending items from repository
      const pending = await repository.fetchPendingSync();
      if (pending.length === 0) {
        this.logger.debug(`No pending items to sync for ${typeName}`);
        return;
      }

      this.logger.info(`Syncing ${pending.length} ${typeName} items`);

      let successCount = 0;
      const failedIds: string[] = [];

      // Process in batches
      const batches = this.chunkArray(pending, this.batchSize);
      for (const batch of batches) {
        try {
          // Use the remote data source to sync
          const syncedIds = await repository.remoteDataSource.syncBatch(batch);

          // Mark successfully synced items
          if (syncedIds.length > 0) {
            await repository.markSynced(syncedIds);
            successCount += syncedIds.length;
          }

          // Track any that didn't sync
          const batchIds = new Set(batch.map((item) => item.id));
          const syncedSet = new Set(syncedIds);
          const failedInBatch = Array.from(batchIds).filter(
            (id) => !syncedSet.has(id)
          );
          failedIds.push(...failedInBatch);
        } catch (error) {
          this.logger.error(`Failed to sync batch: ${error}`);
          failedIds.push(...batch.map((item) => item.id));
        }
      }

      if (successCount > 0) {
        this.logger.info(
          `Successfully synced ${successCount} ${typeName} items`
        );
      }

      if (failedIds.length > 0) {
        this.logger.warning(
          `Failed to sync ${failedIds.length} ${typeName} items`
        );
      }
    } finally {
      this.activeSyncs.delete(typeName);
    }
  }

  /**
   * Start auto sync
   */
  private startAutoSync(): void {
    this.syncTimer = setInterval(
      () => {
        this.logger.debug('Auto-sync timer triggered');
        // Auto-sync would be triggered by services
      },
      5 * 60 * 1000
    ); // 5 minutes
  }

  /**
   * Stop auto sync
   */
  public stopAutoSync(): void {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }

  /**
   * Chunk array into batches
   */
  private chunkArray<T>(array: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < array.length; i += size) {
      chunks.push(array.slice(i, i + size));
    }
    return chunks;
  }
}
