/**
 * `RunAnywhere.lora` — layer adapters onto the resident base model.
 */

import { SDKException } from '../../../Foundation/SDKException.js';
import {
  applyLoraAdapters,
  getLoraState,
  removeLoraAdapters,
} from '../../Extensions/RunAnywhere+LoRA.js';
import { ModelRegistry } from '../../Extensions/RunAnywhere+ModelRegistry.js';
import type { LoraState } from '../Results.js';
import { toLoraState } from '../Mapping.js';
import { ensureReady } from '../Runtime/Prerequisites.js';

/** LoRA adapters on top of the resident base model. */
export const lora = {
  /**
   * Layer an adapter registered through `models.register` onto the base model.
   *
   * @param scale Adapter strength; unset uses the adapter's own default.
   * @throws SDKException when the adapter is not registered or not downloaded.
   */
  async apply(adapterId: string, scale?: number): Promise<void> {
    await ensureReady();
    const artifact = ModelRegistry.getModel(adapterId);
    if (!artifact?.localPath) {
      throw SDKException.invalidConfiguration(
        `LoRA adapter '${adapterId}' is not downloaded. Register it with models.register(...) and download it first.`,
      );
    }
    const result = await applyLoraAdapters({
      requestId: '',
      replaceExisting: false,
      adapters: [{
        adapterPath: artifact.localPath,
        adapterId,
        scale: scale ?? 1,
        metadata: {},
        targetModules: [],
      }],
    });
    if (!result.success) {
      throw SDKException.processingFailed(
        result.errorMessage || `Applying LoRA adapter '${adapterId}' failed.`,
      );
    }
  },

  /** Remove one adapter, or every applied adapter when the id is omitted. */
  async remove(adapterId?: string): Promise<void> {
    await ensureReady();
    await removeLoraAdapters({
      requestId: '',
      adapterIds: adapterId ? [adapterId] : [],
      adapterPaths: [],
      clearAll: adapterId === undefined,
    });
  },

  /** Adapters currently layered onto the base model. */
  async list(): Promise<LoraState> {
    return toLoraState(await getLoraState());
  },
};
