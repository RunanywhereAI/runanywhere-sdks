// SPDX-License-Identifier: Apache-2.0
//
// Pins that public FinishReason mapping preserves commons wire values —
// especially UNSPECIFIED — and never invents toolCalls/stop from local
// tool-call presence.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/finish_reason.pbenum.dart' as wire
    show FinishReason;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationResult;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCall, ToolCallingResult;
import 'package:runanywhere/generated/vlm_options.pb.dart' show VLMResult;
import 'package:runanywhere/public/api/types/results.dart';

void main() {
  group('FinishReason mapping', () {
    test('UNSPECIFIED stays unspecified even when tool calls are present', () {
      final proto = LLMGenerationResult(
        text: '',
        finishReason: wire.FinishReason.FINISH_REASON_UNSPECIFIED,
        toolCalls: [ToolCall(id: '1', name: 'lookup')],
      );

      final result = GenerationResult.fromLlm(proto);

      expect(result.finishReason, FinishReason.unspecified);
      expect(result.toolCalls, hasLength(1));
    });

    test('TOOL_CALLS maps without consulting toolCalls.length', () {
      final withCalls = GenerationResult.fromLlm(
        LLMGenerationResult(
          finishReason: wire.FinishReason.FINISH_REASON_TOOL_CALLS,
          toolCalls: [ToolCall(id: '1', name: 'lookup')],
        ),
      );
      final withoutCalls = GenerationResult.fromLlm(
        LLMGenerationResult(
          finishReason: wire.FinishReason.FINISH_REASON_TOOL_CALLS,
        ),
      );

      expect(withCalls.finishReason, FinishReason.toolCalls);
      expect(withoutCalls.finishReason, FinishReason.toolCalls);
    });

    test('STOP and LENGTH map exactly', () {
      expect(
        GenerationResult.fromLlm(
          LLMGenerationResult(finishReason: wire.FinishReason.FINISH_REASON_STOP),
        ).finishReason,
        FinishReason.stop,
      );
      expect(
        GenerationResult.fromLlm(
          LLMGenerationResult(
            finishReason: wire.FinishReason.FINISH_REASON_LENGTH,
          ),
        ).finishReason,
        FinishReason.length,
      );
    });

    test('ToolCallingResult uses commons finish_reason, not tool count', () {
      final unspecified = GenerationResult.fromToolCalling(
        ToolCallingResult(
          toolCalls: [ToolCall(id: '1', name: 'lookup')],
          finishReason: wire.FinishReason.FINISH_REASON_UNSPECIFIED,
        ),
      );
      final stopWithTools = GenerationResult.fromToolCalling(
        ToolCallingResult(
          toolCalls: [ToolCall(id: '1', name: 'lookup')],
          finishReason: wire.FinishReason.FINISH_REASON_STOP,
        ),
      );

      expect(unspecified.finishReason, FinishReason.unspecified);
      expect(stopWithTools.finishReason, FinishReason.stop);
    });

    test('empty VLM finishReason string stays unspecified', () {
      final result = GenerationResult.fromVlm(VLMResult(text: 'hi'));
      expect(result.finishReason, FinishReason.unspecified);
    });
  });
}
