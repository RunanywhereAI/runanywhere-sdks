/**
 * ConversationManager.ts
 *
 * Service for managing conversation context and message history
 *
 * Provides functionality for:
 * - Managing message history
 * - Context window management
 * - System prompts
 * - Conversation state
 */

import { Message, MessageRole } from '../components/LLM/LLMModels';

/**
 * Configuration for conversation manager
 */
export interface ConversationConfig {
  /** Maximum number of messages to retain in history */
  readonly maxMessages?: number;
  /** Maximum total tokens in context window */
  readonly maxContextTokens?: number;
  /** System prompt to prepend to conversations */
  readonly systemPrompt?: string | null;
}

/**
 * Manages conversation state and history
 */
export class ConversationManager {
  private messages: Message[] = [];
  private systemPrompt: string | null;
  private readonly maxMessages: number;
  private readonly maxContextTokens: number;

  constructor(config: ConversationConfig = {}) {
    this.systemPrompt = config.systemPrompt ?? null;
    this.maxMessages = config.maxMessages ?? 20;
    this.maxContextTokens = config.maxContextTokens ?? 2048;
  }

  /**
   * Add a user message to the conversation
   */
  public addUserMessage(content: string): void {
    this.messages.push({
      role: MessageRole.User,
      content,
    });
    this.trimHistory();
  }

  /**
   * Add an assistant message to the conversation
   */
  public addAssistantMessage(content: string): void {
    this.messages.push({
      role: MessageRole.Assistant,
      content,
    });
    this.trimHistory();
  }

  /**
   * Add a message to the conversation
   */
  public addMessage(message: Message): void {
    this.messages.push(message);
    this.trimHistory();
  }

  /**
   * Get all messages in the conversation
   */
  public getMessages(): readonly Message[] {
    return [...this.messages];
  }

  /**
   * Get the system prompt
   */
  public getSystemPrompt(): string | null {
    return this.systemPrompt;
  }

  /**
   * Set or update the system prompt
   */
  public setSystemPrompt(prompt: string | null): void {
    this.systemPrompt = prompt;
  }

  /**
   * Clear all messages from history
   */
  public clearHistory(): void {
    this.messages = [];
  }

  /**
   * Clear all state including system prompt
   */
  public reset(): void {
    this.messages = [];
    this.systemPrompt = null;
  }

  /**
   * Get the number of messages in history
   */
  public getMessageCount(): number {
    return this.messages.length;
  }

  /**
   * Estimate the total token count of the conversation
   * Uses a rough estimate of 1 token per 4 characters
   */
  public estimateTokenCount(): number {
    let totalChars = 0;

    // Add system prompt if present
    if (this.systemPrompt) {
      totalChars += this.systemPrompt.length;
    }

    // Add all messages
    for (const message of this.messages) {
      totalChars += message.content.length;
      // Add overhead for role labels
      totalChars += 10;
    }

    return Math.ceil(totalChars / 4);
  }

  /**
   * Check if the conversation is within context limits
   */
  public isWithinContextLimit(): boolean {
    return this.estimateTokenCount() <= this.maxContextTokens;
  }

  /**
   * Trim history to stay within limits
   * Removes oldest messages first while preserving conversation flow
   */
  private trimHistory(): void {
    // Trim by message count
    while (this.messages.length > this.maxMessages) {
      this.messages.shift();
    }

    // Trim by token count (rough estimate)
    while (this.estimateTokenCount() > this.maxContextTokens && this.messages.length > 1) {
      this.messages.shift();
    }
  }

  /**
   * Build a formatted prompt from the conversation history
   * Suitable for passing to LLM generation
   */
  public buildPrompt(): string {
    let prompt = '';

    // Add system prompt if present
    if (this.systemPrompt) {
      prompt += `System: ${this.systemPrompt}\n\n`;
    }

    // Add conversation history
    for (const message of this.messages) {
      const roleLabel = message.role === MessageRole.User ? 'User' : 'Assistant';
      prompt += `${roleLabel}: ${message.content}\n\n`;
    }

    // Add assistant prompt to continue
    prompt += 'Assistant:';
    return prompt;
  }

  /**
   * Get conversation statistics
   */
  public getStats(): ConversationStats {
    const userMessages = this.messages.filter((m) => m.role === MessageRole.User).length;
    const assistantMessages = this.messages.filter((m) => m.role === MessageRole.Assistant).length;

    return {
      totalMessages: this.messages.length,
      userMessages,
      assistantMessages,
      estimatedTokens: this.estimateTokenCount(),
      hasSystemPrompt: this.systemPrompt !== null,
    };
  }

  /**
   * Export conversation to JSON
   */
  public toJSON(): ConversationSnapshot {
    return {
      systemPrompt: this.systemPrompt,
      messages: [...this.messages],
      timestamp: new Date(),
    };
  }

  /**
   * Import conversation from JSON
   */
  public fromJSON(snapshot: ConversationSnapshot): void {
    this.systemPrompt = snapshot.systemPrompt;
    this.messages = [...snapshot.messages];
    this.trimHistory();
  }
}

/**
 * Statistics about a conversation
 */
export interface ConversationStats {
  readonly totalMessages: number;
  readonly userMessages: number;
  readonly assistantMessages: number;
  readonly estimatedTokens: number;
  readonly hasSystemPrompt: boolean;
}

/**
 * Snapshot of a conversation for serialization
 */
export interface ConversationSnapshot {
  readonly systemPrompt: string | null;
  readonly messages: Message[];
  readonly timestamp: Date;
}
