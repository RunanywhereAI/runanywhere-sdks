/**
 * Tests for LLM Streaming functionality
 */

import { LLMCapability } from '../Features/LLM/LLMCapability';
import { LLMConfigurationImpl } from '../Features/LLM/LLMConfiguration';
import { ConversationManager } from '../services/ConversationManager';
import { MessageRole } from '../Features/LLM/LLMModels';

// Mock the LLM service
jest.mock('../Foundation/DependencyInjection/ServiceRegistry', () => ({
  ServiceRegistry: {
    shared: {
      llmProvider: jest.fn(() => ({
        createLLMService: jest.fn(() => ({
          initialize: jest.fn(),
          cleanup: jest.fn(),
          generate: jest.fn(async () => ({
            text: 'Test response',
            tokensUsed: 10,
          })),
          generateStream: jest.fn(async (prompt: string, options: any, onToken: (token: string) => void) => {
            // Simulate streaming tokens
            const tokens = ['Hello', ' ', 'world', '!'];
            for (const token of tokens) {
              onToken(token);
              await new Promise((resolve) => setTimeout(resolve, 10));
            }
            return {
              text: 'Hello world!',
              tokensUsed: 4,
            };
          }),
          isReady: true,
          currentModel: 'test-model',
        })),
      })),
    },
  },
}));

