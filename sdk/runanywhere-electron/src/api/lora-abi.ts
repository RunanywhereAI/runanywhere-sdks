// lora-abi.ts — typed access to the commons lifecycle LoRA ABI.
//
// The component entry points these replace (rac_llm_component_load_lora and
// friends) needed a handle the SDK stopped creating in F4, when language models
// moved into commons' lifecycle store. These read that store instead.

import {
  LoraApplyRequest,
  LoraApplyResult,
  LoraRemoveRequest,
  LoraState,
} from '@runanywhere/proto-ts/lora_options';
import type { RaBackend } from './backend';
import { invokeProto } from './proto-abi';
import { newRequestId } from './types';

/** The commons LoRA layer, bound to one backend. */
export class LoraAbi {
  constructor(private readonly backend: RaBackend) {}

  async apply(request: {
    adapters: Array<{ adapterId: string; adapterPath?: string; scale?: number }>;
    keepExisting: boolean;
  }): Promise<LoraApplyResult> {
    return invokeProto(
      (bytes) => this.backend.loraApplyProto(bytes),
      LoraApplyRequest,
      LoraApplyRequest.fromPartial({ requestId: newRequestId('lora'), ...request }),
      LoraApplyResult
    );
  }

  async remove(request: { adapterIds: string[]; clearAll: boolean }): Promise<LoraState> {
    return invokeProto(
      (bytes) => this.backend.loraRemoveProto(bytes),
      LoraRemoveRequest,
      LoraRemoveRequest.fromPartial(request),
      LoraState
    );
  }

  /**
   * What is applied right now. The request is a `LoraState` too: commons reads
   * the base model from the lifecycle store rather than from the argument, so
   * an empty one is the whole query.
   */
  async state(): Promise<LoraState> {
    return invokeProto(
      (bytes) => this.backend.loraStateProto(bytes),
      LoraState,
      LoraState.fromPartial({}),
      LoraState
    );
  }
}
