// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import 'package:runanywhere_core/adapter/chat_session.dart';
import 'package:runanywhere_core/adapter/tool_calling.dart';
import 'package:runanywhere_core/adapter/structured_output.dart';
import 'package:runanywhere_core/adapter/types.dart';
import 'package:test/test.dart';

void main() {
  group('ChatSession.renderMessages', () {
    test('produces ChatML-formatted prompt', () {
      final r = ChatSession.renderMessages([
        ChatMessage.system('Be helpful.'),
        ChatMessage.user('Hi'),
      ]);
      expect(r.contains('<|im_start|>system'), isTrue);
      expect(r.contains('Be helpful.'), isTrue);
      expect(r.contains('<|im_start|>user'), isTrue);
      expect(r.endsWith('<|im_start|>assistant\n'), isTrue);
    });

    test('skips system when injected', () {
      final r = ChatSession.renderMessages([
        ChatMessage.system('sys'),
        ChatMessage.user('hi'),
      ], skipSystem: true);
      expect(r.contains('<|im_start|>system'), isFalse);
      expect(r.contains('<|im_start|>user'), isTrue);
    });
  });

  group('ToolFormatter', () {
    test('systemPrompt emits tool schema', () {
      final p = ToolFormatter.systemPrompt([
        ToolDefinition(
          name: 'get_weather',
          description: 'Get weather',
          parameters: [
            ToolParameter(name: 'city', type: 'string', description: 'City'),
            ToolParameter(name: 'unit', type: 'string',
                           description: 'C or F', required: false),
          ],
        ),
      ]);
      expect(p.contains('get_weather'), isTrue);
      expect(p.contains('city'), isTrue);
      expect(p.contains('optional'), isTrue);
      expect(p.contains('<tool_call>'), isTrue);
    });

    test('parseToolCalls extracts valid call', () {
      final raw = 'Sure. <tool_call>{"name":"x","arguments":{"y":1}}</tool_call>';
      final calls = ToolFormatter.parseToolCalls(raw);
      expect(calls.length, 1);
      expect(calls[0].name, 'x');
      expect(calls[0].arguments['y'], 1);
    });

    test('parseToolCalls skips malformed blocks', () {
      final raw = '<tool_call>not json</tool_call>'
          '<tool_call>{"name":"ok","arguments":{}}</tool_call>';
      final calls = ToolFormatter.parseToolCalls(raw);
      expect(calls.length, 1);
      expect(calls[0].name, 'ok');
    });
  });

  group('StructuredOutput.extractJSON', () {
    test('handles fenced block', () {
      final raw = '```json\n{"a":1}\n```';
      expect(StructuredOutput.extractJSON(raw), '{"a":1}');
    });

    test('handles bare object with prose', () {
      expect(StructuredOutput.extractJSON('Hi {"a":1} end'), '{"a":1}');
    });

    test('handles nested braces', () {
      final s = '{"outer":{"inner":true}}';
      expect(StructuredOutput.extractJSON(s), s);
    });

    test('throws on no JSON', () {
      expect(() => StructuredOutput.extractJSON('nothing'),
             throwsA(isA<ParseFailedException>()));
    });
  });

  group('Enums', () {
    test('ModelFormat raw values match C ABI', () {
      expect(ModelFormat.gguf.raw, 1);
      expect(ModelFormat.onnx.raw, 2);
      expect(ModelFormat.whisperKit.raw, 6);
    });

    test('Environment raw values match C ABI', () {
      expect(Environment.development.raw, 0);
      expect(Environment.staging.raw, 1);
      expect(Environment.production.raw, 2);
    });
  });
}
