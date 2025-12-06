# Streaming LLM Generation

This document describes the streaming LLM generation implementation for the React Native SDK, following the Swift SDK pattern.

## Overview

The streaming LLM generation feature provides token-by-token output with comprehensive performance metrics tracking. This enables real-time display of generated text and detailed analytics for optimization.

## Features

- **Token-by-Token Streaming**: Receive tokens immediately as they're generated
- **Performance Metrics**: Track time-to-first-token, tokens/second, and total generation time
- **Conversation Management**: Manage multi-turn conversations with context
- **Error Handling**: Graceful error handling during streaming
- **Type Safety**: Full TypeScript support with structured types

## Architecture

### Core Components

#### 1. LLMStreamToken

Represents a single token emitted during streaming:

```typescript
interface LLMStreamToken {
  token: string;           // The token text
  isLast: boolean;         // Whether this is the final token
  tokenIndex: number;      // Sequential index of the token
  timestamp: Date;         // When the token was generated
}
```

#### 2. LLMStreamResult

Contains both the token stream and final result:

```typescript
interface LLMStreamResult {
  stream: AsyncGenerator<LLMStreamToken, void, unknown>;  // Token stream
  result: Promise<LLMOutput>;                             // Final output with metrics
}
```

#### 3. LLMStreamMetrics

Performance metrics for streaming generation:

```typescript
interface LLMStreamMetrics {
  timeToFirstTokenMs: number;   // Time until first token arrives
  tokensPerSecond: number;      // Average generation speed
  totalTokens: number;          // Total tokens generated
  totalTimeMs: number;          // Total generation time
}
```

## Usage

### Basic Streaming

```typescript
import { LLMComponent, LLMConfiguration } from '@runanywhere/react-native';

// Initialize component
const config: LLMConfiguration = {
  modelId: 'llama-3.2-1b',
  maxTokens: 200,
  temperature: 0.7,
};

const llm = new LLMComponent(config);
await llm.initialize();

// Generate with streaming
const streamResult = llm.generateStreamWithMetrics('Tell me a story');

// Display tokens as they arrive
for await (const token of streamResult.stream) {
  if (!token.isLast) {
    console.log(token.token);
  }
}

// Get final metrics
const output = await streamResult.result;
console.log(`Tokens/sec: ${output.metadata.tokensPerSecond}`);
```

### Conversation Management

```typescript
import { ConversationManager } from '@runanywhere/react-native';

// Create conversation manager
const conversation = new ConversationManager({
  maxMessages: 20,
  maxContextTokens: 2048,
  systemPrompt: 'You are a helpful AI assistant.',
});

// Multi-turn conversation
const questions = ['What is AI?', 'How does it work?'];

for (const question of questions) {
  conversation.addUserMessage(question);

  const streamResult = llm.generateStreamWithMetrics(question);
  let response = '';

  for await (const token of streamResult.stream) {
    if (!token.isLast) {
      response += token.token;
      console.log(token.token);
    }
  }

  conversation.addAssistantMessage(response);
}

// Get conversation stats
const stats = conversation.getStats();
console.log(`Total messages: ${stats.totalMessages}`);
console.log(`Estimated tokens: ${stats.estimatedTokens}`);
```

### Performance Monitoring

```typescript
const streamResult = llm.generateStreamWithMetrics('Explain quantum computing');

let tokenCount = 0;
let firstTokenTime: number | null = null;
const startTime = Date.now();

for await (const token of streamResult.stream) {
  if (!token.isLast) {
    // Track first token
    if (firstTokenTime === null) {
      firstTokenTime = Date.now();
      console.log(`Time to first token: ${firstTokenTime - startTime}ms`);
    }

    tokenCount++;

    // Show progress
    if (tokenCount % 10 === 0) {
      const elapsed = (Date.now() - startTime) / 1000;
      const currentTPS = tokenCount / elapsed;
      console.log(`Progress: ${tokenCount} tokens, ${currentTPS.toFixed(2)} tok/s`);
    }
  }
}

// Final metrics
const output = await streamResult.result;
console.log('Final metrics:', {
  totalTokens: output.tokenUsage.completionTokens,
  avgTokensPerSec: output.metadata.tokensPerSecond,
  totalTime: output.metadata.generationTime,
});
```

### Error Handling

```typescript
try {
  const streamResult = llm.generateStreamWithMetrics('Generate text');

  try {
    for await (const token of streamResult.stream) {
      if (!token.isLast) {
        console.log(token.token);
      }
    }

    const output = await streamResult.result;
    console.log('Success!', output);
  } catch (streamError) {
    console.error('Streaming error:', streamError);
  }
} catch (initError) {
  console.error('Initialization error:', initError);
}
```

## API Reference

### LLMComponent

#### `generateStreamWithMetrics(prompt: string, options?: RunAnywhereGenerationOptions): LLMStreamResult`

Generates text with token-by-token streaming and performance metrics.

**Parameters:**
- `prompt` - The user prompt
- `options` - Optional generation options:
  - `maxTokens` - Maximum tokens to generate
  - `temperature` - Sampling temperature (0.0-2.0)
  - `systemPrompt` - Override system prompt
  - `topP` - Top-p sampling parameter
  - `stopSequences` - Stop sequences

