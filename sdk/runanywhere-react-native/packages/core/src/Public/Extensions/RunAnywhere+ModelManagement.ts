/**
 * RunAnywhere+ModelManagement.ts
 *
 * Model lifecycle helpers. Mirrors Swift `RunAnywhere+ModelManagement.swift`.
 *
 * RN delegates loading to per-modality bridges (see `RunAnywhere+TextGeneration`,
 * `+STT`, `+TTS`, `+VAD`, `+VLM`, `+Diffusion`). This file is a forwarder
 * facade that exposes a single `loadModel(_)` entrypoint with category
 * routing, plus path resolution helpers, so consumers can load any model
 * without having to know which sub-API to call.
 */

import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import { ModelCategory } from '../../types';
import type { ModelInfo } from '../../types';
import { loadModel as loadLLMModel } from './RunAnywhere+TextGeneration';
import { loadSTTModel } from './RunAnywhere+STT';
import { loadTTSModel } from './RunAnywhere+TTS';
import { loadVADModel } from './RunAnywhere+VAD';
import { loadVLMModelById } from './RunAnywhere+VisionLanguage';
import { loadDiffusionModel } from './RunAnywhere+Diffusion';
import { getModelPath } from './RunAnywhere+Models';

const logger = new SDKLogger('RunAnywhere.ModelManagement');

/**
 * Load a model by ID, automatically routing to the correct backend based
 * on its registered category. Mirrors Swift `loadModel(_:)`.
 *
 * Throws `SDKException.modelNotFound` if the model isn't in the registry.
 */
export async function loadModelByCategory(modelId: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.notInitialized('SDK');
  }
  const allModels = await ModelRegistry.getAvailableModels();
  const model = allModels.find((m) => m.id === modelId);
  if (!model) {
    throw SDKException.modelNotFound(modelId);
  }

  logger.info(`Routing loadModel for category=${model.category} model=${modelId}`);

  switch (model.category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      await loadLLMModel(modelId);
      return;
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      await loadSTTModel(modelId);
      return;
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      await loadTTSModel(modelId);
      return;
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION: {
      const vadPath = await getModelPath(modelId);
      if (!vadPath) throw SDKException.modelNotFound(modelId);
      await loadVADModel(vadPath);
      return;
    }
    case ModelCategory.MODEL_CATEGORY_VISION:
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      await loadVLMModelById(modelId);
      return;
    case ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION: {
      const localPath = await getModelPath(modelId);
      if (!localPath) {
        throw SDKException.modelNotFound(modelId);
      }
      await loadDiffusionModel(localPath, modelId, model.name);
      return;
    }
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      throw SDKException.notImplemented(
        `Embedding model loading not implemented for ${modelId}`
      );
    default:
      throw SDKException.notImplemented(
        `Model category ${model.category} not supported for ${modelId}`
      );
  }
}

/**
 * Resolve the on-disk model file path for an arbitrary model. Mirrors
 * Swift `resolveModelFilePath(for:)` — but on RN this is a thin wrapper
 * over the native bridge which handles framework-specific resolution.
 */
export async function resolveModelFilePath(
  modelId: string
): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = requireNativeModule();
  try {
    return await native.getModelPath(modelId);
  } catch (err) {
    logger.warning(
      `resolveModelFilePath failed: ${err instanceof Error ? err.message : String(err)}`
    );
    return null;
  }
}

/**
 * Verify that a model is downloaded and present on disk before loading.
 * Throws if not.
 */
export async function ensureModelDownloaded(modelId: string): Promise<ModelInfo> {
  const allModels = await ModelRegistry.getAvailableModels();
  const model = allModels.find((m) => m.id === modelId);
  if (!model) throw SDKException.modelNotFound(modelId);
  if (!model.isDownloaded) {
    throw SDKException.of(
      // ERROR_CODE_MODEL_NOT_LOADED
      116 as never,
      `Model '${modelId}' is not downloaded`
    );
  }
  return model;
}
