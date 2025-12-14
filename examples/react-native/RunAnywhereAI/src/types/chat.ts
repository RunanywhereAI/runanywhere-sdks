/**
 * Chat Types - Matching iOS Message models
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Chat/Models/
 */

/**
 * Message role in conversation
 */
export enum MessageRole {
  User = 'user',
  Assistant = 'assistant',
  System = 'system',
}

/**
 * Message analytics data
 */
export interface MessageAnalytics {
  /** Time to first token in milliseconds */
  timeToFirstToken?: number;

  /** Total generation time in milliseconds */
  totalGenerationTime: number;

  /** Time spent on thinking/reasoning */
  thinkingTime?: number;

  /** Time for actual response */
  responseTime?: number;

  /** Number of input tokens */
  inputTokens: number;

  /** Number of output tokens */
  outputTokens: number;

  /** Number of thinking tokens */
  thinkingTokens?: number;

  /** Number of response tokens */
  responseTokens?: number;

  /** Average tokens per second */
  averageTokensPerSecond?: number;

  /** History of tokens per second over time */
  tokensPerSecondHistory?: number[];

  /** Whether generation completed successfully */
  completionStatus: 'completed' | 'interrupted' | 'error';

  /** Whether thinking mode was used */
  wasThinkingMode: boolean;

  /** Whether generation was interrupted */
  wasInterrupted: boolean;

  /** Number of retry attempts */
  retryCount: number;

  /** Generation parameters used */
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
