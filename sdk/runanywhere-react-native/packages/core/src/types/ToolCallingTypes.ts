/**
 * ToolCallingTypes.ts
 *
 * Type definitions for Tool Calling functionality.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 */

// =============================================================================
// Parameter Types
// =============================================================================

/**
 * Supported parameter types for tool arguments
 */
export type ParameterType = 'string' | 'number' | 'boolean' | 'object' | 'array';

/**
 * A single parameter definition for a tool
 */
export interface ToolParameter {
  /** Parameter name */
  name: string;

  /** Data type of the parameter */
  type: ParameterType;

  /** Human-readable description */
  description: string;

  /** Whether this parameter is required */
  required: boolean;

  /** Default value if not provided */
  defaultValue?: unknown;

  /** Allowed values (for enum-like parameters) */
  enum?: string[];
}

// =============================================================================
// Tool Definition Types
// =============================================================================

/**
 * Definition of a tool that the LLM can use
 */
export interface ToolDefinition {
  /** Unique name of the tool (e.g., "get_weather") */
  name: string;

  /** Human-readable description of what the tool does */
  description: string;

  /** Parameters the tool accepts */
  parameters: ToolParameter[];

  /** Category for organizing tools (optional) */
  category?: string;
}

// =============================================================================
// Tool Call Types (LLM requesting to use a tool)
// =============================================================================

/**
 * A request from the LLM to execute a tool
 */
export interface ToolCall {
  /** Name of the tool to execute */
  toolName: string;

  /** Arguments to pass to the tool */
  arguments: Record<string, unknown>;

  /** Unique ID for this tool call (for tracking) */
  callId?: string;
}

// =============================================================================
// Tool Result Types (Result after execution)
// =============================================================================

/**
 * Result of executing a tool
 */
export interface ToolResult {
  /** Name of the tool that was executed */
  toolName: string;

  /** Whether execution was successful */
  success: boolean;

  /** Result data (if successful) */
  result?: Record<string, unknown>;

  /** Error message (if failed) */
  error?: string;

  /** The original call ID (for tracking) */
  callId?: string;
}

// =============================================================================
// Tool Executor Types
// =============================================================================

/**
 * Function type for tool executors
 * Takes arguments, returns a promise with the result
 */
export type ToolExecutor = (
  args: Record<string, unknown>
) => Promise<Record<string, unknown>>;

/**
 * A registered tool with its definition and executor
 */
export interface RegisteredTool {
  /** Tool definition (name, description, parameters) */
  definition: ToolDefinition;

  /** Function that executes the tool */
  executor: ToolExecutor;
}

// =============================================================================
// Tool Calling Options
// =============================================================================

/**
 * Options for tool-enabled generation
 */
export interface ToolCallingOptions {
  /** Available tools for this generation (if not provided, uses registered tools) */
  tools?: ToolDefinition[];

  /** Maximum number of tool calls allowed in one conversation turn */
  maxToolCalls?: number;

  /** Whether to automatically execute tools or return them for manual execution */
  autoExecute?: boolean;

  /** Temperature for generation */
  temperature?: number;

  /** Maximum tokens to generate */
  maxTokens?: number;

  /** System prompt to use (will be merged with tool instructions by default) */
  systemPrompt?: string;

  /**
   * If true, replaces the system prompt entirely instead of appending tool instructions.
   * Use this if your system prompt already includes tool-calling instructions.
   * Default: false (tool instructions are appended to systemPrompt)
   */
  replaceSystemPrompt?: boolean;

  /**
   * If true, keeps tool definitions available after the first tool call.
   * This allows the LLM to make multiple sequential tool calls if needed.
   * Default: false (tool definitions are removed after first call to encourage natural response)
   */
  keepToolsAvailable?: boolean;

  /**
   * Tool calling format to use.
   * - 'default': JSON format with <tool_call> tags (Llama, Qwen, Mistral, etc.)
   * - 'lfm2': Pythonic format for Liquid AI LFM2-Tool models
   * Default: 'default'
   */
  format?: string;
}

// =============================================================================
// Tool Calling Result Types
// =============================================================================

/**
 * Result of a generation that may include tool calls
 */
export interface ToolCallingResult {
  /** The final text response */
  text: string;

  /** Any tool calls the LLM made */
  toolCalls: ToolCall[];

  /** Results of executed tools (if autoExecute was true) */
  toolResults: ToolResult[];

  /** Whether the response is complete or waiting for tool results */
  isComplete: boolean;

  /** Conversation ID for continuing with tool results */
  conversationId?: string;
}

