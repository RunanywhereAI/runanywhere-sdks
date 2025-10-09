// Web Worker for LLM processing
import type { Result } from '@runanywhere/core';

// Worker message types
export interface LLMWorkerMessage {
  id: string;
  type: string;
  data?: any;
}

export interface LLMInitializeMessage extends LLMWorkerMessage {
  type: 'initialize';
  data: {
    apiKey?: string;
    baseUrl?: string;
    modelName?: string;
    systemPrompt?: string;
    maxTokens?: number;
    temperature?: number;
  };
}

export interface LLMProcessMessage extends LLMWorkerMessage {
  type: 'process';
  data: {
    prompt: string;
    context?: Array<{ role: 'user' | 'assistant'; content: string }>;
    stream?: boolean;
  };
}

export interface LLMDestroyMessage extends LLMWorkerMessage {
  type: 'destroy';
}

// Response types
export interface LLMWorkerResponse {
  id: string;
  type: string;
  success: boolean;
  data?: any;
  error?: string;
}

export interface LLMInitializedResponse extends LLMWorkerResponse {
  type: 'initialized';
}

export interface LLMTextResponse extends LLMWorkerResponse {
  type: 'textGenerated';
  data: {
    text: string;
    isComplete: boolean;
    metadata?: {
      tokensUsed: number;
      latency: number;
      model: string;
    };
  };
}

export interface LLMStreamResponse extends LLMWorkerResponse {
  type: 'textStream';
  data: {
    delta: string;
    text: string;
    isComplete: boolean;
    metadata?: {
      tokensUsed: number;
      model: string;
    };
  };
}

export interface LLMErrorResponse extends LLMWorkerResponse {
  type: 'error';
  success: false;
  error: string;
}

interface LLMConfig {
  apiKey?: string;
  baseUrl?: string;
  modelName: string;
  systemPrompt?: string;
  maxTokens: number;
  temperature: number;
}

interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

class LLMProcessorWorker {
  private config: LLMConfig | null = null;
  private isInitialized = false;
  private abortController: AbortController | null = null;

  constructor() {
    self.addEventListener('message', this.handleMessage.bind(this));
  }

