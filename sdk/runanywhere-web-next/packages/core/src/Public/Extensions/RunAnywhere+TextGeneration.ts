import {
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import { type LLMGenerationResult as ProtoLLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { type SDKEvent as ProtoSDKEvent } from '@runanywhere/proto-ts/sdk_events';
import { LLMProtoAdapter } from '../../Adapters/LLMProtoAdapter';
import { LlmTelemetry } from '../../Adapters/LlmTelemetry';
import { SDKException } from '../../Foundation/SDKException';
import { clientFor } from '../../runtime/HostRegistry';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    generate(request: ProtoLLMGenerateRequest): Promise<ProtoLLMGenerationResult | null>;
    generateStream(request: ProtoLLMGenerateRequest): AsyncIterable<ProtoLLMStreamEvent>;
    cancelGeneration(): Promise<ProtoSDKEvent | null>;
  }
}

function llm(): LLMProtoAdapter {
  const adapter = LLMProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('LLM');
  return adapter;
}

RunAnywhereSDK.prototype.generate = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  return llm().generate(request);
};

RunAnywhereSDK.prototype.generateStream = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  const stream = llm().generateStream(request);

  // The handle-less LLM proto path emits no telemetry (unlike the component
  // path iOS uses). Emit llm.generation.started/completed SDK-side by tracking
  // on the commons-worker telemetry manager. Passthrough when telemetry is off.
  const commons = clientFor('commons');
  const managerPtr = this.telemetryManagerPtr;
  if (!commons || managerPtr === 0) return stream;

  const tel = new LlmTelemetry(commons, managerPtr);
  const generationId = LlmTelemetry.newId();
  const modelId = request.modelId ?? '';
  const temperature = request.temperature ?? 0;
  const maxTokens = request.maxTokens ?? 0;

  return (async function* () {
    tel.started({ generationId, modelId, isStreaming: true, temperature, maxTokens });
    let final: ProtoLLMStreamEvent['result'];
    try {
      for await (const event of stream) {
        if (event.isFinal && event.result) final = event.result;
        yield event;
      }
    } finally {
      tel.completed({
        generationId,
        modelId,
        isStreaming: true,
        temperature,
        maxTokens,
        inputTokens: final?.promptTokens ?? 0,
        outputTokens: final?.completionTokens ?? 0,
        durationMs: final?.totalTimeMs ?? 0,
        tokensPerSecond: final?.tokensPerSecond ?? 0,
        timeToFirstTokenMs: final?.timeToFirstTokenMs ?? 0,
        contextLength: 0,
      });
    }
  })();
};

RunAnywhereSDK.prototype.cancelGeneration = function (this: RunAnywhereSDK) {
  const adapter = LLMProtoAdapter.tryDefault();
  return adapter ? adapter.cancel() : Promise.resolve(null);
};