**Returns:**
- `LLMStreamResult` with:
  - `stream` - AsyncGenerator yielding LLMStreamToken
  - `result` - Promise resolving to LLMOutput with metrics

**Example:**
```typescript
const streamResult = llm.generateStreamWithMetrics('Write a haiku', {
  maxTokens: 50,
  temperature: 0.8,
});
```

### ConversationManager

#### `constructor(config?: ConversationConfig)`

Creates a conversation manager.

**Config:**
- `maxMessages` - Maximum messages to retain (default: 20)
- `maxContextTokens` - Maximum context tokens (default: 2048)
- `systemPrompt` - System prompt for the conversation

#### `addUserMessage(content: string): void`

Adds a user message to the conversation.

#### `addAssistantMessage(content: string): void`

Adds an assistant message to the conversation.

#### `getMessages(): readonly Message[]`

Gets all messages in the conversation.

#### `clearHistory(): void`

Clears message history (preserves system prompt).

#### `reset(): void`

Resets conversation completely (clears messages and system prompt).

#### `estimateTokenCount(): number`

Estimates total token count of the conversation.

#### `buildPrompt(): string`

Builds a formatted prompt from conversation history.

#### `getStats(): ConversationStats`

Gets conversation statistics:
- `totalMessages` - Total message count
- `userMessages` - User message count
- `assistantMessages` - Assistant message count
- `estimatedTokens` - Estimated token count
- `hasSystemPrompt` - Whether system prompt is set

## Performance Characteristics

### Metrics Tracked

1. **Time to First Token (TTFT)**
   - Time from generation start to first token
   - Indicates model loading and prompt processing overhead
   - Typically 100-500ms for on-device models

2. **Tokens Per Second (TPS)**
   - Average generation speed
   - Varies by model size and hardware
   - Example: 10-50 tokens/sec on mobile devices

3. **Total Generation Time**
   - Complete end-to-end time
   - Includes all processing overhead

4. **Token Count**
   - Total tokens generated
   - Used for cost tracking and analytics

### Optimization Tips

1. **Use Streaming for Long Responses**
   - Provides better UX with immediate feedback
   - Allows early cancellation if needed

2. **Monitor TTFT**
   - High TTFT indicates model loading overhead
   - Consider keeping models loaded between requests

3. **Batch Conversations**
   - Reuse conversation context when possible
   - Reduces repeated prompt processing

4. **Limit Context Size**
   - Use ConversationManager to trim history
   - Prevents context window overflow

## Implementation Details

### Streaming Architecture

The streaming implementation uses:

1. **Token Queue**: Buffers tokens from the native callback
2. **AsyncGenerator**: Provides iterative token consumption
3. **Metrics Collector**: Tracks performance during generation
4. **Result Promise**: Resolves when generation completes

### Flow Diagram

```
User Request
    ↓
LLMComponent.generateStreamWithMetrics()
    ↓
Start Background Generation
    ↓
Native LLM Service
    ↓
Token Callback → Enqueue Token
    ↓
AsyncGenerator → Yield to User
    ↓
Stream Complete
    ↓
Calculate Metrics
    ↓
Resolve Result Promise
```

### Thread Safety

- Token queue operations are synchronous
- Async generator handles backpressure automatically
- Metrics collector accumulates state safely

## Comparison with Swift SDK

The React Native streaming implementation follows the Swift SDK pattern:

| Feature | Swift SDK | React Native SDK |
|---------|-----------|------------------|
| Token Streaming | AsyncThrowingStream | AsyncGenerator |
| Metrics Tracking | StreamingService | generateStreamWithMetrics |
| Conversation | Not built-in | ConversationManager |
| Performance | Native Swift | Native C++ via bridge |
| Type Safety | Swift types | TypeScript types |

## Examples

See `/examples/streaming-llm-example.ts` for comprehensive examples including:
- Basic streaming
- Conversation management
- Performance monitoring
- Error handling
- Parallel generation

## Testing

Run tests with:

```bash
npm test -- LLMStreaming.test.ts
```

Tests cover:
- Token streaming functionality
- Metrics calculation
- Conversation management
- Error handling
- Integration scenarios

## Limitations

1. **No Direct C++ Streaming Yet**: Currently relies on callback-based native implementation
2. **Single Active Stream**: One stream per LLM component instance
3. **Memory Buffering**: Tokens are buffered in JavaScript
4. **Approximate Token Counts**: Uses character-based estimation

## Future Improvements

- [ ] Direct C++ streaming support via TurboModules
- [ ] Multi-stream support
- [ ] Advanced token filtering (thinking tokens)
- [ ] Streaming with structured outputs
- [ ] Real-time cost tracking
- [ ] Stream cancellation support

## Related Documentation

- [LLM Component Guide](./LLM_COMPONENT.md)
- [Conversation Management](./CONVERSATION_MANAGEMENT.md)
- [Performance Optimization](./PERFORMANCE.md)
- [Swift SDK Streaming](../../runanywhere-swift/docs/STREAMING.md)
