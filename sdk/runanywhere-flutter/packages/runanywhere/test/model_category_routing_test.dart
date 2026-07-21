// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unsupported model categories never fall through to LLM', () {
    final source = File(
      'lib/public/capabilities/runanywhere_models.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION'),
    );
    expect(
      source,
      contains('ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION'),
    );
    expect(
      source,
      isNot(contains('default:\n        return RunAnywhereLLM.shared')),
    );
    expect(
      RegExp(
        r'default:\s+throw SDKException\.unsupportedModality',
        multiLine: true,
      ).allMatches(source).length,
      3,
    );
  });
}
