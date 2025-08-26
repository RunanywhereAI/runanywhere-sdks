'use client';

import { useState, useCallback, useRef, useEffect } from 'react';

// Define our own interfaces since we can't rely on the SDK packages in the web example
interface LLMConfig {
  apiKey?: string;
  defaultModel?: string;
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
}

interface CompletionOptions {
  model?: string;
  temperature?: number;
  maxTokens?: number;
  useHistory?: boolean;
  saveToHistory?: boolean;
}

interface CompletionResult {
  text: string;
  finishReason?: string;
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
  latency: number;
}

interface TokenResult {
  token: string;
  isComplete: boolean;
  tokenIndex?: number;
  timestamp?: number;
}

interface LLMMetrics {
  totalCompletions: number;
  totalTokens: number;
  avgResponseTime: number;
  errorRate: number;
  averageLatency?: number;
  totalCost?: number;
}

interface Message {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

interface LLMState {
  isInitialized: boolean;
  isProcessing: boolean;
  response: string;
  error: string | null;
  conversationHistory: Array<{ role: string; content: string }>;
  lastCompletionResult: any | null;
}

/**
 * Hook that uses the @runanywhere/llm-openai package
 * This is an example of how to consume the SDK adapter in a React app
 */
export function useLLMAdapter(config?: Partial<LLMConfig>) {
  const [state, setState] = useState<LLMState>({
    isInitialized: false,
    isProcessing: false,
    response: '',
    error: null,
    conversationHistory: [],
    lastCompletionResult: null,
  });

  const adapterRef = useRef<any | null>(null);

  // Initialize LLM
  const initialize = useCallback(async (apiKey: string) => {
    if (state.isInitialized) return;

    try {
      console.log('[LLM Adapter] Initializing...');

      // For now, we'll use direct OpenAI API calls instead of the SDK adapter
      // This avoids complex SDK import issues in the web example
      const adapter = {
        initialize: async (config: LLMConfig) => ({ success: true }),
        complete: async (prompt: string, options?: CompletionOptions) => {
          const messages = [
            { role: 'system', content: config?.systemPrompt || 'You are a helpful assistant.' },
            ...state.conversationHistory,
            { role: 'user', content: prompt }
          ];

          const startTime = Date.now();
          const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${apiKey}`
            },
            body: JSON.stringify({
              model: options?.model || config?.defaultModel || 'gpt-4o-mini',
              messages,
              temperature: options?.temperature ?? config?.temperature ?? 0.7,
              max_tokens: options?.maxTokens ?? config?.maxTokens ?? 1000
            })
          });

          if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error?.message || 'OpenAI API error');
          }

          const data = await response.json();
          const completion = data.choices[0].message.content;
          const latency = Date.now() - startTime;

          // Update history
          if (options?.saveToHistory !== false) {
            adapter._history = [
              ...adapter._history,
              { role: 'user', content: prompt },
              { role: 'assistant', content: completion }
            ];
          }

          return {
            success: true,
            value: {
              text: completion,
              finishReason: data.choices[0].finish_reason,
              usage: data.usage,
              latency
            } as CompletionResult
          };
        },
        completeStream: async function* (prompt: string, options?: CompletionOptions) {
          const messages = [
            { role: 'system', content: config?.systemPrompt || 'You are a helpful assistant.' },
            ...state.conversationHistory,
            { role: 'user', content: prompt }
          ];

          const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${apiKey}`
            },
            body: JSON.stringify({
              model: options?.model || config?.defaultModel || 'gpt-4o-mini',
              messages,
              temperature: options?.temperature ?? config?.temperature ?? 0.7,
              max_tokens: options?.maxTokens ?? config?.maxTokens ?? 1000,
              stream: true
            })
          });

          if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error?.message || 'OpenAI API error');
          }

          const reader = response.body?.getReader();
          if (!reader) throw new Error('Failed to get response stream');

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
                  if (options?.saveToHistory !== false && fullText) {
                    adapter._history = [
                      ...adapter._history,
                      { role: 'user', content: prompt },
                      { role: 'assistant', content: fullText }
                    ];
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
                      timestamp: Date.now()
                    } as TokenResult;
                  }
                } catch (e) {
                  // Skip invalid JSON
                }
              }
            }
          }
        },
        setSystemPrompt: (prompt: string) => {
          if (config) {
            config.systemPrompt = prompt;
          }
        },
        clearHistory: () => {
          adapter._history = [];
        },
        getHistory: () => adapter._history || [],
        getMetrics: () => ({
          totalCompletions: 0,
          totalTokens: 0,
          avgResponseTime: 0,
          errorRate: 0
        } as LLMMetrics),
        isHealthy: () => true,
        destroy: () => {},
        on: () => {},
        _history: [] as Message[]
      };

      // Initialize the simple adapter
      const result = await adapter.initialize({
        apiKey,
        defaultModel: config?.defaultModel || 'gpt-4o-mini',
        systemPrompt: config?.systemPrompt || 'You are a helpful assistant. Keep responses concise.',
        ...config
      });

      adapterRef.current = adapter;

      setState(prev => ({
        ...prev,
        isInitialized: true,
        error: null
      }));

      console.log('[LLM Adapter] Initialized successfully');
    } catch (err) {
      const error = `LLM initialization error: ${err}`;
      setState(prev => ({ ...prev, error }));
      console.error('[LLM Adapter]', error);
    }
  }, [state.isInitialized, config]);

  // Send message to LLM
  const sendMessage = useCallback(async (message: string, options?: CompletionOptions) => {
    if (!adapterRef.current) {
      setState(prev => ({ ...prev, error: 'LLM not initialized' }));
      return;
    }

    setState(prev => ({
      ...prev,
      isProcessing: true,
      error: null
    }));

    try {
      console.log('[LLM Adapter] Sending message:', message);

      const result = await adapterRef.current.complete(message, {
        useHistory: true,
        saveToHistory: true,
        ...options
      });

      if (!result.success) {
        throw new Error(result.error?.message || 'Failed to get completion');
      }

      const completion = result.value;
      const history = adapterRef.current.getHistory();

      setState(prev => ({
        ...prev,
        isProcessing: false,
        response: completion.text,
        conversationHistory: history,
        lastCompletionResult: completion
      }));

      console.log('[LLM Adapter] Response received:', completion.text);
      console.log('[LLM Adapter] Usage:', completion.usage);
      return completion.text;
    } catch (err) {
      setState(prev => ({
        ...prev,
        isProcessing: false,
        error: `LLM error: ${err}`
      }));
      console.error('[LLM Adapter]', err);
    }
  }, []);

  // Send message with streaming
  const sendMessageStream = useCallback(async function* (message: string, options?: CompletionOptions) {
    if (!adapterRef.current) {
      setState(prev => ({ ...prev, error: 'LLM not initialized' }));
      return;
    }

    setState(prev => ({
      ...prev,
      isProcessing: true,
      error: null,
      response: ''
    }));

    try {
      console.log('[LLM Adapter] Starting streaming for:', message);
      let fullText = '';

      for await (const token of adapterRef.current.completeStream(message, {
        useHistory: true,
        saveToHistory: true,
        ...options
      })) {
        fullText += token.token;
        setState(prev => ({
          ...prev,
          response: fullText
        }));
        yield token;
      }

      const history = adapterRef.current.getHistory();
      setState(prev => ({
        ...prev,
        isProcessing: false,
        conversationHistory: history
      }));

      console.log('[LLM Adapter] Streaming completed:', fullText);
    } catch (err) {
      setState(prev => ({
        ...prev,
        isProcessing: false,
        error: `LLM streaming error: ${err}`
      }));
      console.error('[LLM Adapter]', err);
    }
  }, []);

  // Clear conversation history
  const clearHistory = useCallback(() => {
    if (!adapterRef.current) return;

    adapterRef.current.clearHistory();
    setState(prev => ({
      ...prev,
      conversationHistory: [],
      response: '',
      lastCompletionResult: null
    }));
    console.log('[LLM Adapter] Conversation history cleared');
  }, []);

  // Update system prompt
  const setSystemPrompt = useCallback((prompt: string) => {
    if (!adapterRef.current) return;

    adapterRef.current.setSystemPrompt(prompt);
    console.log('[LLM Adapter] System prompt updated');
  }, []);

  // Get metrics
  const getMetrics = useCallback((): LLMMetrics | null => {
    if (!adapterRef.current) return null;
    return adapterRef.current.getMetrics();
  }, []);

  // Check if adapter is healthy
  const isHealthy = useCallback((): boolean => {
    if (!adapterRef.current) return false;
    return adapterRef.current.isHealthy();
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (adapterRef.current) {
        adapterRef.current.destroy();
        adapterRef.current = null;
      }
    };
  }, []);

  return {
    ...state,
    initialize,
    sendMessage,
    sendMessageStream,
    clearHistory,
    setSystemPrompt,
    getMetrics,
    isHealthy,
  };
}
