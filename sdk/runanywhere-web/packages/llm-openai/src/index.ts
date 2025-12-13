/**
 * OpenAI LLM Adapter Implementation
 * Provides access to OpenAI GPT models via API
 */

import {
  BaseAdapter,
  type LLMAdapter,
  type LLMConfig,
  type LLMEvents,
  type CompletionOptions,
  type CompletionResult,
  type TokenResult,
  type Message,
  type LLMMetrics,
  type AdapterType,
  Result,
  logger,
  ServiceRegistry
} from '@runanywhere/core';

export class OpenAILLMAdapter extends BaseAdapter<LLMEvents> implements LLMAdapter {
  readonly id = 'openai';
  readonly name = 'OpenAI GPT';
  readonly version = '1.0.0';
  readonly supportedModels = [
    'gpt-3.5-turbo',
    'gpt-3.5-turbo-16k',
    'gpt-4',
    'gpt-4-turbo',
    'gpt-4o',
    'gpt-4o-mini',
  ];

  private config?: LLMConfig;
  private apiKey?: string;
  private systemPrompt?: string;
  private history: Message[] = [];
  private metrics: LLMMetrics = {
    totalTokens: 0,
    totalCompletions: 0,
    avgResponseTime: 0,
    errorRate: 0,
    averageLatency: 0,
    totalCost: 0,
  };
  private isInitialized = false;

  async initialize(config?: LLMConfig): Promise<Result<void, Error>> {
    try {
      if (!config?.apiKey) {
        return Result.err(new Error('OpenAI API key is required'));
      }

      this.config = config;
      this.apiKey = config.apiKey;
      this.systemPrompt = config.systemPrompt;
      this.isInitialized = true;

      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  async complete(
    prompt: string,
    options?: CompletionOptions
  ): Promise<Result<CompletionResult, Error>> {
    if (!this.isInitialized || !this.apiKey) {
      return Result.err(new Error('Adapter not initialized'));
    }

    try {
      const startTime = Date.now();

      const messages = this.buildMessages(prompt, options);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: options?.model || this.config?.defaultModel || 'gpt-3.5-turbo',
          messages,
          temperature: options?.temperature ?? 0.7,
          max_tokens: options?.maxTokens ?? 1000,
          top_p: options?.topP ?? 1,
          frequency_penalty: options?.frequencyPenalty ?? 0,
          presence_penalty: options?.presencePenalty ?? 0,
          stream: false,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error?.message || 'OpenAI API error');
      }

      const data = await response.json();
      const completion = data.choices[0];
      const latency = Date.now() - startTime;

      // Update metrics
      this.metrics.totalCompletions++;
      this.metrics.totalTokens += data.usage?.total_tokens || 0;
      this.metrics.avgResponseTime =
        (this.metrics.avgResponseTime * (this.metrics.totalCompletions - 1) + latency) /
        this.metrics.totalCompletions;
      if (this.metrics.averageLatency !== undefined) {
        this.metrics.averageLatency =
          (this.metrics.averageLatency * (this.metrics.totalCompletions - 1) + latency) /
          this.metrics.totalCompletions;
      }
      if (this.metrics.totalCost !== undefined) {
        this.metrics.totalCost += this.calculateCost(
          data.usage,
          options?.model || this.config?.defaultModel || 'gpt-3.5-turbo'
        );
      }
      // Update history if tracking conversation
      if (options?.saveToHistory !== false) {
        this.history.push(
          { role: 'user', content: prompt },
          { role: 'assistant', content: completion.message.content }
        );
      }

      const result: CompletionResult = {
        text: completion.message.content,
        finishReason: completion.finish_reason,
        usage: {
          promptTokens: data.usage?.prompt_tokens || 0,
          completionTokens: data.usage?.completion_tokens || 0,
          totalTokens: data.usage?.total_tokens || 0,
        },
        latency,
      };

      return Result.ok(result);
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  async *completeStream(
    prompt: string,
    options?: CompletionOptions
  ): AsyncGenerator<TokenResult> {
    if (!this.isInitialized || !this.apiKey) {
      throw new Error('Adapter not initialized');
    }

    const startTime = Date.now();
    const messages = this.buildMessages(prompt, options);

    try {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: options?.model || this.config?.defaultModel || 'gpt-3.5-turbo',
          messages,
          temperature: options?.temperature ?? 0.7,
          max_tokens: options?.maxTokens ?? 1000,
          stream: true,
        }),
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error?.message || 'OpenAI API error');
      }

