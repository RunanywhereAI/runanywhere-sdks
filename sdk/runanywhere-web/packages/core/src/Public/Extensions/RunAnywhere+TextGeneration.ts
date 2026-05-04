/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation namespace — mirrors Swift's `RunAnywhere+TextGeneration.swift`.
 * Provides `RunAnywhere.textGeneration.*` capability surface (generate / generateStream / chat).
 * Also exposes the canonical §3 verbs `generateStructuredStream` and
 * `extractStructuredOutput` as flat top-level functions for use by RunAnywhere.ts.
 */

import type { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import type { StructuredOutputResult } from '@runanywhere/proto-ts/structured_output';
import type { LLMStreamingResult } from '../../types/index';
import { chat, generate as generateViaProvider, generateStream as generateStreamViaProvider } from './RunAnywhere+Convenience';
import { AsyncQueue } from '../../Foundation/AsyncQueue';
import { SDKException } from '../../Foundation/SDKException';
import { LLMProtoAdapter } from '../../Adapters/ModalityProtoAdapter';

export type { LLMGenerationOptions, LLMGenerationResult };
export type { LLMStreamingResult };
export type { StructuredOutputResult };

// ---------------------------------------------------------------------------
// Schema type accepted by the canonical structured-output verbs.
// ---------------------------------------------------------------------------

/** Minimal JSON Schema descriptor accepted by structured-output methods. */
export interface JSONSchemaDescriptor {
  jsonSchema: string;
  parse?: (text: string) => unknown;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildLLMGenerateRequest(
  prompt: string,
  options: Partial<LLMGenerationOptions> = {},
  streamingEnabled = false,
): LLMGenerateRequest {
  return {
    prompt,
    maxTokens: options.maxTokens ?? 0,
    temperature: options.temperature ?? 0,
    topP: options.topP ?? 0,
    topK: options.topK ?? 0,
    systemPrompt: options.systemPrompt ?? '',
    emitThoughts: options.thinkingPattern != null,
    repetitionPenalty: options.repetitionPenalty ?? 0,
    stopSequences: options.stopSequences ?? [],
    streamingEnabled,
    preferredFramework: options.preferredFramework == null
      ? ''
      : String(options.preferredFramework),
    jsonSchema: options.jsonSchema ?? options.structuredOutput?.jsonSchema ?? '',
    executionTarget: options.executionTarget == null
      ? ''
      : String(options.executionTarget),
  };
}

function structuredResultFromGeneration(result: LLMGenerationResult): StructuredOutputResult {
  const extractedJson = result.jsonOutput
    ?? result.structuredOutputValidation?.extractedJson
    ?? '';
  const jsonBytes = new TextEncoder().encode(extractedJson || 'null');
  return {
    parsedJson: jsonBytes,
    rawText: result.text,
    validation: result.structuredOutputValidation ?? {
      isValid: extractedJson.length > 0,
      containsJson: extractedJson.length > 0,
      errorMessage: result.errorMessage || undefined,
      rawOutput: result.text,
      extractedJson: extractedJson || undefined,
    },
  };
}

function streamingResultFromEvents(
  events: AsyncIterable<LLMStreamEvent>,
  cancelNative: () => void,
): LLMStreamingResult {
  const queue = new AsyncQueue<string>();
  let started = false;
  let cancelled = false;
  let fullText = '';
  let tokenCount = 0;
  let finalEvent: LLMStreamEvent | undefined;
  const startedAt = performance.now();

  const result = new Promise<LLMGenerationResult>((resolve, reject) => {
    const start = (): void => {
      if (started) return;
      started = true;
      void (async () => {
        try {
          for await (const event of events) {
            finalEvent = event;
            if (event.token) {
              fullText += event.token;
              tokenCount += 1;
              queue.push(event.token);
            }
            if (event.errorMessage) {
              throw SDKException.generationFailed(event.errorMessage);
            }
          }
          queue.complete();
          resolve(finalLLMResult(fullText, tokenCount, startedAt, finalEvent));
        } catch (error) {
          queue.fail(error instanceof Error ? error : new Error(String(error)));
          reject(error);
        }
      })();
    };

    const originalIterator = queue[Symbol.asyncIterator].bind(queue);
    queue[Symbol.asyncIterator] = () => {
      start();
      return originalIterator();
    };
    start();
  });

  return {
    stream: queue,
    result,
    cancel() {
      if (cancelled) return;
      cancelled = true;
      cancelNative();
      queue.complete();
    },
  };
}

function finalLLMResult(
  fullText: string,
  tokenCount: number,
  startedAt: number,
  finalEvent?: LLMStreamEvent,
): LLMGenerationResult {
  const final = finalEvent?.result;
  const generationTimeMs = final?.totalTimeMs ?? performance.now() - startedAt;
  const inputTokens = final?.promptTokens ?? 0;
  const tokensGenerated = final?.completionTokens ?? tokenCount;
  return {
    text: final?.text ?? fullText,
    thinkingContent: final?.thinkingContent,
    inputTokens,
    tokensGenerated,
    modelUsed: '',
    generationTimeMs,
    ttftMs: final?.timeToFirstTokenMs,
    tokensPerSecond: final?.tokensPerSecond
      ?? (generationTimeMs > 0 ? (tokensGenerated / generationTimeMs) * 1000 : 0),
    finishReason: finalEvent?.finishReason || final?.finishReason || '',
    thinkingTokens: 0,
    responseTokens: tokensGenerated,
    totalTokens: final?.totalTokens ?? inputTokens + tokensGenerated,
    errorMessage: finalEvent?.errorMessage || undefined,
  };
}

// ---------------------------------------------------------------------------
// §3 `generateStructuredStream` — canonical flat verb
// ---------------------------------------------------------------------------

/**
 * Streaming structured output (§3 `generateStructuredStream`).
 *
 * Uses the generated-proto LLM request shape and lets the native LLM service
 * own schema prompting, JSON extraction, and validation.
 */
export async function* generateStructuredStream(
  prompt: string,
  schema: JSONSchemaDescriptor,
  options?: Partial<LLMGenerationOptions>,
): AsyncIterable<StructuredOutputResult> {
  const result = await TextGeneration.generate({
    ...options,
    prompt,
    jsonSchema: schema.jsonSchema,
  } as Partial<LLMGenerationOptions> & { prompt: string });
  yield structuredResultFromGeneration(result);
}

// ---------------------------------------------------------------------------
// §3 `extractStructuredOutput` — canonical flat verb (pure TS)
// ---------------------------------------------------------------------------

/**
 * Extract and validate structured output from already-generated text (§3).
 *
 * Native structured-output extraction is owned by the C++ modality layer.
 */
export function extractStructuredOutput(
  text: string,
  schema: JSONSchemaDescriptor,
): StructuredOutputResult {
  void text;
  void schema;
  throw SDKException.backendNotAvailable(
    'extractStructuredOutput',
    'Use generateStructuredStream/generate with jsonSchema so C++ can extract and validate structured output.',
  );
}

// ---------------------------------------------------------------------------
// TextGeneration namespace object
// ---------------------------------------------------------------------------

export const TextGeneration = {
  async generate(options: Partial<LLMGenerationOptions>): Promise<LLMGenerationResult> {
    const prompt = (options as { prompt?: string }).prompt ?? '';
    const adapter = LLMProtoAdapter.tryDefault();
    if (adapter?.supportsProtoLLM()) {
      const result = adapter.generate(buildLLMGenerateRequest(prompt, options, false));
      if (result) return result;
    }
    return generateViaProvider(prompt, options);
  },

  async generateStream(options: Partial<LLMGenerationOptions>): Promise<LLMStreamingResult> {
    const prompt = (options as { prompt?: string }).prompt ?? '';
    const adapter = LLMProtoAdapter.tryDefault();
    if (adapter?.supportsProtoLLM()) {
      const events = adapter.generateStream(buildLLMGenerateRequest(prompt, options, true));
      return streamingResultFromEvents(events, () => {
        adapter.cancel();
      });
    }
    return generateStreamViaProvider(prompt, options);
  },

  async chat(prompt: string, options?: Partial<LLMGenerationOptions>): Promise<string> {
    return chat(prompt, options);
  },

  generateStructuredStream,
  extractStructuredOutput,
};
