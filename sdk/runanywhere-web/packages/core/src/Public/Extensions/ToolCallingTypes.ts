/** RunAnywhere Web SDK - Tool Calling Types */

/** Type-safe JSON value for tool arguments and results. */
export type ToolValue =
  | { type: 'string'; value: string }
  | { type: 'number'; value: number }
  | { type: 'boolean'; value: boolean }
  | { type: 'array'; value: ToolValue[] }
  | { type: 'object'; value: Record<string, ToolValue> }
  | { type: 'null' };

/** Parameter types for tool arguments. */
export type ToolParameterType = 'string' | 'number' | 'boolean' | 'object' | 'array';

/** A single parameter definition for a tool. */
export interface ToolParameter {
  name: string;
  type: ToolParameterType;
  description: string;
  required?: boolean;
  enumValues?: string[];
}

/** Definition of a tool that the LLM can use. */
export interface ToolDefinition {
  name: string;
  description: string;
  parameters: ToolParameter[];
  category?: string;
}

/** A request from the LLM to execute a tool. */
export interface ToolCall {
  toolName: string;
  arguments: Record<string, ToolValue>;
  callId?: string;
}

/** Result of executing a tool. */
export interface ToolResult {
  toolName: string;
  success: boolean;
  result?: Record<string, ToolValue>;
  error?: string;
  callId?: string;
}

/** Tool calling format names. */
export enum ToolCallFormat {
  Default = 'default',
  LFM2 = 'lfm2',
}

/** Options for tool-enabled generation. */
export interface ToolCallingOptions {
  tools?: ToolDefinition[];
  maxToolCalls?: number;
  autoExecute?: boolean;
  temperature?: number;
  maxTokens?: number;
  systemPrompt?: string;
  replaceSystemPrompt?: boolean;
  keepToolsAvailable?: boolean;
  format?: ToolCallFormat;
}

/** Result of a generation that may include tool calls. */
export interface ToolCallingResult {
  text: string;
  toolCalls: ToolCall[];
  toolResults: ToolResult[];
  isComplete: boolean;
}

/** Executor function for a tool. Takes arguments, returns result data. */
export type ToolExecutor = (
  args: Record<string, ToolValue>,
) => Promise<Record<string, ToolValue>>;
