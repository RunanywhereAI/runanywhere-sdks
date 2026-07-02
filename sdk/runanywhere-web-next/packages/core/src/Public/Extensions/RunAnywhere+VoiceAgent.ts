import {
  type VoiceAgentComposeConfig as ProtoVoiceAgentComposeConfig,
  type VoiceAgentResult as ProtoVoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import { type VoiceAgentComponentStates as ProtoVoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';
import { type VoiceEvent as ProtoVoiceEvent } from '@runanywhere/proto-ts/voice_events';
import { VoiceAgentProtoAdapter } from '../../Adapters/VoiceAgentProtoAdapter';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    voiceAgentInitialize(handle: number, config: ProtoVoiceAgentComposeConfig): Promise<ProtoVoiceAgentComponentStates | null>;
    voiceAgentStates(handle: number): Promise<ProtoVoiceAgentComponentStates | null>;
    processVoiceTurn(handle: number, audio: Uint8Array): Promise<ProtoVoiceAgentResult | null>;
    voiceAgentDestroy(handle: number): Promise<void>;
    voiceEvents(handle: number): AsyncIterable<ProtoVoiceEvent>;
  }
}

function voiceAgent(): VoiceAgentProtoAdapter {
  const adapter = VoiceAgentProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('VoiceAgent');
  return adapter;
}

RunAnywhereSDK.prototype.voiceAgentInitialize = function (this: RunAnywhereSDK, handle, config) {
  this.ensureInitialized();
  return voiceAgent().initialize(handle, config);
};

RunAnywhereSDK.prototype.voiceAgentStates = function (this: RunAnywhereSDK, handle) {
  this.ensureInitialized();
  return voiceAgent().componentStates(handle);
};

RunAnywhereSDK.prototype.processVoiceTurn = function (this: RunAnywhereSDK, handle, audio) {
  this.ensureInitialized();
  return voiceAgent().processVoiceTurn(handle, audio);
};

RunAnywhereSDK.prototype.voiceAgentDestroy = function (this: RunAnywhereSDK, handle) {
  return voiceAgent().destroy(handle);
};

RunAnywhereSDK.prototype.voiceEvents = function (this: RunAnywhereSDK, handle) {
  this.ensureInitialized();
  const adapter = VoiceAgentStreamAdapter.tryDefault(handle);
  if (!adapter) throw SDKException.backendNotAvailable('VoiceAgent');
  return adapter.stream();
};
