/**
 * RunAnywhere+ModelManagement.ts
 *
 * Model management namespace — mirrors Swift's `RunAnywhere+ModelManagement.swift`.
 * Provides `RunAnywhere.modelManagement.*` capability surface.
 */

import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
export type { ModelInfo };

import { ModelManager, ModelStatus } from '../../Infrastructure/ModelManager';
import type { ManagedModel } from '../../Infrastructure/ModelManager';

export const ModelManagement = {
  list(): ManagedModel[] {
    return ModelManager.getModels();
  },

  isLoaded(modelId: string): boolean {
    const found = ModelManager.getModels().find((m) => m.id === modelId);
    return found?.status === ModelStatus.Loaded;
  },

  async download(modelId: string): Promise<void> {
    return ModelManager.downloadModel(modelId);
  },

  async load(modelId: string): Promise<boolean> {
    return ModelManager.loadModel(modelId);
  },

  async unloadAll(): Promise<void> {
    return ModelManager.unloadAll();
  },

  async delete(modelId: string): Promise<void> {
    return ModelManager.deleteModel(modelId);
  },
};
