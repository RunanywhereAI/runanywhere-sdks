/**
 * LlmTelemetry.ts
 *
 * SDK-side emission of LLM generation telemetry (`llm.generation.started` /
 * `llm.generation.completed`).
 *
 * Why the SDK emits these (not commons): the web LLM path calls the handle-less
 * `rac_llm_generate_stream_proto`, which goes straight to the backend and — unlike
 * the component path (`rac_llm_component_generate_stream`) used by iOS, or the
 * explicit JNI emission on Android — publishes no generation telemetry. There is
 * no proto ABI for the component path, so web-next builds the `SDKEvent` itself
 * and feeds it to the telemetry manager via `rac_telemetry_manager_track_proto`.
 *
 * The commons destination router is bypassed here (it isn't SDK-callable); we
 * track directly on the manager, which derives the modality/event-type, queues
 * the row, and — because `completed` is a terminal event — immediately flushes
 * the batch to `/api/v2/sdk/telemetry/llm`.
 */

import { EventCategory } from '@runanywhere/proto-ts/component_types';
import { ErrorSeverity } from '@runanywhere/proto-ts/errors';
import {
  EventDestination,
  GenerationEventKind,
  SDKComponent,
  SDKEvent,
  type GenerationEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { SDKLogger } from '../Foundation/SDKLogger';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const logger = new SDKLogger('LlmTelemetry');

export interface LlmStartedFields {
  generationId: string;
  modelId: string;
  isStreaming: boolean;
  temperature: number;
  maxTokens: number;
}

export interface LlmCompletedFields extends LlmStartedFields {
  inputTokens: number;
  outputTokens: number;
  durationMs: number;
  tokensPerSecond: number;
  timeToFirstTokenMs: number;
  contextLength: number;
}

/**
 * Tracks LLM generation events on the commons-worker telemetry manager. Created
 * per generation with the commons `WorkerProtoClient` and the manager pointer
 * reported at worker init. A zero `managerPtr` (telemetry not wired) makes every
 * call a no-op.
 */
export class LlmTelemetry {
  constructor(
    private readonly client: WorkerProtoClient,
    private readonly managerPtr: number,
  ) {}

  get enabled(): boolean {
    return this.managerPtr !== 0;
  }

  /** Fresh generation id, shared between the started/completed pair. */
  static newId(): string {
    return uuid();
  }

  started(f: LlmStartedFields): void {
    this.track({
      kind: GenerationEventKind.GENERATION_EVENT_KIND_STARTED,
      modelId: f.modelId,
      modelName: f.modelId,
      isStreaming: f.isStreaming,
      temperature: f.temperature,
      maxTokens: f.maxTokens,
    }, f.generationId);
  }

  completed(f: LlmCompletedFields): void {
    this.track({
      kind: GenerationEventKind.GENERATION_EVENT_KIND_COMPLETED,
      modelId: f.modelId,
      modelName: f.modelId,
      isStreaming: f.isStreaming,
      inputTokens: f.inputTokens,
      tokensUsed: f.outputTokens,
      latencyMs: Math.round(f.durationMs),
      durationMs: f.durationMs,
      tokensPerSecond: f.tokensPerSecond,
      timeToFirstTokenMs: Math.round(f.timeToFirstTokenMs),
      temperature: f.temperature,
      maxTokens: f.maxTokens,
      contextLength: f.contextLength,
    }, f.generationId);
  }

  private track(generation: Partial<GenerationEvent>, generationId: string): void {
    if (this.managerPtr === 0) return;
    try {
      const event = SDKEvent.fromPartial({
        timestampMs: Date.now(),
        severity: ErrorSeverity.ERROR_SEVERITY_INFO,
        category: EventCategory.EVENT_CATEGORY_LLM,
        component: SDKComponent.SDK_COMPONENT_LLM,
        id: uuid(),
        sessionId: generationId,
        destination: EventDestination.EVENT_DESTINATION_ALL,
        source: 'web',
        generation,
      });
      const bytes = SDKEvent.encode(event).finish();
      void this.client
        .callRc('rac_telemetry_manager_track_proto', [Arg.num(this.managerPtr), Arg.bytes(bytes)])
        .catch((err) => logger.warning(`track failed: ${err instanceof Error ? err.message : String(err)}`));
    } catch (err) {
      logger.warning(`build/track threw: ${err instanceof Error ? err.message : String(err)}`);
    }
  }
}

function uuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
