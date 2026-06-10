import {
  VoiceAgentComposeConfig,
  VoiceAgentResult,
  type VoiceAgentComposeConfig as ProtoVoiceAgentComposeConfig,
  type VoiceAgentResult as ProtoVoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  VoiceAgentComponentStates,
  type VoiceAgentComponentStates as ProtoVoiceAgentComponentStates,
} from '@runanywhere/proto-ts/voice_events';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';

export class VoiceAgentProtoAdapter {
  static tryDefault(): VoiceAgentProtoAdapter | null {
    const mod = adapterState.modalitySlots['voice-agent'];
    return mod ? new VoiceAgentProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  missingVoiceAgentExports(): string[] {
    return missingExports(this.module, [
      '_rac_voice_agent_initialize_proto',
      '_rac_voice_agent_component_states_proto',
      '_rac_voice_agent_process_voice_turn_proto',
      '_rac_voice_agent_set_proto_callback',
    ]);
  }

  supportsProtoVoiceAgent(): boolean {
    return this.missingVoiceAgentExports().length === 0;
  }

  initialize(
    handle: number,
    config: ProtoVoiceAgentComposeConfig,
  ): ProtoVoiceAgentComponentStates | null {
    if (!ensureExports(this.module, 'voiceAgent.initialize', [
      '_rac_voice_agent_initialize_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      VoiceAgentComposeConfig,
      VoiceAgentComponentStates,
      (configPtr, configSize, outResult) => (
        this.module._rac_voice_agent_initialize_proto!(
          handle,
          configPtr,
          configSize,
          outResult,
        )
      ),
      'rac_voice_agent_initialize_proto',
    );
  }

  componentStates(handle: number): ProtoVoiceAgentComponentStates | null {
    if (!ensureExports(this.module, 'voiceAgent.componentStates', [
      '_rac_voice_agent_component_states_proto',
    ])) {
      return null;
    }
    return this.bridge().callResultProto(
      VoiceAgentComponentStates,
      (outResult) => this.module._rac_voice_agent_component_states_proto!(handle, outResult),
      'rac_voice_agent_component_states_proto',
    );
  }

  processVoiceTurn(handle: number, audioData: Uint8Array): ProtoVoiceAgentResult | null {
    if (!ensureExports(this.module, 'voiceAgent.processVoiceTurn', [
      '_rac_voice_agent_process_voice_turn_proto',
    ])) {
      return null;
    }
    const bridge = this.bridge();
    return bridge.withHeapBytes(audioData, (audioPtr, audioSize) => (
      bridge.callResultProto(
        VoiceAgentResult,
        (outResult) => this.module._rac_voice_agent_process_voice_turn_proto!(
          handle,
          audioPtr,
          audioSize,
          outResult,
        ),
        'rac_voice_agent_process_voice_turn_proto',
      )
    ));
  }

  destroy(handle: number): void {
    this.module._rac_voice_agent_component_destroy_proto?.(handle);
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
