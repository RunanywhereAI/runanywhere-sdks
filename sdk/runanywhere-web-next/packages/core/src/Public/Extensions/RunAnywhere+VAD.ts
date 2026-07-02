import {
  type SpeechActivityEvent as ProtoSpeechActivityEvent,
  type VADConfiguration as ProtoVADConfiguration,
  type VADOptions as ProtoVADOptions,
  type VADResult as ProtoVADResult,
  type VADStatistics as ProtoVADStatistics,
} from '@runanywhere/proto-ts/vad_options';
import { VADProtoAdapter } from '../../Adapters/VADProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    configureVAD(handle: number, config: ProtoVADConfiguration): Promise<boolean>;
    processVAD(handle: number, samples: Float32Array, options: ProtoVADOptions): Promise<ProtoVADResult | null>;
    vadStatistics(handle: number): Promise<ProtoVADStatistics | null>;
    onSpeechActivity(handle: number, onEvent: (event: ProtoSpeechActivityEvent) => void): () => void;
  }
}

function vad(): VADProtoAdapter {
  const adapter = VADProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('VAD');
  return adapter;
}

RunAnywhereSDK.prototype.configureVAD = function (this: RunAnywhereSDK, handle, config) {
  this.ensureInitialized();
  return vad().configure(handle, config);
};

RunAnywhereSDK.prototype.processVAD = function (this: RunAnywhereSDK, handle, samples, options) {
  this.ensureInitialized();
  return vad().process(handle, samples, options);
};

RunAnywhereSDK.prototype.vadStatistics = function (this: RunAnywhereSDK, handle) {
  this.ensureInitialized();
  return vad().statistics(handle);
};

RunAnywhereSDK.prototype.onSpeechActivity = function (this: RunAnywhereSDK, handle, onEvent) {
  this.ensureInitialized();
  return vad().setActivityHandler(handle, onEvent);
};
