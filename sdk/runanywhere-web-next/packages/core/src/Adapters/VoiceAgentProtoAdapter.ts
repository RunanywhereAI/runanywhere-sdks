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
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class VoiceAgentProtoAdapter {
  static tryDefault(): VoiceAgentProtoAdapter | null {
    const client = clientFor('voice-agent') ?? clientFor('commons');
    return client ? new VoiceAgentProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  initialize(
    handle: number,
    config: ProtoVoiceAgentComposeConfig,
  ): Promise<ProtoVoiceAgentComponentStates | null> {
    return this.client.callProto(
      'rac_voice_agent_initialize_proto',
      [Arg.num(handle), Arg.bytes(VoiceAgentComposeConfig.encode(config).finish()), Arg.outProto()],
      VoiceAgentComponentStates,
    );
  }

  componentStates(handle: number): Promise<ProtoVoiceAgentComponentStates | null> {
    return this.client.callProto(
      'rac_voice_agent_component_states_proto',
      [Arg.num(handle), Arg.outProto()],
      VoiceAgentComponentStates,
    );
  }

  processVoiceTurn(handle: number, audioData: Uint8Array): Promise<ProtoVoiceAgentResult | null> {
    return this.client.callProto(
      'rac_voice_agent_process_voice_turn_proto',
      [Arg.num(handle), Arg.bytes(audioData), Arg.outProto()],
      VoiceAgentResult,
    );
  }

  async destroy(handle: number): Promise<void> {
    await this.client.callRc('rac_voice_agent_component_destroy_proto', [Arg.num(handle)]);
  }
}
