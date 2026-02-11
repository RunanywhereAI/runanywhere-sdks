/**
 * OpenAICompatibleProvider.ts
 *
 * Built-in cloud provider for OpenAI-compatible APIs.
 * Works with OpenAI, Groq, Together, Ollama, vLLM, etc.
 *
 * Uses the fetch API with SSE streaming parsing.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/Cloud/OpenAICompatibleProvider.swift
 */

import type { CloudProvider } from './CloudProvider';
import type { CloudGenerationOptions, CloudGenerationResult } from './CloudTypes';

// ============================================================================
// Configuration
// ============================================================================

/** Configuration options for creating an OpenAI-compatible provider */
export interface OpenAICompatibleProviderConfig {
  /** Unique ID (default: auto-generated from base URL) */
  providerId?: string;

  /** Human-readable name */
  displayName?: string;

  /** API key (undefined for local providers like Ollama) */
  apiKey?: string;

  /** Default model to use */
  model: string;

  /** API base URL (default: OpenAI) */
  baseURL?: string;

  /** Extra headers to send with every request */
  additionalHeaders?: Record<string, string>;
}

// ============================================================================
// OpenAI API Response Types (internal)
// ============================================================================

interface ChatCompletionResponse {
  choices: Array<{
    message: { content?: string };
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
  };
}

interface ChatCompletionChunk {
  choices: Array<{
    delta: { content?: string };
  }>;
}

// ============================================================================
// Provider Implementation
// ============================================================================

const DEFAULT_BASE_URL = 'https://api.openai.com/v1';

/**
 * Cloud provider for any OpenAI-compatible chat completions API.
 *
 * Supports both streaming (SSE) and non-streaming responses.
 *
 * @example
 * ```typescript
 * // OpenAI
 * const openai = new OpenAICompatibleProvider({ apiKey: 'sk-...', model: 'gpt-4o-mini' });
 *
 * // Groq
 * const groq = new OpenAICompatibleProvider({
 *   apiKey: 'gsk_...',
 *   model: 'llama-3.1-8b-instant',
 *   baseURL: 'https://api.groq.com/openai/v1',
 * });
 *
 * // Local Ollama
 * const ollama = new OpenAICompatibleProvider({
 *   model: 'llama3.2',
 *   baseURL: 'http://localhost:11434/v1',
 * });
 * ```
 */
export class OpenAICompatibleProvider implements CloudProvider {
  // CloudProvider
  public readonly providerId: string;
  public readonly displayName: string;

  // Configuration
  private readonly apiKey?: string;
  private readonly model: string;
  private readonly baseURL: string;
  private readonly additionalHeaders: Record<string, string>;

  constructor(config: OpenAICompatibleProviderConfig) {
    this.apiKey = config.apiKey;
    this.model = config.model;
    this.baseURL = config.baseURL ?? DEFAULT_BASE_URL;
    this.additionalHeaders = config.additionalHeaders ?? {};

    // Derive host from URL for default IDs
    const host = extractHost(this.baseURL);
    this.providerId = config.providerId ?? `openai-compat-${host}`;
    this.displayName = config.displayName ?? `OpenAI Compatible (${host})`;
  }

  // ============================================================================
  // CloudProvider Implementation
  // ============================================================================

  async generate(
    prompt: string,
    options: CloudGenerationOptions,
  ): Promise<CloudGenerationResult> {
    const startTime = Date.now();

    const messages = this.buildMessages(prompt, options);
    const requestBody = this.buildRequestBody(messages, options, false);

    const response = await this.performRequest(requestBody);
    const data = (await response.json()) as ChatCompletionResponse;

    const latencyMs = Date.now() - startTime;
    const text = data.choices[0]?.message.content ?? '';

    return {
      text,
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
      latencyMs,
      providerId: this.providerId,
      model: options.model,
      estimatedCostUSD: undefined,
    };
  }

  async *generateStream(
    prompt: string,
    options: CloudGenerationOptions,
  ): AsyncGenerator<string> {
    const messages = this.buildMessages(prompt, options);
    const requestBody = this.buildRequestBody(messages, options, true);

    const response = await this.performRequest(requestBody);

    if (!response.body) {
      throw new CloudProviderError('Response body is null - streaming not supported');
    }

    // Parse SSE stream using ReadableStream
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        // Process complete SSE lines
        const lines = buffer.split('\n');
        // Keep the last potentially incomplete line in the buffer
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith('data: ')) continue;

