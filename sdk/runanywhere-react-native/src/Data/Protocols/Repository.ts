/**
 * Repository.ts
 *
 * Base repository protocol for data persistence
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Protocols/Repository.swift
 */

import type { RepositoryEntity } from './RepositoryEntity';
import type { RemoteDataSource } from './DataSource';

/**
 * Base repository protocol for data persistence
 * Minimal interface - sync handled by SyncCoordinator
 */
export interface Repository<Entity> {
  // MARK: - Core CRUD Operations

  /**
   * Save an entity
   */
  save(entity: Entity): Promise<void>;

  /**
   * Fetch entity by ID
   */
  fetch(id: string): Promise<Entity | null>;

  /**
   * Fetch all entities
   */
  fetchAll(): Promise<Entity[]>;

  /**
   * Delete entity by ID
   */
  delete(id: string): Promise<void>;

  // MARK: - Sync Support

  /**
   * Get the remote data source for syncing
   */
  readonly remoteDataSource?: RemoteDataSource<Entity>;
}

/**
 * Extended repository protocol for entities that implement RepositoryEntity
 * Provides sync support methods
 */
export interface SyncableRepository<Entity extends RepositoryEntity>
  extends Repository<Entity> {
  /**
   * Fetch entities pending sync
   */
  fetchPendingSync(): Promise<Entity[]>;

  /**
   * Mark entities as synced
   */
  markSynced(ids: string[]): Promise<void>;
}

/**
 * Helper functions for repositories with RepositoryEntity entities
 * Provides minimal sync support - actual sync logic in SyncCoordinator
 */
export const RepositoryHelpers = {
  /**
   * Fetch entities pending sync
   * Filters all entities to find those with syncPending = true
   */
  async fetchPendingSync<Entity extends RepositoryEntity>(
    repository: Repository<Entity>
  ): Promise<Entity[]> {
    const all = await repository.fetchAll();
    return all.filter((entity) => entity.syncPending);
  },

  /**
   * Mark entities as synced
   * Updates each entity to clear syncPending flag
   */
  async markSynced<Entity extends RepositoryEntity>(
    repository: Repository<Entity>,
    ids: string[]
  ): Promise<void> {
    for (const id of ids) {
      const entity = await repository.fetch(id);
      if (entity) {
        const updated = {
          ...entity,
          syncPending: false,
        };
        await repository.save(updated);
      }
    }
  },
};
