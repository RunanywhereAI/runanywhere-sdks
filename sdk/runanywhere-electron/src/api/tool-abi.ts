// tool-abi.ts — typed access to the commons tool-calling run loop.
//
// Mirrors Swift's RunAnywhere+ToolCalling: commons owns prompt formatting,
// parsing, validation, execution ordering, the follow-up turn, and
// cancellation. This file carries the registry of executors and trampolines
// one call at a time through the addon, which is the only part of tool calling
// that has to live in the host language.

import { SDKException } from '../errors';
import {
  ToolCall as ProtoToolCall,
  ToolCallingHistoryTurn,
  ToolCallingOptions,
  ToolCallingResult,
  ToolCallingRole,
  ToolCallingSessionCreateRequest,
  ToolChoiceMode,
  ToolDefinition as ProtoToolDefinition,
  ToolResult as ProtoToolResult,
} from '../proto/tool_calling';
import type { RaBackend, ToolRunLoopEvent } from './backend';
import { ToolChoice } from './types';
import type { ToolCall, ToolDefinition } from './types';

const CHOICE_TO_PROTO: Record<string, ToolChoiceMode> = {
  [ToolChoice.AUTO]: ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
  [ToolChoice.NONE]: ToolChoiceMode.TOOL_CHOICE_MODE_NONE,
  [ToolChoice.REQUIRED]: ToolChoiceMode.TOOL_CHOICE_MODE_REQUIRED,
};

/** Map the public tool choice onto the mode and the forced name it implies. */
export function toProtoToolChoice(choice: ToolChoice | undefined): {
  mode: ToolChoiceMode;
  forcedToolName?: string;
} {
  if (choice == null) return { mode: ToolChoiceMode.TOOL_CHOICE_MODE_AUTO };
  if (typeof choice === 'object') {
    return { mode: ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC, forcedToolName: choice.forced };
  }
  return { mode: CHOICE_TO_PROTO[choice] ?? ToolChoiceMode.TOOL_CHOICE_MODE_AUTO };
}

/**
 * A tool as commons wants it. `parameters` crosses the wire as JSON Schema
 * text, which is the same shape OpenAI, Anthropic, and MCP each publish.
 */
export function toProtoTool(tool: ToolDefinition): ProtoToolDefinition {
  return ProtoToolDefinition.fromPartial({
    name: tool.name,
    description: tool.description ?? '',
    parameters: tool.parameters ? JSON.stringify(tool.parameters) : '{}',
  });
}

const ROLE_BY_INDEX = [ToolCallingRole.TOOL_CALLING_ROLE_USER,
                       ToolCallingRole.TOOL_CALLING_ROLE_ASSISTANT];

/** Prior turns, alternating from the first, excluding the turn being answered. */
export function toHistoryTurns(contents: string[]): ToolCallingHistoryTurn[] {
  return contents.map((content, index) =>
    ToolCallingHistoryTurn.fromPartial({ role: ROLE_BY_INDEX[index % 2], content })
  );
}

/** What one executed call looked like, in the public shape. */
function toPublicCall(call: ProtoToolCall, result: ProtoToolResult | undefined): ToolCall {
  return {
    id: call.id,
    name: call.name,
    arguments: parseObject(call.argumentsJson),
    result: result ? parseObject(result.resultJson) : undefined,
  };
}

function parseObject(json: string): Record<string, unknown> {
  if (!json) return {};
  try {
    const value = JSON.parse(json) as unknown;
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : { value };
  } catch {
    return {};
  }
}

/** Pair each call commons reported with the result it recorded for it. */
export function toPublicCalls(result: ToolCallingResult): ToolCall[] {
  const byId = new Map<string, ProtoToolResult>();
  const byName = new Map<string, ProtoToolResult>();
  for (const r of result.toolResults) {
    if (r.toolCallId) byId.set(r.toolCallId, r);
    if (!byName.has(r.name)) byName.set(r.name, r);
  }
  return result.toolCalls.map((call) =>
    toPublicCall(call, byId.get(call.id) ?? byName.get(call.name))
  );
}

/** Runs a tool call and returns whatever the executor produced. */
export type ToolInvoke = (
  name: string,
  args: Record<string, unknown>
) => Promise<Record<string, unknown>>;

/** Called as commons executes each call, before the loop's follow-up turn. */
export type ToolProgress = (call: ToolCall) => void;

/** A run loop in flight, and the only way to stop it. */
export interface ToolRun {
  result: Promise<ToolCallingResult>;
  cancel(): Promise<void>;
}

/** The commons tool-calling layer, bound to one backend. */
export class ToolAbi {
  constructor(private readonly backend: RaBackend) {}

  /**
   * Run the whole loop in commons. `invoke` is called once per tool commons
   * decided to run; `onCall` sees each one as it completes, which is what
   * makes a streaming caller able to show tool activity before the answer.
   */
  start(
    request: ToolCallingSessionCreateRequest,
    invoke: ToolInvoke,
    onCall?: ToolProgress
  ): ToolRun {
    const bytes = ToolCallingSessionCreateRequest.encode(request).finish();
    // Commons publishes the handle before its first generation, but a caller
    // can abandon the iterator earlier than that; remembering the request is
    // what makes an early cancel land rather than being dropped.
    let handle = 0;
    let cancelRequested = false;
    const cancelNow = async (): Promise<void> => {
      cancelRequested = true;
      if (handle !== 0) await this.backend.toolRunLoopCancel(handle);
    };

    const reply = this.backend.toolRunLoop(bytes, async (event: ToolRunLoopEvent) => {
      if (event.handle !== undefined) {
        handle = event.handle;
        if (cancelRequested) await this.backend.toolRunLoopCancel(handle);
        return undefined;
      }
      const call = ProtoToolCall.decode(event.toolCall as Uint8Array);
      const started = Date.now();
      let executed: ProtoToolResult;
      try {
        const value = await invoke(call.name, parseObject(call.argumentsJson));
        executed = ProtoToolResult.fromPartial({
          toolCallId: call.id,
          name: call.name,
          resultJson: JSON.stringify(value ?? {}),
          isError: false,
          startedAtMs: started,
          completedAtMs: Date.now(),
        });
      } catch (error) {
        // A failed tool is data commons feeds back to the model, not a failed
        // run: isError lets it self-correct instead of reading the message as
        // the tool's answer.
        executed = ProtoToolResult.fromPartial({
          toolCallId: call.id,
          name: call.name,
          resultJson: '{}',
          isError: true,
          error: error instanceof Error ? error.message : String(error),
          startedAtMs: started,
          completedAtMs: Date.now(),
        });
      }
      onCall?.(toPublicCall(call, executed));
      return ProtoToolResult.encode(executed).finish();
    });

    return {
      cancel: cancelNow,
      result: reply.then((bytes) => {
        const result = ToolCallingResult.decode(bytes);
        if (result.errorCode !== 0) {
          throw SDKException.generationFailed(
            result.errorMessage || `tool calling failed (${result.errorCode})`
          );
        }
        return result;
      }),
    };
  }

  /** The common case: run the loop to completion with no cancel handle. */
  runLoop(
    request: ToolCallingSessionCreateRequest,
    invoke: ToolInvoke,
    onCall?: ToolProgress
  ): Promise<ToolCallingResult> {
    return this.start(request, invoke, onCall).result;
  }
}

export { ToolCallingOptions, ToolCallingResult, ToolCallingSessionCreateRequest, ToolChoiceMode };