          const data = trimmed.slice(6);
          if (data === '[DONE]') return;

          try {
            const chunk = JSON.parse(data) as ChatCompletionChunk;
            const content = chunk.choices[0]?.delta.content;
            if (content) {
              yield content;
            }
          } catch {
            // Skip malformed JSON chunks
          }
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  async isAvailable(): Promise<boolean> {
    try {
      const url = `${this.baseURL}/models`;
      const headers: Record<string, string> = {};
      if (this.apiKey) {
        headers['Authorization'] = `Bearer ${this.apiKey}`;
      }

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);

      const response = await fetch(url, {
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      return response.status === 200;
    } catch {
      return false;
    }
  }

  // ============================================================================
  // Internal Helpers
  // ============================================================================

  private buildMessages(
    prompt: string,
    options: CloudGenerationOptions,
  ): Array<{ role: string; content: string }> {
    if (options.messages && options.messages.length > 0) {
      return options.messages;
    }

    const msgs: Array<{ role: string; content: string }> = [];
    if (options.systemPrompt) {
      msgs.push({ role: 'system', content: options.systemPrompt });
    }
    msgs.push({ role: 'user', content: prompt });
    return msgs;
  }

  private buildRequestBody(
    messages: Array<{ role: string; content: string }>,
    options: CloudGenerationOptions,
    stream: boolean,
  ): Record<string, unknown> {
    return {
      model: options.model,
      messages,
      max_tokens: options.maxTokens ?? 1024,
      temperature: options.temperature ?? 0.7,
      stream,
    };
  }

  private async performRequest(body: Record<string, unknown>): Promise<Response> {
    const url = `${this.baseURL}/chat/completions`;

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...this.additionalHeaders,
    };

    if (this.apiKey) {
      headers['Authorization'] = `Bearer ${this.apiKey}`;
    }

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw new CloudProviderError(
        `Cloud API returned HTTP ${response.status}`,
        response.status,
      );
    }

    return response;
  }
}

// ============================================================================
// Cloud Provider Error
// ============================================================================

/**
 * Error from cloud provider operations.
 * Mirrors Swift CloudProviderError enum.
 */
export class CloudProviderError extends Error {
  public readonly statusCode?: number;
  public readonly errorType: CloudProviderErrorType;

  constructor(message: string, statusCode?: number, errorType: CloudProviderErrorType = CloudProviderErrorType.General) {
    super(message);
    this.name = 'CloudProviderError';
    this.statusCode = statusCode;
    this.errorType = errorType;
  }

  /** Cloud budget exceeded */
  static budgetExceeded(currentUSD: number, capUSD: number): CloudProviderError {
    return new CloudProviderError(
      `Cloud budget exceeded: $${currentUSD.toFixed(4)} / $${capUSD.toFixed(4)} cap`,
      undefined,
      CloudProviderErrorType.BudgetExceeded,
    );
  }

  /** On-device latency timeout */
  static latencyTimeout(maxMs: number, actualMs: number): CloudProviderError {
    return new CloudProviderError(
      `On-device latency timeout: ${actualMs.toFixed(0)}ms exceeded ${maxMs}ms limit`,
      undefined,
      CloudProviderErrorType.LatencyTimeout,
    );
  }

  /** No cloud provider registered */
  static noProviderRegistered(): CloudProviderError {
    return new CloudProviderError(
      'No cloud provider registered',
      undefined,
      CloudProviderErrorType.NoProviderRegistered,
    );
  }
}

/**
 * Cloud provider error types matching Swift CloudProviderError cases
 */
export enum CloudProviderErrorType {
  General = 'general',
  InvalidURL = 'invalid_url',
  HttpError = 'http_error',
  NoProviderRegistered = 'no_provider_registered',
  ProviderNotFound = 'provider_not_found',
  ProviderUnavailable = 'provider_unavailable',
  DecodingError = 'decoding_error',
  BudgetExceeded = 'budget_exceeded',
  LatencyTimeout = 'latency_timeout',
}

// ============================================================================
// Utility
// ============================================================================

function extractHost(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return 'local';
  }
}
