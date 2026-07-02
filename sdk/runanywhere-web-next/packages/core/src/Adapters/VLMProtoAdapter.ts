import {
  VLMGenerationOptions,
  VLMGenerationRequest,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
  type VLMStreamEvent as ProtoVLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class VLMProtoAdapter {
  static tryDefault(): VLMProtoAdapter | null {
    const client = clientFor('vlm');
    return client ? new VLMProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  process(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult | null> {
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    return this.client.callProto(
      'rac_vlm_process_proto',
      [Arg.num(handle), Arg.bytes(imageBytes), Arg.bytes(optionsBytes), Arg.outProto()],
      VLMResult,
    );
  }

  streamEvents(
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): AsyncIterable<ProtoVLMStreamEvent> {
    const requestBytes = VLMGenerationRequest.encode(
      VLMGenerationRequest.fromPartial({
        images: [image],
        options: { ...options, streamingEnabled: true },
      }),
    ).finish();
    return this.client.streamProto(
      'rac_vlm_stream_proto',
      [Arg.bytes(requestBytes), Arg.streamCb(true), Arg.num(0)],
      VLMStreamEvent,
    );
  }

  async cancel(handle: number): Promise<boolean> {
    return (await this.client.callRc('rac_vlm_cancel_proto', [Arg.num(handle)])) === 0;
  }
}
