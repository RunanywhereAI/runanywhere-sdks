/**
 * Example: Streaming LLM Generation with Metrics
 *
 * This example demonstrates how to use the streaming LLM generation
 * with full performance metrics tracking.
 */

import { LLMComponent } from '../src/components/LLM/LLMComponent';
import { LLMConfigurationImpl } from '../src/components/LLM/LLMConfiguration';
import { ConversationManager } from '../src/services/ConversationManager';

/**
 * Example 1: Basic streaming with metrics
 */
async function basicStreamingExample() {
  // Create and initialize LLM component
  const config = new LLMConfigurationImpl({
    modelId: 'llama-3.2-1b',
    maxTokens: 200,
    temperature: 0.7,
    systemPrompt: 'You are a helpful assistant.',
  });

  const llm = new LLMComponent(config);
  await llm.initialize();

  // Generate with streaming
  const streamResult = llm.generateStreamWithMetrics(
    'Tell me a short story about a robot learning to paint.',
    {
      maxTokens: 150,
      temperature: 0.8,
    }
  );

  console.log('Streaming tokens:');
  console.log('=================');

  // Consume tokens as they arrive
  for await (const token of streamResult.stream) {
    if (!token.isLast) {
      process.stdout.write(token.token);
    }
  }

  console.log('\n\n');

  // Get final result with metrics
  const output = await streamResult.result;

  console.log('Generation Complete!');
  console.log('===================');
  console.log(`Model: ${output.metadata.modelId}`);
  console.log(`Tokens: ${output.tokenUsage.completionTokens}`);
  console.log(`Tokens/sec: ${output.metadata.tokensPerSecond.toFixed(2)}`);
  console.log(`Total time: ${output.metadata.generationTime.toFixed(2)}s`);

  await llm.cleanup();
}

/**
 * Example 2: Streaming with conversation context
 */
async function conversationStreamingExample() {
  // Create conversation manager
  const conversation = new ConversationManager({
    maxMessages: 20,
    maxContextTokens: 2048,
    systemPrompt: 'You are a knowledgeable AI assistant specializing in science.',
  });

  // Create and initialize LLM component
  const config = new LLMConfigurationImpl({
    modelId: 'llama-3.2-1b',
    maxTokens: 200,
    temperature: 0.7,
  });

  const llm = new LLMComponent(config);
  await llm.initialize();

  // Start a multi-turn conversation
  const questions = [
    'What is photosynthesis?',
    'How does it benefit the environment?',
    'Can you explain it in simpler terms for a 10-year-old?',
  ];

  for (const question of questions) {
    // Add user message to conversation
    conversation.addUserMessage(question);

    console.log(`\nUser: ${question}`);
    console.log('Assistant: ');

    // Generate streaming response
    const streamResult = llm.generateStreamWithMetrics(question, {
      systemPrompt: conversation.getSystemPrompt() || undefined,
    });

    let fullResponse = '';

    // Display tokens as they arrive
    for await (const token of streamResult.stream) {
      if (!token.isLast) {
        process.stdout.write(token.token);
        fullResponse += token.token;
      }
    }

    console.log('\n');

    // Add assistant response to conversation
    conversation.addAssistantMessage(fullResponse);

    // Get metrics
    const output = await streamResult.result;
    console.log(
      `(${output.tokenUsage.completionTokens} tokens, ${output.metadata.tokensPerSecond.toFixed(2)} tok/s)`
    );
  }

  // Display conversation stats
  const stats = conversation.getStats();
  console.log('\n=== Conversation Stats ===');
  console.log(`Total messages: ${stats.totalMessages}`);
  console.log(`User messages: ${stats.userMessages}`);
  console.log(`Assistant messages: ${stats.assistantMessages}`);
  console.log(`Estimated tokens: ${stats.estimatedTokens}`);

  await llm.cleanup();
}

/**
 * Example 3: Monitoring streaming performance
 */
