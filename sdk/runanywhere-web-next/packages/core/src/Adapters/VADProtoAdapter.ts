import {
  SpeechActivityEvent,
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  type SpeechActivityEvent as ProtoSpeechActivityEvent,
  type VADConfiguration as ProtoVADConfiguration,
  type VADOptions as ProtoVADOptions,
  type VADResult as ProtoVADResult,
  type VADStatistics as ProtoVADStatistics,
} from '@runanywhere/proto-ts/vad_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const SET_ACTIVITY_CALLBACK = 'rac_vad_component_set_activity_proto_callback';

export class VADProtoAdapter {
  static tryDefault(): VADProtoAdapter | null {
    const client = clientFor('vad');
    return client ? new VADProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  async configure(handle: number, config: ProtoVADConfiguration): Promise<boolean> {
    const bytes = VADConfiguration.encode(config).finish();
    const rc = await this.client.callRc('rac_vad_component_configure_proto', [Arg.num(handle), Arg.bytes(bytes)]);
    return rc === 0;
  }

  process(
    handle: number,
    samples: Float32Array,
    options: ProtoVADOptions,
  ): Promise<ProtoVADResult | null> {
    const sampleBytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
    const optionsBytes = VADOptions.encode(options).finish();
    return this.client.callProto(
      'rac_vad_component_process_proto',
      [Arg.num(handle), Arg.bytesPtr(sampleBytes), Arg.num(samples.length), Arg.bytes(optionsBytes), Arg.outProto()],
      VADResult,
    );
  }

  statistics(handle: number): Promise<ProtoVADStatistics | null> {
    return this.client.callProto(
      'rac_vad_component_get_statistics_proto',
      [Arg.num(handle), Arg.outProto()],
      VADStatistics,
    );
  }

  setActivityHandler(
    handle: number,
    onEvent: (event: ProtoSpeechActivityEvent) => void,
  ): () => void {
    return this.client.subscribe(
      SET_ACTIVITY_CALLBACK,
      { fn: SET_ACTIVITY_CALLBACK, args: [Arg.num(handle), Arg.num(0), Arg.num(0)] },
      [Arg.num(handle), Arg.streamCb(false), Arg.num(0)],
      SpeechActivityEvent,
      onEvent,
    );
  }
}
