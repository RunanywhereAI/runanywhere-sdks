/**
 * RunAnywhere+VLMModels.ts
 *
 * VLM model loading helpers. Mirrors Swift `RunAnywhere+VLMModels.swift`.
 *
 * Provides convenience overloads for loading a VLM model from a
 * `ModelInfo` object (vs the lower-level `loadVLMModelById(string)`).
 * File resolution (main model + mmproj) is handled in C++ commons.
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import type { ModelInfo } from '../../types';
import { ModelCategory } from '../../types';
import {
  loadVLMModelById,
  isVLMModelLoaded,
  unloadVLMModel,
} from './RunAnywhere+VisionLanguage';

const logger = new SDKLogger('VLM.Models');

/** Load a VLM model from a `ModelInfo`. Mirrors Swift `loadVLMModel(_:)`. */
export async function loadVLMModel(model: ModelInfo): Promise<void> {
  if (
    model.category !== ModelCategory.Vision &&
    model.category !== ModelCategory.Multimodal
  ) {
    throw SDKException.invalidInput(
      `Model ${model.id} is not a VLM (category=${model.category})`
    );
  }
  logger.info(`Loading VLM model by ID: ${model.id}`);
  await loadVLMModelById(model.id);
  logger.info(`VLM model loaded successfully: ${model.id}`);
}

export { loadVLMModelById, isVLMModelLoaded, unloadVLMModel };
