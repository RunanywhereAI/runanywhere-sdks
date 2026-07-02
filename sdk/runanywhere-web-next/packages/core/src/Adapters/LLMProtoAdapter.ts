import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  LLMGenerationResult,
  type LLMGenerationResult as ProtoLLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class LLMProtoAdapter {
  static tryDefault(): LLMProtoAdapter | null {
    const client = clientFor('llm');
    return client ? new LLMProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  generate(request: ProtoLLMGenerateRequest): Promise<ProtoLLMGenerationResult | null> {
    const bytes = LLMGenerateRequest.encode(request).finish();
    return this.client.callProto('rac_llm_generate_proto', [Arg.bytes(bytes), Arg.outProto()], LLMGenerationResult);
  }

  generateStream(request: ProtoLLMGenerateRequest): AsyncIterable<ProtoLLMStreamEvent> {
    const bytes = LLMGenerateRequest.encode({ ...request, streamingEnabled: true }).finish();
    return this.client.streamProto(
      'rac_llm_generate_stream_proto',
      [Arg.bytes(bytes), Arg.streamCb(false), Arg.num(0)],
      LLMStreamEvent,
      { stopWhen: (event) => event.isFinal },
    );
  }

  cancel(): Promise<ProtoSDKEvent | null> {
    return this.client.callProto('rac_llm_cancel_proto', [Arg.outProto()], SDKEvent);
  }
}
