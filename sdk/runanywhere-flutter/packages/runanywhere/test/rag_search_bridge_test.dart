// SPDX-License-Identifier: Apache-2.0

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/rag.pb.dart' as rag_pb;
import 'package:runanywhere/public/api/types/results.dart';

void main() {
  group('rag.search bridge encode/decode', () {
    test('builds RAGSearchRequest with question and topK', () {
      final request = rag_pb.RAGSearchRequest(
        question: 'what is blue?',
        retrievalTopK: 3,
        similarityThreshold: 0.4,
      );

      expect(request.question, 'what is blue?');
      expect(request.retrievalTopK, 3);
      expect(request.hasSimilarityThreshold(), isTrue);
      expect(request.similarityThreshold, closeTo(0.4, 1e-6));
      // Retrieval-only — no generation knobs on this message.
      expect(request.writeToBuffer(), isNotEmpty);
    });

    test('maps RAGSearchResponse chunks onto Match', () {
      final chunk = rag_pb.RAGSearchResult(
        text: 'the sky is blue',
        similarityScore: 0.91,
      )..metadata['source'] = 'facts';
      final response = rag_pb.RAGSearchResponse(
        chunks: [
          chunk,
          rag_pb.RAGSearchResult(
            text: 'water looks blue',
            similarityScore: 0.72,
          ),
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
        question: 'round trip',
        retrievalTopK: 5,
      );
      final decodedRequest =
          rag_pb.RAGSearchRequest.fromBuffer(request.writeToBuffer());
      expect(decodedRequest.question, 'round trip');
      expect(decodedRequest.retrievalTopK, 5);

      final response = rag_pb.RAGSearchResponse(
        chunks: [
          rag_pb.RAGSearchResult(text: 'chunk', similarityScore: 0.5),
        ],
      );
      final decodedResponse =
          rag_pb.RAGSearchResponse.fromBuffer(response.writeToBuffer());
      expect(decodedResponse.chunks, hasLength(1));
      expect(decodedResponse.chunks.first.text, 'chunk');
    });
  });
}
