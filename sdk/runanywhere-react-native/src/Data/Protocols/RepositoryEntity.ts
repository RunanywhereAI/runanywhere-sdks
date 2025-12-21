/**
 * Consolidated protocol for entities that can be stored in repositories and synced
 * Combines previous Syncable and RepositoryEntity protocols to eliminate duplication
 */
export interface RepositoryEntity {
  /** Unique identifier */
  id: string;

  /** When created */
  createdAt: Date;

  /** When last updated */
  updatedAt: Date;

  /** Needs sync to network */
  syncPending: boolean;
}

/**
 * Helper functions for RepositoryEntity sync behavior
 */
export const RepositoryEntityHelpers = {
  /**
   * Mark entity as updated (sets updatedAt and syncPending)
   */
  markUpdated<T extends RepositoryEntity>(entity: T): T {
    return {
      ...entity,
      updatedAt: new Date(),
      syncPending: true,
    };
  },

  /**
   * Mark entity as synced (clears syncPending)
   */
  markSynced<T extends RepositoryEntity>(entity: T): T {
    return {
      ...entity,
      syncPending: false,
    };
  },
};
