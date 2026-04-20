// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import type { ChatSession } from './ChatSession.js';

export class ParseFailedError extends Error {
  constructor(msg: string) { super(msg); this.name = 'ParseFailedError'; }
}

/** Extract the first top-level JSON object from arbitrary text. */
export function extractJSON(text: string): string {
  // Try fenced ```json … ``` first
  const fence = /```(?:json)?\s*([\s\S]*?)```/.exec(text);
  if (fence && fence[1]) {
    const stripped = fence[1].trim();
    if (stripped.startsWith('{') || stripped.startsWith('[')) return stripped;
  }
  // Otherwise find the first balanced { … }
  const start = text.indexOf('{');
  if (start < 0) throw new ParseFailedError(`no '{' in: ${text}`);
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (escaped) { escaped = false; continue; }
    if (c === '\\') { escaped = true; continue; }
    if (c === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return text.substring(start, i + 1);
    }
  }
  throw new ParseFailedError(`unbalanced braces in: ${text}`);
}

/**
 * Ask the model to produce JSON matching a schema, then parse.
 * Retries up to maxAttempts on parse failure.
 */
export async function generateStructured<T>(
  chat: ChatSession,
  query: string,
  schemaHint: string,
  maxAttempts = 3,
): Promise<T> {
  const fullQuery = `${query}

Respond with a JSON object matching this schema:
${schemaHint}

Respond ONLY with valid JSON. No prose before or after. No markdown
code fences. Just the JSON object.`;

  let lastError: unknown;
  const { ChatMessage } = await import('./ChatSession.js');
  for (let i = 0; i < maxAttempts; i++) {
    try {
      const text = await chat.generateText([ChatMessage.user(fullQuery)]);
      const json = extractJSON(text);
      return JSON.parse(json) as T;
    } catch (e) { lastError = e; }
  }
  throw lastError instanceof Error ? lastError : new ParseFailedError('all retries failed');
}
