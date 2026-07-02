import {
  STTOptions,
  STTOutput,
  STTPartialResult,
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class STTProtoAdapter {
  static tryDefault(): STTProtoAdapter | null {
    const client = clientFor('stt');
    return client ? new STTProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  async createComponent(): Promise<number> {
    const { rc, outValues } = await this.client.call('rac_stt_component_create', [Arg.outU32()]);
    if (rc !== 0) throw new Error(`rac_stt_component_create failed (rc=${rc})`);
    const handle = outValues?.[0] ?? 0;
    if (!handle) throw new Error('rac_stt_component_create returned a null handle');
    return handle;
  }

  async loadModel(handle: number, modelPath: string, modelId = '', modelName = ''): Promise<void> {
    const rc = await this.client.callRc('rac_stt_component_load_model', [
      Arg.num(handle),
      Arg.string(modelPath),
      Arg.string(modelId),
      Arg.string(modelName),
    ]);
    if (rc !== 0) throw new Error(`rac_stt_component_load_model failed (rc=${rc})`);
  }

  destroy(handle: number): Promise<number> {
    return this.client.callRc('rac_stt_component_destroy', [Arg.num(handle)]);
  }

  transcribe(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): Promise<ProtoSTTOutput | null> {
    const optionsBytes = STTOptions.encode(options).finish();
    return this.client.callProto(
      'rac_stt_component_transcribe_proto',
      [Arg.num(handle), Arg.bytes(audioData), Arg.bytes(optionsBytes), Arg.outProto()],
      STTOutput,
    );
  }

  transcribeStream(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): AsyncIterable<ProtoSTTPartialResult> {
    const optionsBytes = STTOptions.encode(options).finish();
    return this.client.streamProto(
      'rac_stt_component_transcribe_stream_proto',
      [Arg.num(handle), Arg.bytes(audioData), Arg.bytes(optionsBytes), Arg.streamCb(false), Arg.num(0)],
      STTPartialResult,
      { stopWhen: (event) => event.isFinal },
    );
  }
}