async function performanceMonitoringExample() {
  const config = new LLMConfigurationImpl({
    modelId: 'llama-3.2-1b',
    maxTokens: 500,
    temperature: 0.7,
  });

  const llm = new LLMComponent(config);
  await llm.initialize();

  const streamResult = llm.generateStreamWithMetrics(
    'Write a detailed explanation of how neural networks work.'
  );

  let tokenCount = 0;
  let firstTokenTime: number | null = null;
  const startTime = Date.now();

  console.log('Streaming with performance monitoring:');
  console.log('======================================\n');

  for await (const token of streamResult.stream) {
    if (!token.isLast) {
      // Track first token
      if (firstTokenTime === null) {
        firstTokenTime = Date.now();
        console.log(
          `Time to first token: ${((firstTokenTime - startTime) / 1000).toFixed(3)}s\n`
        );
      }

      // Display token
      process.stdout.write(token.token);
      tokenCount++;

      // Show progress every 50 tokens
      if (tokenCount % 50 === 0) {
        const elapsed = (Date.now() - startTime) / 1000;
        const currentTPS = tokenCount / elapsed;
        process.stdout.write(`\n[${tokenCount} tokens, ${currentTPS.toFixed(2)} tok/s]\n`);
      }
    }
  }

  // Final metrics
  const output = await streamResult.result;
  console.log('\n\n=== Final Metrics ===');
  console.log(`Total tokens: ${output.tokenUsage.completionTokens}`);
  console.log(`Generation time: ${output.metadata.generationTime.toFixed(2)}s`);
  console.log(`Average tokens/sec: ${output.metadata.tokensPerSecond.toFixed(2)}`);

  await llm.cleanup();
}

/**
 * Example 4: Error handling with streaming
 */
async function errorHandlingExample() {
  const config = new LLMConfigurationImpl({
    modelId: 'llama-3.2-1b',
    maxTokens: 200,
    temperature: 0.7,
  });

  const llm = new LLMComponent(config);

  try {
    await llm.initialize();

    const streamResult = llm.generateStreamWithMetrics('What is the meaning of life?');

    try {
      for await (const token of streamResult.stream) {
        if (!token.isLast) {
          process.stdout.write(token.token);
        }
      }

      const output = await streamResult.result;
      console.log(`\nSuccess! Generated ${output.tokenUsage.completionTokens} tokens`);
    } catch (streamError) {
      console.error('Error during streaming:', streamError);
    }
  } catch (error) {
    console.error('Error initializing LLM:', error);
  } finally {
    await llm.cleanup();
  }
}

/**
 * Example 5: Parallel streaming (multiple prompts)
 */
async function parallelStreamingExample() {
  const config = new LLMConfigurationImpl({
    modelId: 'llama-3.2-1b',
    maxTokens: 100,
    temperature: 0.7,
  });

  const llm = new LLMComponent(config);
  await llm.initialize();

  const prompts = [
    'Explain quantum computing in one sentence.',
    'What is the capital of France?',
    'Write a haiku about programming.',
  ];

  console.log('Generating multiple responses:\n');

  // Process all prompts (note: they'll run sequentially due to single LLM instance)
  for (let i = 0; i < prompts.length; i++) {
    console.log(`\n[Prompt ${i + 1}]: ${prompts[i]}`);
    console.log('Response: ');

    const streamResult = llm.generateStreamWithMetrics(prompts[i]);

    for await (const token of streamResult.stream) {
      if (!token.isLast) {
        process.stdout.write(token.token);
      }
    }

    const output = await streamResult.result;
    console.log(
      `\n(${output.metadata.tokensPerSecond.toFixed(2)} tok/s)`
    );
  }

  await llm.cleanup();
}

// Export examples
export {
  basicStreamingExample,
  conversationStreamingExample,
  performanceMonitoringExample,
  errorHandlingExample,
  parallelStreamingExample,
};

// Run an example if executed directly
if (require.main === module) {
  basicStreamingExample()
    .then(() => console.log('\nExample completed successfully!'))
    .catch((error) => console.error('Example failed:', error));
}
