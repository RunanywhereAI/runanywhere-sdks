/**
 * RunAnywhere+VLMModels.ts
 *
 * VLM model catalog namespace — mirrors Swift's `RunAnywhere+VLMModels.swift`.
 * Provides `RunAnywhere.vlmModels.*` surface for listing and managing VLM models.
 */

import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
export type { ModelInfo };

import { ModelManager, ModelStatus } from '../../Infrastructure/ModelManager';
import { ModelCategory } from '../../types/enums';

export const VLMModels = {
  list(): ModelInfo[] {
    return ModelManager.getModels()
      .filter((m) => m.modality === ModelCategory.Vision || m.modality === ModelCategory.Multimodal)
      .map((m) => ({ id: m.id, name: m.name }) as unknown as ModelInfo);
  },

  isLoaded(modelId: string): boolean {
    const models = ModelManager.getModels();
    const found = models.find((m) => m.id === modelId);
    return found?.status === ModelStatus.Loaded;
  },
};
