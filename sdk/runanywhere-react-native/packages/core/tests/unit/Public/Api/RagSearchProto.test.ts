/**
 * Unit coverage for the retrieval-only rag.search encode/decode path.
 */

import {
  RAGSearchRequest,
  RAGSearchResponse,
} from '@runanywhere/proto-ts/rag';
import { ErrorCode } from '@runanywhere/proto-ts/errors';
import { SDKException } from '../../../../src/Foundation/Errors/SDKException';
import { toMatch } from '../../../../src/Public/Api/Results';

describe('rag.search proto mapping', () => {
  it('encodes RAGSearchRequest without generation knobs', () => {
    const request = RAGSearchRequest.fromPartial({
      query: 'what is blue?',
      retrieval: {
        topK: 3,
        scoreThreshold: 0.4,
      },
    });
    const bytes = RAGSearchRequest.encode(request).finish();
    const decoded = RAGSearchRequest.decode(bytes);

    expect(decoded.query).toBe('what is blue?');
    expect(decoded.retrieval?.topK).toBe(3);
    expect(decoded.retrieval?.scoreThreshold).toBeCloseTo(0.4);
    expect(decoded.retrieval?.enableMultiQuery).toBe(false);
  });

  it('maps RAGSearchResponse chunks onto public Match', () => {
    const response = RAGSearchResponse.fromPartial({
      chunks: [
        {
          text: 'the sky is blue',
          score: 0.91,
          metadata: { source: 'facts' },
        },
        {
          text: 'water looks blue',
          score: 0.72,
          metadata: {},
        },
      ],
      retrievalTimeMs: 12,
      requestId: 'req-1',
    });

    const matches = response.chunks.map(toMatch);
    expect(matches).toHaveLength(2);
    expect(matches[0]).toMatchObject({
      text: 'the sky is blue',
      score: 0.91,
      metadata: { source: 'facts' },
    });
    expect(matches[1].text).toBe('water looks blue');
  });

  it('featureNotAvailable uses FEATURE_NOT_AVAILABLE', () => {
    const exception = SDKException.featureNotAvailable(
      'rag.search (rac_rag_search_proto)'
    );
    expect(exception.code).toBe(ErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE);
    expect(exception.message).toContain('rac_rag_search_proto');
  });
});
