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

import { DiffusionProtoAdapter } from './DiffusionProtoAdapter';
import { EmbeddingsProtoAdapter } from './EmbeddingsProtoAdapter';
import { LLMProtoAdapter } from './LLMProtoAdapter';
import { LoRAProtoAdapter } from './LoRAProtoAdapter';
import {
  adapterState,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';
import { RAGProtoAdapter } from './RAGProtoAdapter';
import { STTProtoAdapter } from './STTProtoAdapter';
import { StructuredOutputProtoAdapter } from './StructuredOutputProtoAdapter';
import { TTSProtoAdapter } from './TTSProtoAdapter';
import { VADProtoAdapter } from './VADProtoAdapter';
import { VLMProtoAdapter } from './VLMProtoAdapter';
import { VoiceAgentProtoAdapter } from './VoiceAgentProtoAdapter';

export { DiffusionProtoAdapter } from './DiffusionProtoAdapter';
export { EmbeddingsProtoAdapter } from './EmbeddingsProtoAdapter';
export { LLMProtoAdapter } from './LLMProtoAdapter';
export { LoRAProtoAdapter } from './LoRAProtoAdapter';
export { RAGProtoAdapter } from './RAGProtoAdapter';
export { STTProtoAdapter } from './STTProtoAdapter';
export { StructuredOutputProtoAdapter } from './StructuredOutputProtoAdapter';
export { TTSProtoAdapter } from './TTSProtoAdapter';
export { VADProtoAdapter } from './VADProtoAdapter';
export { VLMProtoAdapter } from './VLMProtoAdapter';
export { VoiceAgentProtoAdapter } from './VoiceAgentProtoAdapter';
export type {
  ModalityProtoModule,
  ProtoEventHandler,
} from './ProtoAdapterTypes';

export class ModalityProtoAdapter {
  static setDefaultModule(module: ModalityProtoModule): void {
    adapterState.defaultModule = module;
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
