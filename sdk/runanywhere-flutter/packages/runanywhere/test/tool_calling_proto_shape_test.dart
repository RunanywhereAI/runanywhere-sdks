// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/runanywhere_protos.dart'
    show
        ToolCallFormatName,
        ToolCallingOptions,
        ToolCallingSessionCreateRequest;

void main() {
  group('tool calling proto shape', () {
    test('uses generated format enum without legacy format hints', () {
      final options = ToolCallingOptions(
        format: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2,
        maxToolCalls: 3,
      );

      expect(options.hasFormat(), isTrue);
      expect(options.format, ToolCallFormatName.TOOL_CALL_FORMAT_NAME_LFM2);
      expect(options.hasMaxToolCalls(), isTrue);
      expect(options.maxToolCalls, 3);
    });

    test('session request carries execution and validation policy', () {
      final request = ToolCallingSessionCreateRequest(
        prompt: 'call the tool',
        validateCalls: false,
      );

      expect(request.hasValidateCalls(), isTrue);
      expect(request.validateCalls, isFalse);
      expect(request.prompt, 'call the tool');
    });
  });
}
