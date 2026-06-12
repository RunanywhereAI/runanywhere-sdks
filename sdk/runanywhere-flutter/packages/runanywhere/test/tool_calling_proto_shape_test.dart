// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/runanywhere.dart'
    show ToolCallFormatName, ToolCallingOptions;

void main() {
  group('tool calling proto shape', () {
    test('uses generated format enum without legacy format hints', () {
      final options = ToolCallingOptions(
        format: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC,
      );

      expect(options.hasFormat(), isTrue);
      expect(
        options.format,
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC,
      );
      expect(options.formatHint, isEmpty);
    });
  });
}
