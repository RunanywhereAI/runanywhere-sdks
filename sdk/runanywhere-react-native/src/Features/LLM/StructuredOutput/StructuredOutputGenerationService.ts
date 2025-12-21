/**
 * StructuredOutputGenerationService.ts
 *
 * Service for generating structured output from LLMs
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputGenerationService.swift
 */

import type { Generatable, StructuredOutputConfig } from './Generatable';
import type { LLMStreamResult } from '../LLMModels';
import type { StreamToken, StructuredOutputStreamResult } from './StreamToken';
import {
  createStreamToken,
  createStructuredOutputStreamResult,
} from './StreamToken';
import { StreamAccumulator } from './StreamAccumulator';
import type { LLMOutput } from '../LLMModels';
import type { LLMFramework } from '../../../types/enums';

/**
 * StructuredOutputHandler types (imported from existing implementation)
 */
export interface StructuredOutputHandler {
  getSystemPrompt<T extends { jsonSchema: string }>(type: T): string;
  buildUserPrompt<T extends { jsonSchema: string }>(
    type: T,
    content: string
  ): string;
  parseStructuredOutput<T>(text: string, schema: { jsonSchema: string }): T;
}

/**
 * LLM generation options interface
 * This should match the actual LLMGenerationOptions from your implementation
 */
export interface LLMGenerationOptions {
  readonly maxTokens?: number;
  readonly temperature?: number;
  readonly topP?: number;
  readonly stopSequences?: string[];
  readonly streamingEnabled?: boolean;
  readonly preferredFramework?: LLMFramework;
  readonly structuredOutput?: StructuredOutputConfig;
  readonly systemPrompt?: string | null;
}

/**
 * LLM Capability interface (simplified for this implementation)
 */
export interface LLMCapability {
  generate(prompt: string, options?: LLMGenerationOptions): Promise<LLMOutput>;
}

/**
 * Structured output errors
 * Matches iOS StructuredOutputError enum
 */
export class StructuredOutputError extends Error {
  constructor(
    message: string,
    public readonly type:
      | 'invalidJSON'
      | 'validationFailed'
      | 'extractionFailed'
      | 'unsupportedType'
  ) {
    super(message);
    this.name = 'StructuredOutputError';
  }

  static invalidJSON(detail: string): StructuredOutputError {
    return new StructuredOutputError(`Invalid JSON: ${detail}`, 'invalidJSON');
  }

  static validationFailed(detail: string): StructuredOutputError {
    return new StructuredOutputError(
      `Validation failed: ${detail}`,
      'validationFailed'
    );
  }

  static extractionFailed(detail: string): StructuredOutputError {
    return new StructuredOutputError(
      `Failed to extract structured output: ${detail}`,
      'extractionFailed'
    );
  }

  static unsupportedType(type: string): StructuredOutputError {
    return new StructuredOutputError(
      `Unsupported type for structured output: ${type}`,
      'unsupportedType'
    );
  }
}

/**
 * Service for generating structured output from LLMs
 * Matches iOS StructuredOutputGenerationService
 */
export class StructuredOutputGenerationService {
  constructor(private readonly handler: StructuredOutputHandler) {}

  /**
   * Generate structured output that conforms to a Generatable type (non-streaming)
   * Matches iOS: generateStructured(_:prompt:options:llmCapability:)
   *
   * @param type - The type to generate (must conform to Generatable)
   * @param prompt - The prompt to generate from
   * @param options - Generation options (structured output config will be added automatically)
   * @param llmCapability - The LLM capability to use for generation
   * @returns The generated object of the specified type
   */
  public async generateStructured<T>(
    type: Generatable,
    prompt: string,
    options: LLMGenerationOptions | null,
    llmCapability: LLMCapability
  ): Promise<T> {
    // Get system prompt for structured output
    const systemPrompt = this.handler.getSystemPrompt(type);

    // Create effective options with system prompt
    const effectiveOptions: LLMGenerationOptions = {
      maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
      temperature:
        options?.temperature ?? type.generationHints?.temperature ?? 0.7,
      topP: options?.topP ?? 1.0,
      stopSequences: options?.stopSequences ?? [],
      streamingEnabled: false,
      preferredFramework: options?.preferredFramework,
      structuredOutput: {
        type,
        includeSchemaInPrompt: false,
      },
      systemPrompt,
    };

    // Build user prompt
    const userPrompt = this.handler.buildUserPrompt(type, prompt);

    // Generate the text using LLMCapability
    const generationResult = await llmCapability.generate(
      userPrompt,
      effectiveOptions
    );

    // Parse using StructuredOutputHandler
    const result = this.handler.parseStructuredOutput<T>(
      generationResult.text,
      type
    );

    return result;
  }

