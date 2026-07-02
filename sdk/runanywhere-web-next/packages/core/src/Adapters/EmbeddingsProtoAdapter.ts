import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class EmbeddingsProtoAdapter {
  static tryDefault(): EmbeddingsProtoAdapter | null {
    const client = clientFor('embedding');
    return client ? new EmbeddingsProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  embedBatch(
    handle: number,
    request: ProtoEmbeddingsRequest,
  ): Promise<ProtoEmbeddingsResult | null> {
    const bytes = EmbeddingsRequest.encode(request).finish();
    return this.client.callProto(
      'rac_embeddings_embed_batch_proto',
      [Arg.num(handle), Arg.bytes(bytes), Arg.outProto()],
      EmbeddingsResult,
    );
  }
}
