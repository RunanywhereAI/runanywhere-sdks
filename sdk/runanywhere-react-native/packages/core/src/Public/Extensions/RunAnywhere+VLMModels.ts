/**
 * RunAnywhere+VLMModels.ts
 *
 * VLM model loading helpers. Mirrors Swift `RunAnywhere+VLMModels.swift`.
 *
 * Provides convenience overloads for loading a VLM model from a
 * `ModelInfo` object (vs the lower-level `loadVLMModelById(string)`).
 * File resolution is handled by commons lifecycle resolved artifacts.
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
import {
  loadVLMModelById,
  isVLMModelLoaded,
  unloadVLMModel,
} from './RunAnywhere+VisionLanguage';

const logger = new SDKLogger('VLM.Models');

/** Load a VLM model from a `ModelInfo`. Mirrors Swift `loadVLMModel(_:)`. */
export async function loadVLMModel(model: ModelInfo): Promise<void> {
  if (
    model.category !== ModelCategory.MODEL_CATEGORY_VISION &&
    model.category !== ModelCategory.MODEL_CATEGORY_MULTIMODAL
  ) {
    throw SDKException.invalidInput(
      `Model ${model.id} is not a VLM (category=${model.category})`
    );
  }
  logger.info(`Loading VLM model by ID: ${model.id}`);
  const loaded = await loadVLMModelById(model.id);
  if (!loaded) {
    throw SDKException.modelLoadFailed(model.id);
  }
  logger.info(`VLM model loaded successfully: ${model.id}`);
}

export { loadVLMModelById, isVLMModelLoaded, unloadVLMModel };
