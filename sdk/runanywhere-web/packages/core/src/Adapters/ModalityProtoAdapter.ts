/**
 * Barrel entry for the modality proto adapters.
 *
 * Each per-modality adapter lives in its own file under `./Adapters/`:
 *   - {@link LLMProtoAdapter}
 *   - {@link STTProtoAdapter}
 *   - {@link TTSProtoAdapter}
 *   - {@link VADProtoAdapter}
 *   - {@link VLMProtoAdapter}
 *   - {@link EmbeddingsProtoAdapter}
 *   - {@link DiffusionProtoAdapter}
 *   - {@link RAGProtoAdapter}
 *   - {@link LoRAProtoAdapter}
 *   - {@link VoiceAgentProtoAdapter}
 *   - {@link StructuredOutputProtoAdapter}
 *
 * Shared types and helpers (`ModalityProtoModule`, `ProtoEventHandler`,
 * `streamCallback`, etc.) live in `./ProtoAdapterTypes.ts`.
 *
 * The {@link ModalityProtoAdapter} aggregator class retains its default-module
 * lifecycle (`setDefaultModule` / `clearDefaultModule` / `tryDefault`) and
 * its per-modality factory methods so callers that prefer a single entry
 * point keep working unchanged.
 */

import { DiffusionProtoAdapter } from './DiffusionProtoAdapter.js';
import { EmbeddingsProtoAdapter } from './EmbeddingsProtoAdapter.js';
import { LLMProtoAdapter } from './LLMProtoAdapter.js';
import { LoRAProtoAdapter } from './LoRAProtoAdapter.js';
import {
  adapterState,
  type ModalityCapabilityName,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';
import { RAGProtoAdapter } from './RAGProtoAdapter.js';
import { STTProtoAdapter } from './STTProtoAdapter.js';
import { StructuredOutputProtoAdapter } from './StructuredOutputProtoAdapter.js';
import { TTSProtoAdapter } from './TTSProtoAdapter.js';
import { VADProtoAdapter } from './VADProtoAdapter.js';
import { VLMProtoAdapter } from './VLMProtoAdapter.js';
import { VoiceAgentProtoAdapter } from './VoiceAgentProtoAdapter.js';

/**
 * Subset of `WasmCapability` that maps to a ModalityProtoModule slot. The
 * 'commons' capability is intentionally excluded — modality verbs route by
 * primitive, not by 'commons'. EmscriptenModule.ts filters down to this
 * subset before calling `registerModuleCapabilities`.
 */
const MODALITY_CAPABILITIES: ReadonlySet<string> = new Set<ModalityCapabilityName>([
  'llm',
  'vlm',
  'stt',
  'tts',
  'vad',
  'embedding',
  'rag',
  'diffusion',
  'structured-output',
  'tool-calling',
  'lora',
  'voice-agent',
]);

export { DiffusionProtoAdapter } from './DiffusionProtoAdapter.js';
export { EmbeddingsProtoAdapter } from './EmbeddingsProtoAdapter.js';
export { LLMProtoAdapter } from './LLMProtoAdapter.js';
export { LoRAProtoAdapter } from './LoRAProtoAdapter.js';
export { RAGProtoAdapter } from './RAGProtoAdapter.js';
export { STTProtoAdapter } from './STTProtoAdapter.js';
export { StructuredOutputProtoAdapter } from './StructuredOutputProtoAdapter.js';
export { TTSProtoAdapter } from './TTSProtoAdapter.js';
export { VADProtoAdapter } from './VADProtoAdapter.js';
export { VLMProtoAdapter } from './VLMProtoAdapter.js';
export { VoiceAgentProtoAdapter } from './VoiceAgentProtoAdapter.js';
export type {
  ModalityProtoModule,
  ProtoEventHandler,
} from './ProtoAdapterTypes.js';

export class ModalityProtoAdapter {
  /**
   * @deprecated Prefer `registerModuleCapabilities([...], mod)` so each
   * backend registers only the modalities it actually serves. This shim
   * registers `module` for EVERY modality slot, replicating the pre-P4
   * monolithic behavior — useful only when a single artifact really does
   * own every modality (legacy tests, embedded apps).
   */
  static setDefaultModule(module: ModalityProtoModule): void {
    adapterState.defaultModule = module;
    for (const cap of MODALITY_CAPABILITIES) {
      adapterState.modalitySlots[cap as ModalityCapabilityName] = module;
    }
  }

  /**
   * Push `module` into each capability slot in `capabilities` that
   * corresponds to a modality. Non-modality entries (e.g. `'commons'`)
   * are filtered out. Also updates the legacy aggregate `defaultModule`
   * pointer so `ModalityProtoAdapter.tryDefault()` still returns a useful
   * module — preferring `'llm'`-owning then the first claimed slot.
   *
   * Called by `registerWasmModule(...)` in `EmscriptenModule.ts`.
   */
  static registerModuleCapabilities(
    capabilities: readonly string[],
    module: ModalityProtoModule,
  ): void {
    for (const cap of capabilities) {
      if (MODALITY_CAPABILITIES.has(cap)) {
        adapterState.modalitySlots[cap as ModalityCapabilityName] = module;
      }
    }
    // Keep the legacy `defaultModule` non-null so `tryDefault()` returns
    // something usable — prefer the LLM-owning module (the historical
    // anchor) then fall back to any non-null slot.
    adapterState.defaultModule =
      adapterState.modalitySlots.llm
      ?? adapterState.modalitySlots.vlm
      ?? adapterState.modalitySlots.stt
      ?? adapterState.modalitySlots.tts
      ?? adapterState.modalitySlots.vad
      ?? adapterState.modalitySlots.embedding
      ?? adapterState.modalitySlots.rag
      ?? adapterState.modalitySlots.diffusion
      ?? adapterState.modalitySlots['structured-output']
      ?? adapterState.modalitySlots['tool-calling']
      ?? adapterState.modalitySlots.lora
      ?? adapterState.modalitySlots['voice-agent']
      ?? null;
  }

  /**
   * Drop `module` from any modality slot it currently occupies — called
   * from `unregisterWasmModule(...)`. Slots that point at a different
   * module are left intact; this preserves sibling backends across a
   * single-bridge teardown.
   */
  static unregisterModuleCapabilities(
    capabilities: readonly string[],
    module: ModalityProtoModule,
  ): void {
    // Tear down per-handle VAD callbacks owned by this module before
    // releasing slots — they would otherwise leak function-table indices.
    for (const [handle, callbackPtr] of Array.from(adapterState.vadActivityCallbackPtrs)) {
      try {
        module._rac_vad_component_set_activity_proto_callback?.(handle, 0, 0);
        module.removeFunction?.(callbackPtr);
      } catch { /* ignore */ }
      adapterState.vadActivityCallbackPtrs.delete(handle);
    }
    for (const cap of capabilities) {
      if (!MODALITY_CAPABILITIES.has(cap)) continue;
      const slot = cap as ModalityCapabilityName;
      if (adapterState.modalitySlots[slot] === module) {
        adapterState.modalitySlots[slot] = null;
      }
    }
    if (adapterState.defaultModule === module) {
      adapterState.defaultModule =
        adapterState.modalitySlots.llm
        ?? adapterState.modalitySlots.vlm
        ?? adapterState.modalitySlots.stt
        ?? adapterState.modalitySlots.tts
        ?? adapterState.modalitySlots.vad
        ?? null;
    }
  }

  static clearDefaultModule(): void {
    if (adapterState.defaultModule) {
      for (const [handle, callbackPtr] of adapterState.vadActivityCallbackPtrs) {
        adapterState.defaultModule._rac_vad_component_set_activity_proto_callback?.(handle, 0, 0);
        adapterState.defaultModule.removeFunction?.(callbackPtr);
      }
    }
    adapterState.vadActivityCallbackPtrs.clear();
    adapterState.defaultModule = null;
    for (const cap of MODALITY_CAPABILITIES) {
      adapterState.modalitySlots[cap as ModalityCapabilityName] = null;
    }
  }

  static tryDefault(): ModalityProtoAdapter | null {
    return adapterState.defaultModule
      ? new ModalityProtoAdapter(adapterState.defaultModule)
      : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  llm(): LLMProtoAdapter {
    return new LLMProtoAdapter(this.module);
  }

  stt(): STTProtoAdapter {
    return new STTProtoAdapter(this.module);
  }

  tts(): TTSProtoAdapter {
    return new TTSProtoAdapter(this.module);
  }

  vad(): VADProtoAdapter {
    return new VADProtoAdapter(this.module);
  }

  voiceAgent(): VoiceAgentProtoAdapter {
    return new VoiceAgentProtoAdapter(this.module);
  }

  vlm(): VLMProtoAdapter {
    return new VLMProtoAdapter(this.module);
  }

  embeddings(): EmbeddingsProtoAdapter {
    return new EmbeddingsProtoAdapter(this.module);
  }

  diffusion(): DiffusionProtoAdapter {
    return new DiffusionProtoAdapter(this.module);
  }

  rag(): RAGProtoAdapter {
    return new RAGProtoAdapter(this.module);
  }

  lora(): LoRAProtoAdapter {
    return new LoRAProtoAdapter(this.module);
  }

  structuredOutput(): StructuredOutputProtoAdapter {
    return new StructuredOutputProtoAdapter(this.module);
  }
}