      const reader = response.body?.getReader();
      if (!reader) {
        throw new Error('Failed to get response stream');
      }

      const decoder = new TextDecoder();
      let buffer = '';
      let fullText = '';
      let tokenCount = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6);
            if (data === '[DONE]') {
              // Update history if needed
              if (options?.saveToHistory !== false && fullText) {
                this.history.push(
                  { role: 'user', content: prompt },
                  { role: 'assistant', content: fullText }
                );
              }
              return;
            }

            try {
              const json = JSON.parse(data);
              const delta = json.choices[0]?.delta;

              if (delta?.content) {
                tokenCount++;
                fullText += delta.content;

                yield {
                  token: delta.content,
                  isComplete: false,
                  tokenIndex: tokenCount,
                  timestamp: Date.now() - startTime,
                };
              }
            } catch (e) {
              // Skip invalid JSON
            }
          }
        }
      }
    } catch (error) {
      this.emit('error', error as Error);
      throw error;
    }
  }

  private buildMessages(prompt: string, options?: CompletionOptions): any[] {
    const messages: any[] = [];

    // Add system prompt if configured
    if (this.systemPrompt) {
      messages.push({ role: 'system', content: this.systemPrompt });
    }

    // Add conversation history if using it
    if (options?.useHistory && this.history.length > 0) {
      // Limit history to last N messages to avoid token limits
      const historyLimit = options.historyLimit || 10;
      const recentHistory = this.history.slice(-historyLimit);
      messages.push(...recentHistory);
    }

    // Add current prompt
    messages.push({ role: 'user', content: prompt });

    return messages;
  }

  private calculateCost(usage: any, model: string): number {
    // Rough cost estimates per 1K tokens (in USD)
    const costs: Record<string, { input: number; output: number }> = {
      'gpt-3.5-turbo': { input: 0.0015, output: 0.002 },
      'gpt-3.5-turbo-16k': { input: 0.003, output: 0.004 },
      'gpt-4': { input: 0.03, output: 0.06 },
      'gpt-4-turbo': { input: 0.01, output: 0.03 },
      'gpt-4o': { input: 0.005, output: 0.015 },
      'gpt-4o-mini': { input: 0.00015, output: 0.0006 },
    };

    const modelCost = costs[model] || costs['gpt-3.5-turbo'];
    const inputCost = (usage?.prompt_tokens || 0) / 1000 * modelCost.input;
    const outputCost = (usage?.completion_tokens || 0) / 1000 * modelCost.output;

    return inputCost + outputCost;
  }

  setSystemPrompt(prompt: string): void {
    this.systemPrompt = prompt;
  }

  clearHistory(): void {
    this.history = [];
  }

  getHistory(): Message[] {
    return [...this.history];
  }

  addMessage(message: Message): void {
    this.history.push(message);
  }

  destroy(): void {
    this.config = undefined;
    this.apiKey = undefined;
    this.systemPrompt = undefined;
    this.history = [];
    this.isInitialized = false;
    this.removeAllListeners();
  }

  isHealthy(): boolean {
    return this.isInitialized && !!this.apiKey;
  }

  getMetrics(): LLMMetrics {
    return { ...this.metrics };
  }
}

// Auto-register with ServiceRegistry if available
if (typeof window !== 'undefined') {
  try {
    const registry = ServiceRegistry.getInstance();
    registry.register('LLM' as AdapterType, 'openai', OpenAILLMAdapter as any);
    logger.info('OpenAI LLM adapter auto-registered', 'OpenAILLMAdapter');
  } catch (error) {
    // ServiceRegistry not available, skip auto-registration
    logger.debug('ServiceRegistry not available for auto-registration', 'OpenAILLMAdapter');
  }
}

// Named exports
export { OpenAILLMAdapter as default };
export const adapter = OpenAILLMAdapter;
