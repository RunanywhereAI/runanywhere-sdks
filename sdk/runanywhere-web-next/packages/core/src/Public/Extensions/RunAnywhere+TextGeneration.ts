import {
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import { type LLMGenerationResult as ProtoLLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { type SDKEvent as ProtoSDKEvent } from '@runanywhere/proto-ts/sdk_events';
import { LLMProtoAdapter } from '../../Adapters/LLMProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
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
  return llm().generateStream(request);
};

RunAnywhereSDK.prototype.cancelGeneration = function (this: RunAnywhereSDK) {
  const adapter = LLMProtoAdapter.tryDefault();
  return adapter ? adapter.cancel() : Promise.resolve(null);
};
