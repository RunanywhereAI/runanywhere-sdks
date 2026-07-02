import {
  StructuredOutputParseRequest,
  StructuredOutputResult,
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputResult as ProtoStructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class StructuredOutputProtoAdapter {
  static tryDefault(): StructuredOutputProtoAdapter | null {
    const client = clientFor('structured-output') ?? clientFor('llm');
    return client ? new StructuredOutputProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  parse(request: ProtoStructuredOutputParseRequest): Promise<ProtoStructuredOutputResult | null> {
    return this.client.callProto(
      'rac_structured_output_parse_proto',
      [Arg.bytes(StructuredOutputParseRequest.encode(request).finish()), Arg.outProto()],
      StructuredOutputResult,
    );
  }
}
