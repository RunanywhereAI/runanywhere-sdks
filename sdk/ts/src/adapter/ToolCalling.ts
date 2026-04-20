// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import { ChatMessage, ChatSession } from './ChatSession.js';

export interface ToolParameter {
  name: string;
  type: string;
  description: string;
  required?: boolean;
}

export interface ToolDefinition {
  name: string;
  description: string;
  parameters: ToolParameter[];
}

export interface ToolCall {
  name: string;
  arguments: Record<string, unknown>;
}

export type ToolExecutor = (args: Record<string, unknown>) => Promise<string>;

export const ToolFormatter = {
  systemPrompt(tools: ToolDefinition[]): string {
    if (tools.length === 0) return '';
    let out = 'You have access to the following tools:\n\n';
    for (const t of tools) {
      out += `${t.name}: ${t.description}\nArguments:\n{\n`;
      for (const p of t.parameters) {
        const req = p.required === false ? ' (optional)' : '';
        out += `    "${p.name}": <${p.type}>  // ${p.description}${req}\n`;
      }
      out += '}\n\n';
    }
    out += `
To invoke a tool, reply with EXACTLY:
<tool_call>{"name":"<tool_name>","arguments":{<args_json>}}</tool_call>

Only output the tool call and nothing else when you use a tool.`.trim();
    return out;
  },

  parseToolCalls(text: string): ToolCall[] {
    const calls: ToolCall[] = [];
    const regex = /<tool_call>([\s\S]*?)<\/tool_call>/g;
    let m: RegExpExecArray | null;
    while ((m = regex.exec(text)) !== null) {
      const raw = m[1].trim();
      try {
        const obj = JSON.parse(raw) as { name?: string; arguments?: unknown };
        if (typeof obj.name === 'string' && obj.arguments && typeof obj.arguments === 'object') {
          calls.push({ name: obj.name, arguments: obj.arguments as Record<string, unknown> });
        }
      } catch { /* skip malformed */ }
    }
    return calls;
  },
};

export type ToolCallingReply =
  | { kind: 'assistant'; text: string }
  | { kind: 'tool-calls'; calls: ToolCall[] };

/** High-level tool-calling agent on top of ChatSession. */
export class ToolCallingAgent {
  private readonly chat: ChatSession;
  private readonly history: ChatMessage[] = [];

  constructor(
    public readonly modelId: string,
    public readonly modelPath: string,
    public readonly tools: ToolDefinition[],
    systemPrompt = '',
  ) {
    const toolPrompt = ToolFormatter.systemPrompt(tools);
    const combined = [systemPrompt, toolPrompt].filter((s) => s).join('\n\n');
    this.chat = new ChatSession(modelId, modelPath, combined);
  }

  async send(userMessage: string): Promise<ToolCallingReply> {
    this.history.push(ChatMessage.user(userMessage));
    const response = await this.chat.generateText(this.history);
    this.history.push(ChatMessage.assistant(response));
    const calls = ToolFormatter.parseToolCalls(response);
    if (calls.length > 0) return { kind: 'tool-calls', calls };
    return { kind: 'assistant', text: response };
  }

  async continueAfter(results: { name: string; result: string }[]): Promise<ToolCallingReply> {
    const blob = results.map(({ name, result }) =>
      `Tool \`${name}\` returned:\n${result}`).join('\n\n');
    this.history.push(ChatMessage.tool(blob));
    const response = await this.chat.generateText(this.history);
    this.history.push(ChatMessage.assistant(response));
    const calls = ToolFormatter.parseToolCalls(response);
    if (calls.length > 0) return { kind: 'tool-calls', calls };
    return { kind: 'assistant', text: response };
  }

  resetHistory(): void {
    this.history.length = 0;
    this.chat.resetHistory();
  }

  close(): void { this.chat.close(); }
}
