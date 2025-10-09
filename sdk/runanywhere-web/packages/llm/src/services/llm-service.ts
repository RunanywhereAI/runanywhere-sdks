import { EventEmitter } from 'eventemitter3';
import { createParser, ParsedEvent, ReconnectInterval } from 'eventsource-parser';
import { Result, logger } from '@runanywhere/core';
import type {
  LLMConfig,
  Message,
  CompletionResult,
  TokenEvent,
  FirstTokenEvent
} from '../types';

export class LLMService extends EventEmitter {
  private config: Required<LLMConfig>;
  private abortController?: AbortController;
  private conversationHistory: Message[] = [];

  constructor(config: LLMConfig = {}) {
    super();
    this.config = {
      apiKey: config.apiKey || '',
      baseUrl: config.baseUrl || 'http://localhost:8080/v1',
      model: config.model || 'gpt-3.5-turbo',
      temperature: config.temperature ?? 0.7,
      maxTokens: config.maxTokens ?? 500,
      topP: config.topP ?? 1,
      frequencyPenalty: config.frequencyPenalty ?? 0,
      presencePenalty: config.presencePenalty ?? 0,
      systemPrompt: config.systemPrompt || 'You are a helpful voice assistant.',
      streamingEnabled: config.streamingEnabled ?? true,
      timeout: config.timeout ?? 30000
    };

    // Add system prompt to conversation
    if (this.config.systemPrompt) {
      this.conversationHistory.push({
        role: 'system',
        content: this.config.systemPrompt,
        timestamp: Date.now()
      });
    }
  }

  async complete(
    prompt: string,
    options: Partial<LLMConfig> = {}
  ): Promise<Result<CompletionResult, Error>> {
    const config = { ...this.config, ...options };
    const startTime = performance.now();
    let firstTokenTime: number | undefined;

    this.abortController = new AbortController();

    // Add user message to history
    const userMessage: Message = {
      role: 'user',
      content: prompt,
      timestamp: Date.now()
    };
    this.conversationHistory.push(userMessage);

    try {
      logger.debug('Starting LLM completion', 'LLM', {
        model: config.model,
        streaming: config.streamingEnabled
      });

      this.emit('completionStart', { prompt });

      // Create abort signal with timeout
      const timeoutId = setTimeout(() => {
        this.abortController?.abort();
      }, config.timeout);

      const response = await fetch(`${config.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(config.apiKey && { 'Authorization': `Bearer ${config.apiKey}` })
        },
        body: JSON.stringify({
          model: config.model,
          messages: this.conversationHistory.slice(-10), // Keep last 10 messages
          temperature: config.temperature,
          max_tokens: config.maxTokens,
          top_p: config.topP,
          frequency_penalty: config.frequencyPenalty,
          presence_penalty: config.presencePenalty,
          stream: config.streamingEnabled
        }),
        signal: this.abortController.signal
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`LLM request failed: ${response.status} ${response.statusText}`);
      }

      let fullText = '';
      let finishReason: CompletionResult['finishReason'] = 'stop';

      if (config.streamingEnabled && response.body) {
        // Handle streaming response
        const reader = response.body.getReader();
        const decoder = new TextDecoder();

        const onParse = (event: ParsedEvent | ReconnectInterval) => {
          if (event.type === 'event') {
            if (event.data === '[DONE]') {
              return;
            }

            try {
              const data = JSON.parse(event.data);

              if (data.choices?.[0]?.delta?.content) {
                const token = data.choices[0].delta.content;
                fullText += token;

                if (!firstTokenTime) {
                  firstTokenTime = performance.now();
                  const firstTokenEvent: FirstTokenEvent = {
                    token,
                    latency: firstTokenTime - startTime
                  };
                  this.emit('firstToken', firstTokenEvent);
                }

                const tokenEvent: TokenEvent = {
                  token,
                  position: fullText.length
                };
                this.emit('token', tokenEvent);
              }

              if (data.choices?.[0]?.finish_reason) {
                finishReason = data.choices[0].finish_reason;
              }
            } catch (e) {
              logger.warn('Failed to parse SSE event', 'LLM', { error: e });
            }
          }
        };

        const parser = createParser(onParse);

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          const chunk = decoder.decode(value, { stream: true });
          parser.feed(chunk);
        }
      } else {
        // Handle non-streaming response
        const data = await response.json();
        fullText = data.choices?.[0]?.message?.content || '';
        finishReason = data.choices?.[0]?.finish_reason || 'stop';
        firstTokenTime = performance.now();
      }

      const totalTime = performance.now() - startTime;

      // Add assistant message to history
      this.conversationHistory.push({
        role: 'assistant',
        content: fullText,
        timestamp: Date.now()
      });

      const result: CompletionResult = {
        text: fullText,
        finishReason,
        latency: {
          firstTokenMs: firstTokenTime ? firstTokenTime - startTime : totalTime,
          totalMs: totalTime
        }
      };

      logger.info('LLM completion finished', 'LLM', {
        tokens: fullText.length,
        firstTokenMs: result.latency?.firstTokenMs,
        totalMs: result.latency?.totalMs
      });

      this.emit('completionComplete', result);
      return Result.ok(result);

    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        logger.info('LLM completion cancelled', 'LLM');
        return Result.err(new Error('Completion cancelled'));
      }

      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`LLM completion failed: ${err.message}`, 'LLM');
      this.emit('completionError', err);

      // Remove failed user message from history
      this.conversationHistory.pop();

      return Result.err(err);
    } finally {
      this.abortController = undefined;
    }
  }

  cancel(): void {
    if (this.abortController) {
      this.abortController.abort();
      this.abortController = undefined;
    }
  }

  clearHistory(): void {
    this.conversationHistory = this.conversationHistory.filter(
      msg => msg.role === 'system'
    );
  }

  setSystemPrompt(prompt: string): void {
    this.config.systemPrompt = prompt;

    // Update or add system message
    const systemIndex = this.conversationHistory.findIndex(
      msg => msg.role === 'system'
    );

    const systemMessage: Message = {
      role: 'system',
      content: prompt,
      timestamp: Date.now()
    };

    if (systemIndex >= 0) {
      this.conversationHistory[systemIndex] = systemMessage;
    } else {
      this.conversationHistory.unshift(systemMessage);
    }
  }

  getHistory(): Message[] {
    return [...this.conversationHistory];
  }

  isHealthy(): boolean {
    return true; // Could add API health check here
  }

  destroy(): void {
    this.cancel();
    this.clearHistory();
    this.removeAllListeners();
  }
}