  /**
   * Generate structured output with streaming support
   * Matches iOS: generateStructuredStream(_:content:options:streamGenerator:)
   *
   * @param type - The type to generate (must conform to Generatable)
   * @param content - The content to generate from
   * @param options - Generation options (optional)
   * @param streamGenerator - Function to generate token stream
   * @returns A structured output stream containing tokens and final result
   */
  public generateStructuredStream<T>(
    type: Generatable,
    content: string,
    options: LLMGenerationOptions | null,
    streamGenerator: (
      prompt: string,
      options: LLMGenerationOptions
    ) => Promise<LLMStreamResult>
  ): StructuredOutputStreamResult<T> {
    // Create a shared accumulator
    const accumulator = new StreamAccumulator();
    const handler = this.handler;

    // Get system prompt for structured output
    const systemPrompt = handler.getSystemPrompt(type);

    // Create effective options with system prompt
    const effectiveOptions: LLMGenerationOptions = {
      maxTokens: options?.maxTokens ?? type.generationHints?.maxTokens ?? 1500,
      temperature:
        options?.temperature ?? type.generationHints?.temperature ?? 0.7,
      topP: options?.topP ?? 1.0,
      stopSequences: options?.stopSequences ?? [],
      streamingEnabled: true,
      preferredFramework: options?.preferredFramework,
      structuredOutput: {
        type,
        includeSchemaInPrompt: false,
      },
      systemPrompt,
    };

    // Build user prompt
    const userPrompt = handler.buildUserPrompt(type, content);

    // Create token stream
    const tokenStream = this.createTokenStream(
      userPrompt,
      effectiveOptions,
      streamGenerator,
      accumulator
    );

    // Create result task that waits for streaming to complete
    const resultPromise = this.createResultPromise<T>(
      type,
      accumulator,
      handler
    );

    return createStructuredOutputStreamResult(tokenStream, resultPromise);
  }

  /**
   * Create the token stream from the LLM stream
   */
  private async *createTokenStream(
    userPrompt: string,
    effectiveOptions: LLMGenerationOptions,
    streamGenerator: (
      prompt: string,
      options: LLMGenerationOptions
    ) => Promise<LLMStreamResult>,
    accumulator: StreamAccumulator
  ): AsyncGenerator<StreamToken, void, unknown> {
    try {
      let tokenIndex = 0;

      // Stream tokens
      const streamingResult = await streamGenerator(
        userPrompt,
        effectiveOptions
      );

      for await (const token of streamingResult.stream) {
        const streamToken = createStreamToken(
          token.token,
          tokenIndex,
          token.timestamp
        );

        // Accumulate for parsing
        accumulator.append(token.token);

        // Yield to consumer
        yield streamToken;
        tokenIndex++;
      }

      accumulator.markComplete();
    } catch (error) {
      accumulator.markComplete();
      throw error;
    }
  }

  /**
   * Create the result promise that waits for stream completion and parses
   */
  private async createResultPromise<T>(
    type: Generatable,
    accumulator: StreamAccumulator,
    handler: StructuredOutputHandler
  ): Promise<T> {
    // Wait for accumulation to complete
    await accumulator.waitForCompletion();

    // Get full response
    const fullResponse = accumulator.fullText;

    // Parse using StructuredOutputHandler with retry logic
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        return handler.parseStructuredOutput<T>(fullResponse, type);
      } catch (error) {
        lastError = error as Error;
        if (attempt < 3) {
          // Brief delay before retry (100ms)
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      }
    }

    throw (
      lastError ??
      StructuredOutputError.extractionFailed(
        'Failed to parse structured output after 3 attempts'
      )
    );
  }

  /**
   * Generate with structured output configuration
   * Matches iOS: generateWithStructuredOutput(prompt:structuredOutput:options:llmCapability:)
   *
   * @param prompt - The prompt to generate from
   * @param structuredOutput - Structured output configuration
   * @param options - Generation options
   * @param llmCapability - The LLM capability to use for generation
   * @returns Generation result with structured data
   */
  public async generateWithStructuredOutput(
    prompt: string,
    structuredOutput: StructuredOutputConfig,
    options: LLMGenerationOptions | null,
    llmCapability: LLMCapability
  ): Promise<LLMOutput> {
    // Generate using regular generation with structured config in options
    const baseOptions = options ?? {};
    const internalOptions: LLMGenerationOptions = {
      maxTokens: baseOptions.maxTokens,
      temperature: baseOptions.temperature,
      topP: baseOptions.topP,
      stopSequences: baseOptions.stopSequences,
      streamingEnabled: baseOptions.streamingEnabled,
      preferredFramework: baseOptions.preferredFramework,
      structuredOutput,
      systemPrompt: baseOptions.systemPrompt,
    };

    return await llmCapability.generate(prompt, internalOptions);
  }
}
