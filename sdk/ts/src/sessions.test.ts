// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { describe, it, expect } from 'vitest';

const assert = {
  ok(v: unknown, msg?: string): void { expect(v, msg).toBeTruthy(); },
  equal<T>(actual: T, expected: T, msg?: string): void {
    expect(actual, msg).toBe(expected);
  },
  throws(fn: () => unknown, errorType?: unknown): void {
    if (errorType) expect(fn).toThrow(errorType as new () => Error);
    else expect(fn).toThrow();
  },
};

import { ChatSession, ChatMessage } from './adapter/ChatSession.js';
import { ToolFormatter } from './adapter/ToolCalling.js';
import { extractJSON, ParseFailedError } from './adapter/StructuredOutput.js';
import { ModelFormat, Environment } from './adapter/Types.js';

describe('ChatSession.renderMessages', () => {
  it('produces ChatML-formatted prompt', () => {
    const r = ChatSession.renderMessages([
      ChatMessage.system('Be helpful.'),
      ChatMessage.user('Hi'),
    ], false);
    assert.ok(r.includes('<|im_start|>system'));
    assert.ok(r.includes('Be helpful.'));
    assert.ok(r.includes('<|im_start|>user'));
    assert.ok(r.endsWith('<|im_start|>assistant\n'));
  });

  it('skips system when injected', () => {
    const r = ChatSession.renderMessages([
      ChatMessage.system('sys'),
      ChatMessage.user('hi'),
    ], true);
    assert.ok(!r.includes('<|im_start|>system'));
    assert.ok(r.includes('<|im_start|>user'));
  });
});

describe('ToolFormatter', () => {
  it('emits tool schema in system prompt', () => {
    const p = ToolFormatter.systemPrompt([{
      name: 'get_weather',
      description: 'Get weather',
      parameters: [
        { name: 'city', type: 'string', description: 'City' },
        { name: 'unit', type: 'string', description: 'C or F', required: false },
      ],
    }]);
    assert.ok(p.includes('get_weather'));
    assert.ok(p.includes('city'));
    assert.ok(p.includes('optional'));
    assert.ok(p.includes('<tool_call>'));
  });

  it('parses valid tool call block', () => {
    const raw = `Sure. <tool_call>{"name":"x","arguments":{"y":1}}</tool_call>`;
    const calls = ToolFormatter.parseToolCalls(raw);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].name, 'x');
    assert.equal(calls[0].arguments.y, 1);
  });

  it('skips malformed blocks', () => {
    const raw = `<tool_call>not json</tool_call><tool_call>{"name":"ok","arguments":{}}</tool_call>`;
    const calls = ToolFormatter.parseToolCalls(raw);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].name, 'ok');
  });
});

describe('StructuredOutput.extractJSON', () => {
  it('extracts fenced JSON', () => {
    const raw = '```json\n{"a":1}\n```';
    assert.equal(extractJSON(raw), '{"a":1}');
  });

  it('extracts bare object with surrounding prose', () => {
    assert.equal(extractJSON('Hi {"a":1} end'), '{"a":1}');
  });

  it('handles nested braces', () => {
    const s = '{"outer":{"inner":true}}';
    assert.equal(extractJSON(s), s);
  });

  it('throws on no JSON', () => {
    assert.throws(() => extractJSON('no json'), ParseFailedError);
  });
});

describe('Enums', () => {
  it('ModelFormat raw values match C ABI', () => {
    assert.equal(ModelFormat.GGUF, 1);
    assert.equal(ModelFormat.ONNX, 2);
    assert.equal(ModelFormat.WhisperKit, 6);
  });

  it('Environment raw values match C ABI', () => {
    assert.equal(Environment.Development, 0);
    assert.equal(Environment.Staging, 1);
    assert.equal(Environment.Production, 2);
  });
});
