import { ModelCategory } from '../types/enums';
import type { MetadataMap } from './OPFSStorage';

/**
 * Tracks mutable model runtime state that is not part of the static catalog.
 */
export class ModelStateStore {
  private readonly loadedByCategory = new Map<ModelCategory, string>();
  private metadata: MetadataMap = {};

  getMetadata(): MetadataMap {
    return this.metadata;
  }

  setMetadata(metadata: MetadataMap): void {
    this.metadata = metadata;
  }

  getLoadedModelId(category: ModelCategory): string | null {
    return this.loadedByCategory.get(category) ?? null;
  }

  getLoadedEntries(): Array<[ModelCategory, string]> {
    return [...this.loadedByCategory.entries()];
  }

  areAllLoaded(categories: ModelCategory[]): boolean {
    return categories.every((category) => this.loadedByCategory.has(category));
  }

  markLoaded(category: ModelCategory, modelId: string): void {
    this.loadedByCategory.set(category, modelId);
  }

  clearLoaded(category: ModelCategory): void {
    this.loadedByCategory.delete(category);
  }

  clearAllLoaded(): void {
    this.loadedByCategory.clear();
  }

  removeLoadedModel(modelId: string): void {
    for (const [category, loadedId] of this.loadedByCategory) {
      if (loadedId === modelId) {
        this.loadedByCategory.delete(category);
        return;
      }
    }
  }

  getModelLastUsedAt(modelId: string): number {
    return this.metadata[modelId]?.lastUsedAt ?? 0;
  }

  touchLastUsed(modelId: string, sizeBytes: number): void {
    this.metadata[modelId] = { lastUsedAt: Date.now(), sizeBytes };
  }

  removeMetadata(modelId: string): void {
    delete this.metadata[modelId];
  }

  reset(): void {
    this.metadata = {};
    this.loadedByCategory.clear();
  }
}
