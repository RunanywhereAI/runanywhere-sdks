import { LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import { TokenKind } from '@runanywhere/proto-ts/voice_events';
import {
  type ToolCall as ProtoToolCall,
  type ToolDefinition as ProtoToolDefinition,
} from '@runanywhere/proto-ts/tool_calling';
import { ToolCallingAdapter, type ToolSession } from '../../Adapters/ToolCallingAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

export interface HostTool {
  definition: ProtoToolDefinition;
  execute(args: Record<string, unknown>): Promise<unknown> | unknown;
}

export interface ToolRunHandlers {
  onToken?: (token: string) => void;
  onThinking?: (token: string) => void;
  onToolCall?: (name: string, args: Record<string, unknown>) => void;
  onToolResult?: (name: string, result: unknown) => void;
}

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    generateWithTools(prompt: string, tools: HostTool[], handlers?: ToolRunHandlers): Promise<string>;
  }
}

function parseArgs(json: string): Record<string, unknown> {
  if (!json) return {};
  try {
    const parsed = JSON.parse(json);
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

RunAnywhereSDK.prototype.generateWithTools = function (this: RunAnywhereSDK, prompt, tools, handlers = {}) {
  this.ensureInitialized();
  const adapter = ToolCallingAdapter.tryDefaultForFramework(undefined);
  if (!adapter) throw SDKException.backendNotAvailable('ToolCalling');

  const executors = new Map(tools.map((t) => [t.definition.name, t.execute]));
  const definitions = tools.map((t) => t.definition);

  return new Promise<string>((resolve, reject) => {
    let session: ToolSession | null = null;
    let handle = 0;
    let done = false;
    let answer = '';
    const queued: ProtoToolCall[] = [];

    const cleanup = (): void => {
      if (handle) adapter.destroy(handle).catch(() => { /* best effort */ });
      try { session?.close(); } catch { /* best effort */ }
    };
    const settleResolve = (text: string): void => { if (done) return; done = true; cleanup(); resolve(text); };
    const settleReject = (err: unknown): void => { if (done) return; done = true; cleanup(); reject(err); };

    const runTool = async (call: ProtoToolCall): Promise<void> => {
      const name = call.name;
      const callId = call.id || call.callId || '';
      const args = parseArgs(call.argumentsJson);
      handlers.onToolCall?.(name, args);
      const exec = executors.get(name);
      if (!exec) {
        await adapter.stepWithResult(handle, callId, '{}', `unknown tool: ${name}`);
        return;
      }
      try {
        const result = await exec(args);
        handlers.onToolResult?.(name, result);
        await adapter.stepWithResult(handle, callId, JSON.stringify(result ?? {}));
      } catch (err) {
        await adapter.stepWithResult(handle, callId, '{}', err instanceof Error ? err.message : String(err));
      }
    };

    const onEvent = (event: { llmStreamEventBytes?: Uint8Array; toolCall?: ProtoToolCall; finalResult?: { text: string }; errorBytes?: Uint8Array }): void => {
      if (done) return;
      if (event.llmStreamEventBytes && event.llmStreamEventBytes.length > 0) {
        const lse = LLMStreamEvent.decode(event.llmStreamEventBytes);
        if (lse.token) {
          if (lse.kind === TokenKind.TOKEN_KIND_THOUGHT) handlers.onThinking?.(lse.token);
          else { answer += lse.token; handlers.onToken?.(lse.token); }
        }
      } else if (event.toolCall) {
        if (handle) runTool(event.toolCall).catch(settleReject);
        else queued.push(event.toolCall);
      } else if (event.finalResult) {
        settleResolve(event.finalResult.text || answer);
      } else if (event.errorBytes && event.errorBytes.length > 0) {
        settleReject(SDKException.processingFailed('tool-calling session failed'));
      }
    };

    adapter
      .createSession(
        {
          prompt,
          tools: definitions,
          maxTokens: 512,
          temperature: 0.4,
          topP: 0.9,
          systemPrompt: '',
          formatHint: '',
          maxIterations: 3,
          keepToolsAvailable: false,
          disableThinking: true,
        },
        onEvent,
      )
      .then((s) => {
        session = s;
        handle = s.handle;
        if (done) { cleanup(); return; }
        const pending = queued.splice(0);
        for (const call of pending) runTool(call).catch(settleReject);
      })
      .catch(settleReject);
  });
};