describe('LLM Streaming', () => {
  describe('LLMStreamToken', () => {
    it('should have correct structure', () => {
      const token = {
        token: 'test',
        isLast: false,
        tokenIndex: 0,
        timestamp: new Date(),
      };

      expect(token).toHaveProperty('token');
      expect(token).toHaveProperty('isLast');
      expect(token).toHaveProperty('tokenIndex');
      expect(token).toHaveProperty('timestamp');
    });
  });

  describe('LLMCapability.generateStreamWithMetrics', () => {
    let llm: LLMCapability;

    beforeEach(async () => {
      const config = new LLMConfigurationImpl({
        modelId: 'test-model',
        maxTokens: 100,
        temperature: 0.7,
      });
      llm = new LLMCapability(config);
      await llm.initialize();
    });

    afterEach(async () => {
      await llm.cleanup();
    });

    it('should return stream and result', () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');

      expect(streamResult).toHaveProperty('stream');
      expect(streamResult).toHaveProperty('result');
    });

    it('should stream tokens', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');
      const tokens: string[] = [];

      for await (const token of streamResult.stream) {
        if (!token.isLast) {
          tokens.push(token.token);
        }
      }

      expect(tokens.length).toBeGreaterThan(0);
    });

    it('should provide final result with metrics', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');

      // Consume stream
      for await (const token of streamResult.stream) {
        // Just consume
      }

      const output = await streamResult.result;

      expect(output).toHaveProperty('text');
      expect(output).toHaveProperty('tokenUsage');
      expect(output).toHaveProperty('metadata');
      expect(output.metadata).toHaveProperty('tokensPerSecond');
      expect(output.metadata).toHaveProperty('generationTime');
    });

    it('should track token index correctly', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');
      const indices: number[] = [];

      for await (const token of streamResult.stream) {
        if (!token.isLast) {
          indices.push(token.tokenIndex);
        }
      }

      // Check indices are sequential
      for (let i = 0; i < indices.length; i++) {
        expect(indices[i]).toBe(i);
      }
    });

    it('should mark last token correctly', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');
      let lastTokenFound = false;

      for await (const token of streamResult.stream) {
        if (token.isLast) {
          lastTokenFound = true;
        }
      }

      expect(lastTokenFound).toBe(true);
    });

    it('should calculate tokens per second', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt');

      // Consume stream
      for await (const token of streamResult.stream) {
        // Just consume
      }

      const output = await streamResult.result;
      expect(output.metadata.tokensPerSecond).toBeGreaterThan(0);
    });

    it('should handle custom options', async () => {
      const streamResult = llm.generateStreamWithMetrics('Test prompt', {
        maxTokens: 50,
        temperature: 0.5,
      });

      // Consume stream
      for await (const token of streamResult.stream) {
        // Just consume
      }

      const output = await streamResult.result;
      expect(output.metadata.temperature).toBe(0.5);
    });
  });

  describe('ConversationManager', () => {
    let manager: ConversationManager;

    beforeEach(() => {
      manager = new ConversationManager({
        maxMessages: 10,
        maxContextTokens: 1000,
        systemPrompt: 'You are a helpful assistant.',
      });
    });

    it('should add user messages', () => {
      manager.addUserMessage('Hello');
      const messages = manager.getMessages();

      expect(messages.length).toBe(1);
      expect(messages[0]?.role).toBe(MessageRole.User);
      expect(messages[0]?.content).toBe('Hello');
    });

    it('should add assistant messages', () => {
      manager.addAssistantMessage('Hi there!');
      const messages = manager.getMessages();

      expect(messages.length).toBe(1);
      expect(messages[0]?.role).toBe(MessageRole.Assistant);
      expect(messages[0]?.content).toBe('Hi there!');
    });

    it('should maintain conversation order', () => {
      manager.addUserMessage('Question 1');
      manager.addAssistantMessage('Answer 1');
      manager.addUserMessage('Question 2');
      manager.addAssistantMessage('Answer 2');

      const messages = manager.getMessages();
      expect(messages.length).toBe(4);
      expect(messages[0]?.role).toBe(MessageRole.User);
      expect(messages[1]?.role).toBe(MessageRole.Assistant);
      expect(messages[2]?.role).toBe(MessageRole.User);
      expect(messages[3]?.role).toBe(MessageRole.Assistant);
    });

    it('should trim history when max messages exceeded', () => {
      for (let i = 0; i < 15; i++) {
        manager.addUserMessage(`Message ${i}`);
      }

      const messages = manager.getMessages();
      expect(messages.length).toBeLessThanOrEqual(10);
    });

    it('should clear history', () => {
      manager.addUserMessage('Test');
      manager.addAssistantMessage('Response');
      manager.clearHistory();

      expect(manager.getMessageCount()).toBe(0);
    });

    it('should preserve system prompt after clear', () => {
      manager.clearHistory();
      expect(manager.getSystemPrompt()).toBe('You are a helpful assistant.');
    });

    it('should reset completely', () => {
      manager.addUserMessage('Test');
      manager.reset();

      expect(manager.getMessageCount()).toBe(0);
      expect(manager.getSystemPrompt()).toBeNull();
    });

    it('should estimate token count', () => {
      manager.addUserMessage('This is a test message');
      const tokenCount = manager.estimateTokenCount();

      expect(tokenCount).toBeGreaterThan(0);
    });

    it('should build formatted prompt', () => {
      manager.addUserMessage('Hello');
      manager.addAssistantMessage('Hi there!');

      const prompt = manager.buildPrompt();

      expect(prompt).toContain('System: You are a helpful assistant.');
      expect(prompt).toContain('User: Hello');
      expect(prompt).toContain('Assistant: Hi there!');
      expect(prompt).toContain('Assistant:');
    });

    it('should provide conversation stats', () => {
      manager.addUserMessage('Q1');
      manager.addAssistantMessage('A1');
      manager.addUserMessage('Q2');

      const stats = manager.getStats();

      expect(stats.totalMessages).toBe(3);
      expect(stats.userMessages).toBe(2);
      expect(stats.assistantMessages).toBe(1);
      expect(stats.hasSystemPrompt).toBe(true);
      expect(stats.estimatedTokens).toBeGreaterThan(0);
    });

    it('should export to JSON', () => {
      manager.addUserMessage('Test');
      const snapshot = manager.toJSON();

      expect(snapshot).toHaveProperty('systemPrompt');
      expect(snapshot).toHaveProperty('messages');
      expect(snapshot).toHaveProperty('timestamp');
      expect(snapshot.messages.length).toBe(1);
    });

    it('should import from JSON', () => {
      const snapshot = {
        systemPrompt: 'Test system',
        messages: [
          { role: MessageRole.User, content: 'Test message' },
        ],
        timestamp: new Date(),
      };

      manager.fromJSON(snapshot);

      expect(manager.getSystemPrompt()).toBe('Test system');
      expect(manager.getMessageCount()).toBe(1);
    });

    it('should check context limits', () => {
      // Add a few messages
      manager.addUserMessage('Short message');
      expect(manager.isWithinContextLimit()).toBe(true);

      // Try to exceed limits
      const longMessage = 'x'.repeat(5000);
      for (let i = 0; i < 100; i++) {
        manager.addUserMessage(longMessage);
      }

      // Should still be within limits due to trimming
      expect(manager.getMessageCount()).toBeLessThanOrEqual(10);
    });
  });

  describe('Integration: Streaming with Conversation', () => {
    let llm: LLMCapability;
    let conversation: ConversationManager;

    beforeEach(async () => {
      conversation = new ConversationManager({
        systemPrompt: 'You are a helpful assistant.',
      });

      const config: LLMConfiguration = {
        modelId: 'test-model',
        maxTokens: 100,
        temperature: 0.7,
      };

      llm = new LLMCapability(config);
      await llm.initialize();
    });

    afterEach(async () => {
      await llm.cleanup();
    });

    it('should handle multi-turn conversation with streaming', async () => {
      const turns = [
        'What is AI?',
        'How does it work?',
      ];

      for (const userMessage of turns) {
        conversation.addUserMessage(userMessage);

        const streamResult = llm.generateStreamWithMetrics(userMessage);
        let response = '';

        for await (const token of streamResult.stream) {
          if (!token.isLast) {
            response += token.token;
          }
        }

        conversation.addAssistantMessage(response);
      }

      expect(conversation.getMessageCount()).toBe(4); // 2 user + 2 assistant
    });
  });
});
