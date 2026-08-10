// llm-abi.ts — typed access to the commons LLM proto ABI.
//
// Mirrors Swift's `CppBridge.LLM`: a generated request in, a generated result or
// event stream out. None of these calls takes a handle because they read the
// model `rac_model_lifecycle_load_proto` put in commons' own store, and none of
// them re-derives anything the result already carries: the thinking split, the
// token accounting, the finish reason, and the extracted JSON all arrive
// normalized.

import { SDKException } from '../errors';
// Commons validates a JSON Schema but does not yet derive a decoding grammar
// from one (structured_output.cpp's own TODO), so the GBNF still comes from
// here. This import goes away when that lands.
import { jsonSchemaToGrammar } from '../grammar';
import {
  FinishReason as ProtoFinishReason,
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import { LLMGenerateRequest, LLMStreamEvent, LLMStreamEventKind } from '@runanywhere/proto-ts/llm_service';
import { ChatMessage as ProtoChatMessage, MessageRole } from '@runanywhere/proto-ts/chat';
import {
  StructuredOutputParseRequest,
  StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { ReasoningMode as ProtoReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
import type { RaBackend } from './backend';
import { bridgeStream } from './iter';
import { invokeProto } from './proto-abi';
import type { LlmOptions } from './options';
import { FinishReason, ReasoningMode, Role } from './types';
import type { ChatMessage, GenerationMetrics, JsonSchema } from './types';

const ROLE_TO_PROTO: Record<Role, MessageRole> = {
  [Role.SYSTEM]: MessageRole.MESSAGE_ROLE_SYSTEM,
  [Role.USER]: MessageRole.MESSAGE_ROLE_USER,
  [Role.ASSISTANT]: MessageRole.MESSAGE_ROLE_ASSISTANT,
  [Role.TOOL]: MessageRole.MESSAGE_ROLE_TOOL,
};

const REASONING_TO_PROTO: Record<ReasoningMode, ProtoReasoningMode> = {
  [ReasoningMode.ON]: ProtoReasoningMode.REASONING_MODE_ON,
  [ReasoningMode.OFF]: ProtoReasoningMode.REASONING_MODE_OFF,
};

/**
 * Collapse commons' finish reasons onto the four the public surface names.
 * STOP_SEQUENCE is a stop, and a context overflow is the context-window form of
 * running out of room, so both fold into their neighbour rather than inventing
 * public values the cross-SDK spec does not have.
 */
export function toPublicFinishReason(reason: ProtoFinishReason): FinishReason {
  switch (reason) {
    case ProtoFinishReason.FINISH_REASON_LENGTH:
    case ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW:
      return FinishReason.LENGTH;
    case ProtoFinishReason.FINISH_REASON_TOOL_CALLS:
      return FinishReason.TOOL_CALLS;
    case ProtoFinishReason.FINISH_REASON_CANCELLED:
      return FinishReason.CANCELLED;
    default:
      return FinishReason.STOP;
  }
}

/** A prompt or a conversation, as the messages commons expects. */
export function toProtoMessages(input: string | ChatMessage[]): ProtoChatMessage[] {
  const turns: ChatMessage[] =
    typeof input === 'string' ? [{ role: Role.USER, content: input }] : input;
  if (!turns.length) {
    throw SDKException.validationFailed({
      fieldPath: 'messages',
      message: 'at least one message is required',
    });
  }
  return turns.map((m) =>
    ProtoChatMessage.fromPartial({
      role: ROLE_TO_PROTO[m.role] ?? MessageRole.MESSAGE_ROLE_USER,
      content: m.content,
      toolCallId: m.toolCallId,
    })
  );
}

/**
 * Map {@link LlmOptions} onto the generated options message.
 *
 * Every field is left absent unless the caller set it: `LLMGenerationOptions`
 * documents explicit presence, so commons applies the `rac_default` annotation
 * from `idl/llm_options.proto` for anything unset. That is why there is no
 * defaults table here any more.
 */
export function toProtoOptions(
  o: LlmOptions = {},
  extra: { structuredSchema?: JsonSchema } = {}
): LLMGenerationOptions {
  const schema = extra.structuredSchema ?? o.structuredOutput?.schema;
  const strict = extra.structuredSchema ? true : o.structuredOutput?.strict !== false;
  return LLMGenerationOptions.fromPartial({
    maxOutputTokens: o.maxOutputTokens,
    temperature: o.temperature,
    topP: o.topP,
    topK: o.topK,
    minP: o.minP,
    frequencyPenalty: o.frequencyPenalty,
    presencePenalty: o.presencePenalty,
    repeatPenalty: o.repetitionPenalty,
    seed: o.seed,
    stopSequences: o.stopSequences ? [...o.stopSequences] : [],
    systemPrompt: o.systemPrompt,
    reasoning: o.reasoning
      ? {
          mode: o.reasoning.mode
            ? REASONING_TO_PROTO[o.reasoning.mode]
            : ProtoReasoningMode.REASONING_MODE_UNSPECIFIED,
          includeInOutput: o.reasoning.includeInOutput ?? false,
          pattern: o.reasoning.pattern
            ? { openTag: o.reasoning.pattern.open, closeTag: o.reasoning.pattern.close }
            : undefined,
        }
      : undefined,
    // Both fields, because they do different jobs. Commons reads `grammar` to
    // constrain decoding (llm_module.cpp options_from_request) and `schema` to
    // extract and validate the document afterwards; it does not derive one from
    // the other, and its own TODO in structured_output.cpp is to build the GBNF
    // from the schema. Until that lands, the SDK supplies the grammar.
    // `strict: false` asks for validation without constraining the sampler.
    structuredOutput: schema
      ? {
          schema: JSON.stringify(schema),
          grammar: strict ? jsonSchemaToGrammar(schema) : undefined,
          includeSchemaInPrompt: true,
        }
      : undefined,
  });
}

/** Throughput and token accounting, straight out of the result. */
export function toPublicMetrics(
  result: LLMGenerationResult,
  requestId: string,
  model: string
): GenerationMetrics {
  const usage = result.usage;
  return {
    inputTokens: usage?.inputTokens ?? 0,
    outputTokens: usage?.outputTokens ?? result.responseTokens,
    timeToFirstTokenMs: usage?.ttftMs ?? 0,
    tokensPerSecond: usage?.decodeTokensPerSecond ?? 0,
    requestId,
    model: result.modelUsed || model,
  };
}

/** Raise a commons-authored error, or return the result when there is none. */
function orThrow<T extends { error?: { message?: string } | undefined }>(result: T): T {
  if (result.error) throw SDKException.fromProto(result.error as never);
  return result;
}

/** The commons LLM layer, bound to one backend. */
export class LlmAbi {
  constructor(private readonly backend: RaBackend) {}

  async generate(request: LLMGenerateRequest): Promise<LLMGenerationResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.llmGenerateProto(bytes),
        LLMGenerateRequest,
        request,
        LLMGenerationResult
      )
    );
  }

  /**
   * One `LLMStreamEvent` per callback. Breaking out of the loop cancels the
   * native generation rather than leaving it running to completion.
   */
  generateStream(request: LLMGenerateRequest): AsyncIterableIterator<LLMStreamEvent> {
    const bytes = LLMGenerateRequest.encode(request).finish();
    let inflight: Promise<void> | null = null;
    return bridgeStream<LLMStreamEvent>(
      (sink) => {
        inflight = this.backend.llmGenerateStreamProto(bytes, (event) => {
          sink.push(LLMStreamEvent.decode(event));
        });
        return inflight;
      },
      async () => {
        await this.cancel();
        // Requesting the cancel is not the same as the generation having
        // stopped: commons clears its cancel flag when the running generation
        // observes it, so a caller who starts the next generation before the
        // worker unwinds gets that generation cancelled instead. Wait the
        // worker out here rather than making every caller do it.
        await inflight?.catch(() => undefined);
      }
    );
  }

  async cancel(): Promise<void> {
    // The reply is the CancellationEvent commons also publishes on its own
    // stream; nothing here needs it.
    await this.backend.llmCancelProto();
  }

  /**
   * Extract the JSON document from model output. Commons owns the extraction,
   * which is why a fenced or prose-wrapped answer still parses here.
   */
  async parseStructured(request: StructuredOutputParseRequest): Promise<StructuredOutputResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.structuredParse(bytes),
        StructuredOutputParseRequest,
        request,
        StructuredOutputResult
      )
    );
  }

  async generateStructured(request: LLMGenerateRequest): Promise<StructuredOutputResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.structuredGenerate(bytes),
        LLMGenerateRequest,
        request,
        StructuredOutputResult
      )
    );
  }

  async validateStructured(
    request: StructuredOutputParseRequest
  ): Promise<StructuredOutputResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.structuredValidate(bytes),
        StructuredOutputParseRequest,
        request,
        StructuredOutputResult
      )
    );
  }
}

export { LLMGenerateRequest, LLMStreamEvent, LLMStreamEventKind };
export type { LLMGenerationResult };
