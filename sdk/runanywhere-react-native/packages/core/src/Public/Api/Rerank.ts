/**
 * `RunAnywhere.rerank` — cross-encoder scoring of candidate documents.
 */

import { SDKComponent } from '@runanywhere/proto-ts/sdk_events';
import {
  RerankCandidate,
  RerankRequest,
  RerankResult,
} from '@runanywhere/proto-ts/rerank';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { ErrorCode } from '@runanywhere/proto-ts/errors';
import { componentLifecycleSnapshot } from '../Extensions/Models/RunAnywhere+ModelLifecycle';
import { decode, encode, preflight } from './Bridge';
import { toRerankOptions } from './Options';
import { toRankedResults } from './Results';
import type { RankedResult } from './Types';

/** Relevance reranking with the loaded cross-encoder model. */
export const rerank = {
  /**
   * Score every document against `query`, best first.
   *
   * @example
   * const ranked = await RunAnywhere.rerank.rerank('battery life', docs, 3);
   * const best = docs[ranked[0].index];
   *
   * @throws SDKException when no rerank model is loaded or scoring fails.
   */
  async rerank(
    query: string,
    documents: string[],
    topN?: number
  ): Promise<RankedResult[]> {
    const native = await preflight();
    const snapshot = await componentLifecycleSnapshot(
      SDKComponent.SDK_COMPONENT_RERANK
    );
    const modelId = snapshot?.modelId || snapshot?.model?.id || '';
    const modelPath = snapshot?.resolvedPath || snapshot?.model?.localPath || '';
    if (!modelId || !modelPath) {
      throw SDKException.of(
        ErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
        'rerank.rerank needs a loaded rerank model; call RunAnywhere.models.load(id) first'
      );
    }

    const request = RerankRequest.fromPartial({
      query,
      candidates: documents.map((text, index) =>
        RerankCandidate.fromPartial({ id: String(index), text })
      ),
      options: toRerankOptions(topN),
    });
    const resultBytes = await native.rerankProto(
      modelPath,
      modelId,
      snapshot?.model?.name || modelId,
      encode(request, RerankRequest)
    );
    return toRankedResults(decode(resultBytes, RerankResult, 'rerank'));
  },
};
