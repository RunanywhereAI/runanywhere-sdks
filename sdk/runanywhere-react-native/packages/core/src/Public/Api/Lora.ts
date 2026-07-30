/**
 * `RunAnywhere.lora` — adapters mixed into the loaded language model.
 */

import {
  LoRAAdapterConfig,
  LoRAApplyRequest,
  LoRARemoveRequest,
} from '@runanywhere/proto-ts/lora_options';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { lora as loraCapability } from '../Extensions/LLM/RunAnywhere+LoRA';
import { toLoraState } from './Results';
import type { LoraState } from './Types';

/**
 * Resolve a registered adapter id to the on-disk path commons needs.
 *
 * @throws SDKException when the adapter is unknown or not downloaded.
 */
async function adapterPath(adapterId: string): Promise<string> {
  const entry = await loraCapability.getCatalogEntry({ adapterId });
  const path = entry.entry?.localPath ?? '';
  if (!path) {
    throw SDKException.invalidInput(
      `LoRA adapter '${adapterId}' has no local file; download it through RunAnywhere.models first`
    );
  }
  return path;
}

/** LoRA adapter application. */
export const lora = {
  /**
   * Mix a registered adapter into the loaded model at `scale`.
   *
   * @throws SDKException when the adapter is missing or the apply fails.
   */
  async apply(adapterId: string, scale?: number): Promise<void> {
    const path = await adapterPath(adapterId);
    const result = await loraCapability.apply(
      LoRAApplyRequest.fromPartial({
        adapters: [
          LoRAAdapterConfig.fromPartial({
            adapterPath: path,
            adapterId,
            ...(scale !== undefined ? { scale } : {}),
          }),
        ],
      })
    );
    if (result.errorMessage) {
      throw SDKException.processingFailed(result.errorMessage);
    }
  },

  /** Remove one adapter, or every applied adapter when `adapterId` is omitted. */
  async remove(adapterId?: string): Promise<void> {
    await loraCapability.remove(
      LoRARemoveRequest.fromPartial(
        adapterId ? { adapterIds: [adapterId] } : { clearAll: true }
      )
    );
  },

  /** The adapters currently applied to the loaded model. */
  async list(): Promise<LoraState> {
    return toLoraState(await loraCapability.list());
  },

  /**
   * Adapter catalog: registration, download, import, and per-model lookup.
   *
   * Outside the v3 spec, which routes artifacts through `models.register`.
   * commons keeps LoRA adapters in their own catalog with compatibility
   * metadata the model registry has no field for, so the catalog verbs stay
   * reachable until that merges.
   */
  catalog: {
    register: loraCapability.register,
    registerArtifact: loraCapability.registerArtifact,
    list: loraCapability.listCatalog,
    query: loraCapability.queryCatalog,
    get: loraCapability.getCatalogEntry,
    forModel: loraCapability.adaptersForModel,
    allRegistered: loraCapability.allRegistered,
    download: loraCapability.download,
    importAdapter: loraCapability.importAdapter,
    markDownloadCompleted: loraCapability.markDownloadCompleted,
    markImportCompleted: loraCapability.markImportCompleted,
    checkCompatibility: loraCapability.checkCompatibility,
  },
};
