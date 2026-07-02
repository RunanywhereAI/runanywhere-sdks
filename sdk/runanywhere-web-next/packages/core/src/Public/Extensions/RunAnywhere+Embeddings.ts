import {
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
  type EmbeddingsResult as ProtoEmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { EmbeddingsProtoAdapter } from '../../Adapters/EmbeddingsProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    embed(handle: number, request: ProtoEmbeddingsRequest): Promise<ProtoEmbeddingsResult | null>;
  }
}

RunAnywhereSDK.prototype.embed = function (this: RunAnywhereSDK, handle, request) {
  this.ensureInitialized();
  const adapter = EmbeddingsProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('Embeddings');
  return adapter.embedBatch(handle, request);
};
