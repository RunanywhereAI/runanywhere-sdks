import { VoiceEvent, type VoiceEvent as ProtoVoiceEvent } from '@runanywhere/proto-ts/voice_events';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const SET_CALLBACK = 'rac_voice_agent_set_proto_callback';

export class VoiceAgentStreamAdapter {
  static tryDefault(handle: number): VoiceAgentStreamAdapter | null {
    const client = clientFor('voice-agent') ?? clientFor('commons');
    return client ? new VoiceAgentStreamAdapter(client, handle) : null;
  }

  constructor(
    private readonly client: WorkerProtoClient,
    private readonly handle: number,
  ) {}

  stream(): AsyncIterable<ProtoVoiceEvent> {
    return this.client.streamProto(
      SET_CALLBACK,
      [Arg.num(this.handle), Arg.streamCb(false), Arg.num(0)],
      VoiceEvent,
      { persistent: { unsubscribeFn: SET_CALLBACK, unsubscribeArgs: [Arg.num(this.handle), Arg.num(0), Arg.num(0)] } },
    );
  }
}
