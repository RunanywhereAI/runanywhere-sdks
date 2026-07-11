import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class EmbeddingsProtoAdapter {
  static tryDefault(): EmbeddingsProtoAdapter | null {
    const mod = adapterState.modalitySlots.embedding;
    return mod ? new EmbeddingsProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoEmbeddings(): boolean {
    return missingExports(this.module, ['_rac_embeddings_embed_batch_proto']).length === 0;
  }

  async embedBatch(
    handle: number,
    request: ProtoEmbeddingsRequest,
  ): Promise<ProtoEmbeddingsResult | null> {
    if (!ensureExports(this.module, 'embeddings.embedBatch', [
      '_rac_embeddings_embed_batch_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_embeddings_embed_batch_proto',
        ['number', 'number', 'number', 'number'],
        [handle, requestPtr, requestSize, outResult],
        () => this.module._rac_embeddings_embed_batch_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_embeddings_embed_batch_proto',
    );
  }

  supportsLifecycleProtoEmbeddings(): boolean {
    return missingExports(
      this.module,
      ['_rac_embeddings_embed_batch_lifecycle_proto'],
    ).length === 0;
  }

  async embedBatchLifecycle(
    request: ProtoEmbeddingsRequest,
  ): Promise<ProtoEmbeddingsResult | null> {
    if (!ensureExports(this.module, 'embeddings.embedBatchLifecycle', [
      '_rac_embeddings_embed_batch_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      EmbeddingsRequest,
      EmbeddingsResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_embeddings_embed_batch_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_embeddings_embed_batch_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_embeddings_embed_batch_lifecycle_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
