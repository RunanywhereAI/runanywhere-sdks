// SPDX-License-Identifier: Apache-2.0

// Behavioral guard for the "unsupported model categories never fall through to
// LLM" contract. RunAnywhereModels routes load/unload/current-model by
// ModelInfo.category; categories without a dedicated Flutter capability
// (speaker diarization, semantic segmentation) must throw
// SDKException.unsupportedModality rather than silently resolving to the LLM
// capability. currentLoadedId() reaches the same routing switch as
// loadModel()/unloadModel() but hits the unsupported branches synchronously
// without requiring DartBridge initialization, so this exercises the real
// dispatch — not the source text of runanywhere_models.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/errors.pb.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';

void main() {
  group('unsupported model categories never fall through to LLM', () {
    const unsupported = <ModelCategory>[
      ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
      ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
    ];

    for (final category in unsupported) {
      test('${category.name} routes to unsupportedModality, not LLM', () async {
        await expectLater(
          RunAnywhereModels.shared.currentLoadedId(category),
          throwsA(
            isA<SDKException>().having(
              (e) => e.code,
              'code',
              ErrorCode.ERROR_CODE_UNSUPPORTED_MODALITY,
            ),
          ),
        );
      });
    }
  });
}
