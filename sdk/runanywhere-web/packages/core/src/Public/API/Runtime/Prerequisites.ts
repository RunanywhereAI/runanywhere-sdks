/**
 * Prerequisite resolution shared by every generation verb: make the SDK's
 * services usable, then make sure the model a request needs is resident,
 * downloading it first when the caller named one that is absent.
 *
 * Internal — the public verbs call these so no application ever has to
 * sequence `download` then `load` by hand.
 */

import { ModelRegistryStatus, type ModelCategory } from '@runanywhere/proto-ts/model_types';
import { SDKException } from '../../../Foundation/SDKException.js';
import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { ModelRegistry } from '../../Extensions/RunAnywhere+ModelRegistry.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import { SDKCore } from '../../SDKCore.js';

const logger = new SDKLogger('Prerequisites');

/** Bring the SDK's background services up before a native call. */
export async function ensureReady(): Promise<void> {
  await SDKCore.ensureServicesReady();
}

function residentModelId(category: ModelCategory): string | null {
  const current = WebModelLifecycle.currentModel({ category, includeModelMetadata: false });
  return current?.found ? current.modelId : null;
}

/**
 * Make `modelId` (or, when unset, whatever is already resident) usable for
 * `category`. Downloads the model when the registry says it is not on disk.
 */
export async function ensureModelForCategory(
  category: ModelCategory,
  modelId?: string,
): Promise<string> {
  const resident = residentModelId(category);
  if (!modelId) {
    if (resident) return resident;
    throw SDKException.notInitialized(
      `No model is loaded for this capability. Pass options.model or call RunAnywhere.models.load(id) first.`,
    );
  }
  if (resident === modelId) return modelId;

  const model = ModelRegistry.getModel(modelId);
  if (!model) {
    throw SDKException.invalidConfiguration(
      `Model '${modelId}' is not in the catalog. Register it with RunAnywhere.models.register(...) first.`,
    );
  }
  const isDownloaded = model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED
    || model.registryStatus === ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED;
  if (!isDownloaded || !model.localPath) {
    logger.info(`Downloading '${modelId}' before use`);
    await SDKCore.downloadModel({ modelId });
  }
  const result = await SDKCore.loadModel({
    modelId,
    category: model.category || category,
    framework: model.framework,
    forceReload: false,
    validateAvailability: true,
    backendPreferences: [],
  });
  if (!result || result.error) {
    throw result?.error
      ? new SDKException(result.error)
      : SDKException.fromCode(-1, `Loading '${modelId}' failed.`, 'models.load');
  }
  return modelId;
}

/** Make sure a model of `category` is resident, without naming which one. */
export async function ensureAnyModelForCategory(category: ModelCategory): Promise<string> {
  return ensureModelForCategory(category);
}
