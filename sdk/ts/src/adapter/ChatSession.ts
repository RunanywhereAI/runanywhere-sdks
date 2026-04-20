// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { ModelFormat, LLMTokenKind } from './Types.js';
import { LLMSession } from './LLMSession.js';

export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

export interface ChatMessage {
  role: ChatRole;
  content: string;
}

export const ChatMessage = {
  system:    (content: string): ChatMessage => ({ role: 'system',    content }),
  user:      (content: string): ChatMessage => ({ role: 'user',      content }),
  assistant: (content: string): ChatMessage => ({ role: 'assistant', content }),
  tool:      (content: string): ChatMessage => ({ role: 'tool',      content }),
};

/**
 * Chat-style wrapper over LLMSession. Manages message history and exposes
 * `generate(messages)` → `AsyncIterable<string>` (token text).
 */
export class ChatSession {
  private readonly llm: LLMSession;
  private systemPromptInjected = false;

  constructor(public readonly modelId: string,
              public readonly modelPath: string,
              systemPrompt = '',
              format: ModelFormat = ModelFormat.GGUF) {
    this.llm = new LLMSession(modelId, modelPath, format);
    if (systemPrompt) {
      const rc = this.llm.injectSystemPrompt(systemPrompt);
      this.systemPromptInjected = rc === 0;
    }
  }

  async *generate(messages: ChatMessage[]): AsyncIterable<string> {
    const rendered = ChatSession.renderMessages(messages, this.systemPromptInjected);
    const source = this.systemPromptInjected
      ? this.llm.generateFromContext(rendered)
      : this.llm.generate(rendered);
    for await (const token of source) {
      if (token.kind === LLMTokenKind.Answer) yield token.text;
    }
  }

  async generateText(messages: ChatMessage[]): Promise<string> {
    let buf = '';
    for await (const chunk of this.generate(messages)) buf += chunk;
    return buf;
  }

  cancel(): number { return this.llm.cancel(); }
  resetHistory(): number {
    this.systemPromptInjected = false;
    return this.llm.clearContext();
  }
  close(): void { this.llm.close(); }

  static renderMessages(messages: ChatMessage[], skipSystem: boolean): string {
    let out = '';
    for (const m of messages) {
      if (skipSystem && m.role === 'system') continue;
      out += `<|im_start|>${m.role}\n${m.content}<|im_end|>\n`;
    }
    out += '<|im_start|>assistant\n';
    return out;
  }
}
