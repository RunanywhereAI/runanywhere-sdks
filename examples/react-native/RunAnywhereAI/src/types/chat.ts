/**
 * Chat Types - Matching iOS Message models
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Models/
 */

import type { PerformanceMetrics } from '@runanywhere/proto-ts/llm_options';

/**
 * Message role in conversation
 */
export enum MessageRole {
  User = 'user',
  Assistant = 'assistant',
  System = 'system',
}

/**
 * Message analytics data.
 *
 * Timing and token counts live on the canonical proto `PerformanceMetrics`
 * (see `@runanywhere/proto-ts/llm_options`) — this DTO nests that proto so
 * consumers read `analytics.performance.latencyMs / promptTokens /
 * completionTokens / throughputTokensPerSec` instead of duplicating fields.
 * UI-only flags (thinking mode, completion state, retries) remain inline.
 */
export interface MessageAnalytics {
  /** Canonical proto performance snapshot. */
  performance: PerformanceMetrics;

  /** Time to first token in milliseconds (UI-only; not on proto yet). */
  timeToFirstToken?: number;

  /** Time spent on thinking/reasoning (UI-only). */
  thinkingTime?: number;

  /** Time for actual response (UI-only). */
  responseTime?: number;

  /** Number of thinking tokens (UI-only). */
  thinkingTokens?: number;

  /** Number of response tokens (UI-only). */
  responseTokens?: number;

  /** History of tokens per second over time (UI-only). */
  tokensPerSecondHistory?: number[];

  /** Whether generation completed successfully (UI-only). */
  completionStatus: 'completed' | 'interrupted' | 'error';

  /** Whether thinking mode was used (UI-only). */
  wasThinkingMode: boolean;

  /** Whether generation was interrupted (UI-only). */
  wasInterrupted: boolean;

  /** Number of retry attempts (UI-only). */
  retryCount: number;

  /** Generation parameters used (UI-only). */
  generationParameters?: {
    temperature: number;
    maxTokens: number;
    topP?: number;
    topK?: number;
  };
}

/**
 * Model info attached to a message
 */
export interface MessageModelInfo {
  /** Model ID */
  modelId: string;

  /** Model display name */
  modelName: string;

  /** Framework used */
  framework: string;

  /** Framework display name */
  frameworkDisplayName: string;
}

/**
 * Tool call information attached to a message
 * Matches iOS ToolCallInfo
 */
export interface ToolCallInfo {
  /** Name of the tool that was called */
  toolName: string;

  /** Arguments passed to the tool (JSON string) */
  arguments: string;

  /** Result from the tool (JSON string, if successful) */
  result?: string;

  /** Whether the tool call was successful */
  success: boolean;

  /** Error message (if failed) */
  error?: string;
}

/**
 * Chat message
 */
export interface Message {
  /** Unique identifier */
  id: string;

  /** Message role (user, assistant, system) */
  role: MessageRole;

  /** Message content */
  content: string;

  /** Thinking/reasoning content (for models with reasoning) */
  thinkingContent?: string;

  /** Timestamp */
  timestamp: Date;

  /** Analytics data */
  analytics?: MessageAnalytics;

  /** Model info */
  modelInfo?: MessageModelInfo;

  /** Tool call info (for messages that used tools) */
  toolCallInfo?: ToolCallInfo;

  /** Whether the message is still streaming */
  isStreaming?: boolean;
}

/**
 * Conversation data
 */
export interface Conversation {
  /** Unique identifier */
  id: string;

  /** Conversation title */
  title: string;

  /** Creation timestamp */
  createdAt: Date;

  /** Last update timestamp */
  updatedAt: Date;

  /** Messages in the conversation */
  messages: Message[];

  /** Model name used */
  modelName?: string;

  /** Framework name used */
  frameworkName?: string;
}

/**
 * Conversation summary for list view
 */
export interface ConversationSummary {
  id: string;
  title: string;
  lastMessage: string;
  messageCount: number;
  updatedAt: Date;
}

/**
 * Chat performance summary
 */
export interface ChatPerformanceSummary {
  totalMessages: number;
  averageResponseTime: number;
  averageTokensPerSecond: number;
  totalTokensGenerated: number;
  thinkingModeUsed: boolean;
}
