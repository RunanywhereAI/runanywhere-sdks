// The lora namespace: apply/remove LoRA adapters over the loaded LLM, mirroring
// Swift's LoRA verbs. Commons owns adapter state; this maps protos.
import {
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
} from '@runanywhere/proto-ts/lora_options';

import type { RaBackend } from '../backend.js';
import { SDKException } from '../errors.js';

/** An adapter currently applied to the loaded model. */
export interface AppliedAdapter {
  id: string;
  scale: number;
}

export interface LoraNamespace {
  /** Apply an adapter (an id if registered, else a file path), at an optional scale. */
  apply(adapter: string, scale?: number): Promise<void>;
  /** Remove one applied adapter by id. */
  remove(adapterId: string): Promise<void>;
  /** Remove every applied adapter. */
  removeAll(): Promise<void>;
  /** The adapters currently applied. */
  list(): Promise<AppliedAdapter[]>;
}

export function createLoraNamespace(backend: RaBackend): LoraNamespace {
  return {
    async apply(adapter, scale) {
      const looksLikePath = /[\\/.]/.test(adapter);
      const config = {
        ...(looksLikePath ? { adapterPath: adapter } : { adapterId: adapter }),
        ...(scale !== undefined ? { scale } : {}),
      };
      const res = LoRAApplyResult.decode(
        await backend.loraApply(
          LoRAApplyRequest.encode(LoRAApplyRequest.fromPartial({ adapters: [config] })).finish()
        )
      );
      if (res.error?.message) throw SDKException.of(SDKException.unknown().code, res.error.message);
    },
    async remove(adapterId) {
      await backend.loraRemove(
        LoRARemoveRequest.encode(LoRARemoveRequest.fromPartial({ adapterIds: [adapterId] })).finish()
      );
    },
    async removeAll() {
      await backend.loraRemove(
        LoRARemoveRequest.encode(LoRARemoveRequest.fromPartial({ clearAll: true })).finish()
      );
    },
    async list() {
      const state = LoRAState.decode(
        await backend.loraState(LoRAState.encode(LoRAState.fromPartial({})).finish())
      );
      return (state.loadedAdapters ?? []).map((a) => ({ id: a.adapterId, scale: a.scale }));
    },
  };
}