  private async handleMessage(event: MessageEvent<LLMWorkerMessage>): Promise<void> {
    const message = event.data;

    try {
      switch (message.type) {
        case 'initialize':
          await this.initialize(message as LLMInitializeMessage);
          break;
        case 'process':
          await this.processLLM(message as LLMProcessMessage);
          break;
        case 'destroy':
          await this.destroy();
          break;
        default:
          this.sendError(message.id, `Unknown message type: ${message.type}`);
      }
    } catch (error) {
      this.sendError(message.id, `Error processing message: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async initialize(message: LLMInitializeMessage): Promise<void> {
    try {
      const {
        apiKey,
        baseUrl = 'https://api.openai.com/v1',
        modelName = 'gpt-3.5-turbo',
        systemPrompt = 'You are a helpful AI assistant.',
        maxTokens = 1000,
        temperature = 0.7
      } = message.data;

      this.config = {
        ...(apiKey && { apiKey }),
        baseUrl,
        modelName,
        systemPrompt,
        maxTokens,
        temperature
      };

      // Validate configuration
      if (!apiKey && baseUrl.includes('openai.com')) {
        throw new Error('API key is required for OpenAI models');
      }

      this.isInitialized = true;

      this.sendResponse<LLMInitializedResponse>({
        id: message.id,
        type: 'initialized',
        success: true
      });

    } catch (error) {
      this.sendError(message.id, `LLM initialization failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async processLLM(message: LLMProcessMessage): Promise<void> {
    if (!this.isInitialized || !this.config) {
      this.sendError(message.id, 'LLM worker not initialized');
      return;
    }

    try {
      const { prompt, context = [], stream = false } = message.data;
      const startTime = performance.now();

      // Cancel any ongoing request
      if (this.abortController) {
        this.abortController.abort();
      }
      this.abortController = new AbortController();

      // Build messages array
      const messages: ChatMessage[] = [];

      // Add system prompt if configured
      if (this.config.systemPrompt) {
        messages.push({
          role: 'system',
          content: this.config.systemPrompt
        });
      }

      // Add conversation context
      context.forEach(msg => {
        messages.push({
          role: msg.role,
          content: msg.content
        });
      });

      // Add current prompt
      messages.push({
        role: 'user',
        content: prompt
      });

      if (stream) {
        await this.processStreamingLLM(message.id, messages, startTime);
      } else {
        await this.processSingleLLM(message.id, messages, startTime);
      }

    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        return; // Request was cancelled
      }
      this.sendError(message.id, `LLM processing failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async processSingleLLM(
    messageId: string,
    messages: ChatMessage[],
    startTime: number
  ): Promise<void> {
    const response = await this.makeApiRequest(messages, false);
    const endTime = performance.now();

    if (!response.ok) {
      const errorData = await response.text();
      throw new Error(`API request failed: ${response.status} ${errorData}`);
    }

    const data = await response.json();
    const text = data.choices?.[0]?.message?.content || '';
    const tokensUsed = data.usage?.total_tokens || 0;

    this.sendResponse<LLMTextResponse>({
      id: messageId,
      type: 'textGenerated',
      success: true,
      data: {
        text,
        isComplete: true,
        metadata: {
          tokensUsed,
          latency: endTime - startTime,
          model: this.config!.modelName
        }
      }
    });
  }

  private async processStreamingLLM(
    messageId: string,
    messages: ChatMessage[],
    startTime: number
  ): Promise<void> {
    const response = await this.makeApiRequest(messages, true);

    if (!response.ok) {
      const errorData = await response.text();
      throw new Error(`API request failed: ${response.status} ${errorData}`);
    }

    if (!response.body) {
      throw new Error('Response body is null');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let fullText = '';
    let tokensUsed = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();

        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter(line => line.trim() && line.startsWith('data: '));

        for (const line of lines) {
          const data = line.replace('data: ', '').trim();

          if (data === '[DONE]') {
            this.sendResponse<LLMStreamResponse>({
              id: messageId,
              type: 'textStream',
              success: true,
              data: {
                delta: '',
                text: fullText,
                isComplete: true,
                metadata: {
                  tokensUsed,
                  model: this.config!.modelName
                }
              }
            });
            return;
          }

          try {
            const parsedData = JSON.parse(data);
            const delta = parsedData.choices?.[0]?.delta?.content || '';

            if (delta) {
              fullText += delta;
              tokensUsed += 1; // Rough token estimation

              this.sendResponse<LLMStreamResponse>({
                id: messageId,
                type: 'textStream',
                success: true,
                data: {
                  delta,
                  text: fullText,
                  isComplete: false
                }
              });
            }
          } catch (parseError) {
            console.warn('[LLMWorker] Failed to parse streaming data:', parseError);
          }
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  private async makeApiRequest(messages: ChatMessage[], stream: boolean): Promise<Response> {
    if (!this.config) {
      throw new Error('LLM config not initialized');
    }

    const requestBody = {
      model: this.config.modelName,
      messages,
      max_tokens: this.config.maxTokens,
      temperature: this.config.temperature,
      stream
    };

    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };

    // Add authentication if API key is provided
    if (this.config.apiKey) {
      headers['Authorization'] = `Bearer ${this.config.apiKey}`;
    }

    const fetchOptions: RequestInit = {
      method: 'POST',
      headers,
      body: JSON.stringify(requestBody)
    };

    if (this.abortController?.signal) {
      fetchOptions.signal = this.abortController.signal;
    }

    return fetch(`${this.config.baseUrl}/chat/completions`, fetchOptions);
  }

  private async destroy(): Promise<void> {
    try {
      // Cancel any ongoing requests
      if (this.abortController) {
        this.abortController.abort();
        this.abortController = null;
      }

      // Clear configuration
      this.config = null;
      this.isInitialized = false;

      this.sendResponse<LLMWorkerResponse>({
        id: 'destroy',
        type: 'destroyed',
        success: true
      });

    } catch (error) {
      this.sendError('destroy', `LLM cleanup failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private sendResponse<T extends LLMWorkerResponse>(response: T): void {
    self.postMessage(response);
  }

  private sendError(id: string, errorMessage: string): void {
    this.sendResponse<LLMErrorResponse>({
      id,
      type: 'error',
      success: false,
      error: errorMessage
    });
  }
}

// Initialize the worker
new LLMProcessorWorker();

// Types are already exported above, no need to re-export
