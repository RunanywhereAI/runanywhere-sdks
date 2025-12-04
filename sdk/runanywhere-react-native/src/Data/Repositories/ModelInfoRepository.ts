/**
 * ModelInfoRepository.ts
 *
 * Repository protocol for model information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Repositories/ModelInfoRepositoryImpl.swift
 */

import type { ModelInfo } from '../../Core/Models/Model/ModelInfo';
import { LLMFramework } from '../../Core/Models/Framework/LLMFramework';
import { ModelCategory } from '../../Core/Models/Model/ModelCategory';

/**
 * Repository protocol for model information
 */
export interface ModelInfoRepository {
  /**
   * Save model
   */
  save(model: ModelInfo): Promise<void>;

  /**
   * Fetch model by ID
   */
  fetch(id: string): Promise<ModelInfo | null>;

  /**
   * Fetch all models
   */
  fetchAll(): Promise<ModelInfo[]>;

  /**
   * Delete model
   */
  delete(id: string): Promise<void>;

  /**
   * Fetch models by framework
   */
  fetchByFramework(framework: LLMFramework): Promise<ModelInfo[]>;

  /**
   * Fetch models by category
   */
  fetchByCategory(category: ModelCategory): Promise<ModelInfo[]>;

  /**
   * Fetch downloaded models
   */
  fetchDownloaded(): Promise<ModelInfo[]>;

  /**
   * Update download status
   */
  updateDownloadStatus(
    modelId: string,
    localPath?: string | null
  ): Promise<void>;

  /**
   * Update last used date
   */
  updateLastUsed(modelId: string): Promise<void>;
}

/**
 * Simple in-memory implementation
 */
export class ModelInfoRepositoryImpl implements ModelInfoRepository {
  private models: Map<string, ModelInfo> = new Map();

  public async save(model: ModelInfo): Promise<void> {
    this.models.set(model.id, model);
  }

  public async fetch(id: string): Promise<ModelInfo | null> {
    return this.models.get(id) ?? null;
  }

  public async fetchAll(): Promise<ModelInfo[]> {
    return Array.from(this.models.values());
  }

  public async delete(id: string): Promise<void> {
    this.models.delete(id);
  }

  public async fetchByFramework(framework: LLMFramework): Promise<ModelInfo[]> {
    return Array.from(this.models.values()).filter((model) =>
      model.compatibleFrameworks.includes(framework)
    );
  }

  public async fetchByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return Array.from(this.models.values()).filter(
      (model) => model.category === category
    );
  }

  public async fetchDownloaded(): Promise<ModelInfo[]> {
    return Array.from(this.models.values()).filter((model) => model.isAvailable);
  }

  public async updateDownloadStatus(
    modelId: string,
    localPath?: string | null
  ): Promise<void> {
    const model = this.models.get(modelId);
    if (model) {
      const updated = {
        ...model,
        localPath: localPath ?? model.localPath,
      };
      this.models.set(modelId, updated);
    }
  }

  public async updateLastUsed(modelId: string): Promise<void> {
    const model = this.models.get(modelId);
    if (model) {
      const updated = {
        ...model,
        lastUsed: new Date(),
        usageCount: (model.usageCount ?? 0) + 1,
      };
      this.models.set(modelId, updated);
    }
  }
}
