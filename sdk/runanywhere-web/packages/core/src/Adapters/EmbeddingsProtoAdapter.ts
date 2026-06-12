import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';

export class EmbeddingsProtoAdapter {
  static tryDefault(): EmbeddingsProtoAdapter | null {
    const mod = adapterState.modalitySlots.embedding;
    return mod ? new EmbeddingsProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoEmbeddings(): boolean {
    return missingExports(this.module, ['_rac_embeddings_embed_batch_proto']).length === 0;
  }

  embedBatch(
    handle: number,
    request: ProtoEmbeddingsRequest,
  ): ProtoEmbeddingsResult | null {
    if (!ensureExports(this.module, 'embeddings.embedBatch', [
      '_rac_embeddings_embed_batch_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_embeddings_embed_batch_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_embeddings_embed_batch_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
