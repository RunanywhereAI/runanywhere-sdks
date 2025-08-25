'use client';

import { useState, useCallback } from 'react';

interface LLMConfig {
  apiKey?: string;
  model?: string;
  baseUrl?: string;
  temperature?: number;
  maxTokens?: number;
  systemPrompt?: string;
}

interface LLMState {
  isInitialized: boolean;
  isProcessing: boolean;
  response: string;
  error: string | null;
  conversationHistory: Array<{ role: string; content: string }>;
}

/**
 * Hook for LLM interactions using OpenAI API directly
 * Single responsibility: Process text through LLM
 * IMPORTANT: Does NOT import SDK packages to avoid bundle issues
 */
export function useLLM(config: LLMConfig = {}) {
  const [state, setState] = useState<LLMState>({
    isInitialized: false,
    isProcessing: false,
    response: '',
    error: null,
    conversationHistory: [],
  });

  // Initialize LLM
  const initialize = useCallback(async () => {
    if (state.isInitialized) return;

    if (!config.apiKey) {
      setState(prev => ({
        ...prev,
        error: 'OpenAI API key required for LLM'
      }));
      return;
    }

    try {
      // Validate API key format
      if (!config.apiKey.startsWith('sk-')) {
        throw new Error('Invalid OpenAI API key format');
      }

      setState(prev => ({
        ...prev,
        isInitialized: true,
        error: null
      }));

      console.log('[LLM] Initialized with OpenAI API');
    } catch (err) {
      setState(prev => ({
        ...prev,
        error: `LLM initialization error: ${err}`
      }));
      console.error('[LLM]', err);
    }
  }, [state.isInitialized, config.apiKey]);

  // Send message to LLM
  const sendMessage = useCallback(async (message: string) => {
    if (!state.isInitialized) {
      await initialize();
    }

    if (!config.apiKey) {
      setState(prev => ({
        ...prev,
        error: 'OpenAI API key required'
      }));
      return;
    }

    setState(prev => ({
      ...prev,
      isProcessing: true,
      error: null
    }));

    try {
      const messages = [
        {
          role: 'system',
          content: config.systemPrompt || 'You are a helpful assistant. Keep responses concise.'
        },
        ...state.conversationHistory,
        { role: 'user', content: message }
      ];

      const response = await fetch(config.baseUrl || 'https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`
        },
        body: JSON.stringify({
          model: config.model || 'gpt-4o-mini',
          messages,
          temperature: config.temperature || 0.7,
          max_tokens: config.maxTokens || 150
        })
      });

      if (!response.ok) {
        throw new Error(`OpenAI API error: ${response.statusText}`);
      }

      const data = await response.json();
      const llmResponse = data.choices[0].message.content;

      setState(prev => ({
        ...prev,
        isProcessing: false,
        response: llmResponse,
        conversationHistory: [
          ...prev.conversationHistory,
          { role: 'user', content: message },
          { role: 'assistant', content: llmResponse }
        ]
      }));

      console.log('[LLM] Response received:', llmResponse);
      return llmResponse;
    } catch (err) {
      setState(prev => ({
        ...prev,
        isProcessing: false,
        error: `LLM error: ${err}`
      }));
      console.error('[LLM]', err);
    }
  }, [state.isInitialized, state.conversationHistory, config, initialize]);

  // Clear conversation history
  const clearHistory = useCallback(() => {
    setState(prev => ({
      ...prev,
      conversationHistory: [],
      response: ''
    }));
    console.log('[LLM] Conversation history cleared');
  }, []);

  // Update system prompt
  const updateSystemPrompt = useCallback((prompt: string) => {
    config.systemPrompt = prompt;
    console.log('[LLM] System prompt updated');
  }, [config]);

  return {
    ...state,
    initialize,
    sendMessage,
    clearHistory,
    updateSystemPrompt,
  };
}
