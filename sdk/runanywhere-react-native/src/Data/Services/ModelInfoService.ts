/**
 * ModelInfoService.ts
 *
 * Service layer for model information management
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Services/ModelInfoService.swift
 */

import type { ModelInfo } from '../../Core/Models/Model/ModelInfo';
import type { ModelInfoRepository } from '../../Data/Repositories/ModelInfoRepository';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { LLMFramework } from '../../Core/Models/Framework/LLMFramework';
import { ModelCategory } from '../../Core/Models/Model/ModelCategory';

/**
 * Service for managing model information
 */
export class ModelInfoService {
  private logger: SDKLogger;
  private modelInfoRepository: ModelInfoRepository;
  private syncCoordinator: any | null;

  /**
   * Public access to the repository
   */
  public get repository(): ModelInfoRepository {
    return this.modelInfoRepository;
  }

  constructor(
    modelInfoRepository: ModelInfoRepository,
    syncCoordinator?: any | null
  ) {
    this.logger = new SDKLogger('ModelInfoService');
    this.modelInfoRepository = modelInfoRepository;
    this.syncCoordinator = syncCoordinator ?? null;
  }

  /**
   * Save model metadata
   */
  public async saveModel(model: ModelInfo): Promise<void> {
    await this.modelInfoRepository.save(model);
    this.logger.info(`Model metadata saved: ${model.id}`);
  }

  /**
   * Get model metadata by ID
   */
  public async getModel(modelId: string): Promise<ModelInfo | null> {
    return await this.modelInfoRepository.fetch(modelId);
  }

  /**
   * Load all stored models
   */
  public async loadStoredModels(): Promise<ModelInfo[]> {
    return await this.modelInfoRepository.fetchAll();
  }

  /**
   * Load models for specific frameworks
   */
  public async loadModels(frameworks: LLMFramework[]): Promise<ModelInfo[]> {
    const models: ModelInfo[] = [];
    for (const framework of frameworks) {
      const frameworkModels = await this.modelInfoRepository.fetchByFramework(
        framework
      );
      models.push(...frameworkModels);
    }
    // Remove duplicates based on model ID
    const uniqueModels = Array.from(
      new Map(models.map((m) => [m.id, m])).values()
    );
    return uniqueModels;
  }

  /**
   * Update model last used date
   */
  public async updateLastUsed(modelId: string): Promise<void> {
    await this.modelInfoRepository.updateLastUsed(modelId);
    this.logger.debug(`Updated last used date for model: ${modelId}`);
  }

  /**
   * Remove model metadata
   */
  public async removeModel(modelId: string): Promise<void> {
    await this.modelInfoRepository.delete(modelId);
    this.logger.info(`Removed model metadata: ${modelId}`);
  }

  /**
   * Get downloaded models
   */
  public async getDownloadedModels(): Promise<ModelInfo[]> {
    return await this.modelInfoRepository.fetchDownloaded();
  }

  /**
   * Update download status
   */
  public async updateDownloadStatus(
    modelId: string,
    isDownloaded: boolean,
    localPath?: string | null
  ): Promise<void> {
    await this.modelInfoRepository.updateDownloadStatus(modelId, localPath);
    this.logger.info(
      `Updated download status for model ${modelId}: ${isDownloaded}`
    );
  }

  /**
   * Get models by framework
   */
  public async getModels(framework: LLMFramework): Promise<ModelInfo[]> {
    return await this.modelInfoRepository.fetchByFramework(framework);
  }

  /**
   * Get models by category
   */
  public async getModelsByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return await this.modelInfoRepository.fetchByCategory(category);
  }

  /**
   * Force sync model information
   */
  public async syncModelInfo(): Promise<void> {
    if (this.syncCoordinator) {
      await this.syncCoordinator.sync(this.modelInfoRepository);
      this.logger.info('Model info sync completed');
    } else {
      this.logger.debug('Sync not available for model info');
    }
  }

  /**
   * Clear all model metadata
   */
  public async clearAllModels(): Promise<void> {
    const models = await this.modelInfoRepository.fetchAll();
    for (const model of models) {
      await this.modelInfoRepository.delete(model.id);
    }
    this.logger.info('Cleared all model metadata');
  }
}

