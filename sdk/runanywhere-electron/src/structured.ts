// structured.ts — shared building blocks for schema-constrained generation and
// tool calling, so the Node facade (RunAnywhere.ts) and the renderer preload
// build the same grammars/prompts and parse the same way (no duplication).
import { jsonSchemaToGrammar } from './grammar';
import type { JsonSchema } from './grammar';

/** A tool the model may be asked to call. */
export interface ToolSpec {
  name: string;
  description?: string;
  /** JSON-schema (object) describing the call arguments. */
  parameters: JsonSchema;
}

/** A parsed tool call chosen by the model. */
export interface ToolCall {
  name: string;
  arguments: Record<string, unknown>;
}

/** GBNF grammar constraining output to JSON matching `schema`. */
export function objectGrammar(schema: JsonSchema): string {
  return jsonSchemaToGrammar(schema);
}

/** Schema whose value is one well-formed `{ name, arguments }` call for a tool. */
export function toolCallSchema(tools: ToolSpec[]): JsonSchema {
  return {
    anyOf: tools.map((t) => ({
      type: 'object',
      properties: { name: { const: t.name }, arguments: t.parameters },
      required: ['name', 'arguments'],
    })),
  };
}

/** Prompt that lists the tools so the model can choose one. */
export function toolCallPrompt(prompt: string, tools: ToolSpec[]): string {
  const doc = tools
    .map((t) => `- ${t.name}${t.description ? ': ' + t.description : ''}`)
    .join('\n');
  return `${prompt}\n\nAvailable tools:\n${doc}\n\nReply with a single JSON tool call.`;
}

/** Parse constrained output as JSON, with a clear error if it somehow isn't. */
export function parseStructured<T>(text: string, what: string): T {
  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed) as T;
  } catch {
    throw new Error(`${what}: model did not return valid JSON: ${trimmed}`);
  }
}
