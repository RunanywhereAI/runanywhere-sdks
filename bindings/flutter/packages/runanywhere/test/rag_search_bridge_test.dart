// SPDX-License-Identifier: Apache-2.0

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/rag.pb.dart' as rag_pb;
import 'package:runanywhere/public/api/types/results.dart';

void main() {
  group('rag.search bridge encode/decode', () {
    test('builds RAGSearchRequest with query and topK', () {
      // `RAGSearchRequest.question`/`similarityThreshold`/`retrievalTopK`
      // (flat fields) were restructured into `query` + nested
      // `retrieval: RAGRetrievalOptions{scoreThreshold, topK}`
      // (idl/rag.proto).
      final request = rag_pb.RAGSearchRequest(
        query: 'what is blue?',
        retrieval: rag_pb.RAGRetrievalOptions(topK: 3, scoreThreshold: 0.4),
      );

      expect(request.query, 'what is blue?');
      expect(request.retrieval.topK, 3);
      expect(request.retrieval.hasScoreThreshold(), isTrue);
      expect(request.retrieval.scoreThreshold, closeTo(0.4, 1e-6));
      // Retrieval-only — no generation knobs on this message.
      expect(request.writeToBuffer(), isNotEmpty);
    });

    test('maps RAGSearchResponse chunks onto Match', () {
      // `RAGSearchResult.similarityScore` was renamed `score`
      // (idl/rag.proto).
      final chunk = rag_pb.RAGSearchResult(
        text: 'the sky is blue',
        score: 0.91,
      )..metadata['source'] = 'facts';
      final response = rag_pb.RAGSearchResponse(
        chunks: [
          chunk,
          rag_pb.RAGSearchResult(text: 'water looks blue', score: 0.72),
        ],
        retrievalTimeMs: Int64(12),
        requestId: 'req-1',
      );

      final matches = response.chunks.map(Match.fromProto).toList();

      expect(matches, hasLength(2));
      expect(matches[0].text, 'the sky is blue');
      expect(matches[0].score, closeTo(0.91, 1e-6));
      expect(matches[0].metadata, {'source': 'facts'});
      expect(matches[1].text, 'water looks blue');
      expect(matches[1].score, closeTo(0.72, 1e-6));
    });

    test('round-trips RAGSearchRequest / RAGSearchResponse bytes', () {
      final request = rag_pb.RAGSearchRequest(
        query: 'round trip',
        retrieval: rag_pb.RAGRetrievalOptions(topK: 5),
      );
      final decodedRequest =
          rag_pb.RAGSearchRequest.fromBuffer(request.writeToBuffer());
      expect(decodedRequest.query, 'round trip');
      expect(decodedRequest.retrieval.topK, 5);

      final response = rag_pb.RAGSearchResponse(
        chunks: [rag_pb.RAGSearchResult(text: 'chunk', score: 0.5)],
      );
      final decodedResponse =
          rag_pb.RAGSearchResponse.fromBuffer(response.writeToBuffer());
      expect(decodedResponse.chunks, hasLength(1));
      expect(decodedResponse.chunks.first.text, 'chunk');
    });
  });
}
