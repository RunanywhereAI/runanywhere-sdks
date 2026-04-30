/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Top-level Voice Agent C-ABI parity surface. Mirrors Swift's
 * `RunAnywhere.processVoiceTurn`, `voiceAgentTranscribe`,
 * `voiceAgentGenerateResponse`, `voiceAgentSynthesizeSpeech`,
 * `streamVoiceAgent`, and `cleanupVoiceAgent` static verbs.
 *
 * Single canonical path: backend packages (e.g. `@runanywhere/web-llamacpp`,
 * `@runanywhere/web-onnx`) install a `VoiceAgentProvider` via
 * `setVoiceAgentProvider(...)`. Each verb delegates directly. There is no
 * TS-side compose fallback — that path was deleted in v0.20.0 alongside
 * `RunAnywhere+VoicePipeline.ts` (see CANONICAL_API.md §10 / G-F4).
 *
 * Streaming: `streamVoiceAgent()` returns an `AsyncIterable<VoiceEvent>`
 * built on `VoiceAgentStreamAdapter`. The provider supplies either a raw
 * `rac_voice_agent_handle_t` (proto-byte WASM callback) or a custom
 * `VoiceAgentStreamTransport` for tests.
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
import type { VoiceAgentRequest } from '@runanywhere/proto-ts/voice_agent_service';
import type { VoiceEvent } from '@runanywhere/proto-ts/voice_events';
import type {
  VoiceAgentConfig,
  VoiceAgentComponentStates,
  VoiceAgentResult,
} from '../../types/index';
import type { EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule';

const logger = new SDKLogger('VoiceAgent');

/**
 * Backend-supplied voice-agent provider. Installed by `@runanywhere/web-llamacpp`
 * + `@runanywhere/web-onnx` (or a unified backend) once the WASM
 * `rac_voice_agent_*` exports are loaded. Until a provider is registered,
 * every verb on `RunAnywhere.<voice agent>` throws `backendNotAvailable`.
 */
export interface VoiceAgentProvider {
  initializeVoiceAgent(config: VoiceAgentConfig): Promise<void>;
  initializeVoiceAgentWithLoadedModels(): Promise<void>;
  isVoiceAgentReady(): Promise<boolean> | boolean;
  getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> | VoiceAgentComponentStates;
  processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult>;
  voiceAgentTranscribe(audio: Float32Array | Uint8Array): Promise<string>;
  voiceAgentGenerateResponse(prompt: string): Promise<string>;
  voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array>;
  cleanupVoiceAgent(): Promise<void> | void;

  /**
   * Either a numeric WASM handle (`rac_voice_agent_handle_t`) plus the
   * Emscripten module that owns it, or a custom transport for tests. When
   * absent, `streamVoiceAgent()` throws `backendNotAvailable`.
   */
  getVoiceAgentStream?(): {
    handle: number;
    module: EmscriptenRunanywhereModule;
  } | {
    transport: VoiceAgentStreamTransport;
  } | null;
}

let _provider: VoiceAgentProvider | null = null;

export function setVoiceAgentProvider(provider: VoiceAgentProvider | null): void {
  _provider = provider;
}

function requireProvider(verb: string): VoiceAgentProvider {
  if (!_provider) {
    throw SDKException.backendNotAvailable(
      verb,
      'No voice-agent provider registered. Install and register a backend ' +
      '(e.g. `@runanywhere/web-llamacpp` + `@runanywhere/web-onnx`) so the ' +
      'WASM rac_voice_agent_* exports are reachable.',
    );
  }
  return _provider;
}

// ---------------------------------------------------------------------------
// Public API — Swift-symmetric verbs.
// ---------------------------------------------------------------------------

export async function initializeVoiceAgent(config: VoiceAgentConfig): Promise<void> {
  await requireProvider('initializeVoiceAgent').initializeVoiceAgent(config);
  logger.info('VoiceAgent initialized');
}

export async function initializeVoiceAgentWithLoadedModels(): Promise<void> {
  await requireProvider('initializeVoiceAgentWithLoadedModels').initializeVoiceAgentWithLoadedModels();
}

export async function isVoiceAgentReady(): Promise<boolean> {
  return Promise.resolve(requireProvider('isVoiceAgentReady').isVoiceAgentReady());
}

export async function getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> {
  return Promise.resolve(requireProvider('getVoiceAgentComponentStates').getVoiceAgentComponentStates());
}

export async function areAllVoiceComponentsReady(): Promise<boolean> {
  return (await getVoiceAgentComponentStates()).ready;
}

/** Mirror Swift `RunAnywhere.processVoiceTurn(audioData) -> VoiceAgentResult`. */
export async function processVoiceTurn(
  audio: Float32Array | Uint8Array,
): Promise<VoiceAgentResult> {
  return requireProvider('processVoiceTurn').processVoiceTurn(audio);
}

export async function voiceAgentTranscribe(
  audio: Float32Array | Uint8Array,
): Promise<string> {
  return requireProvider('voiceAgentTranscribe').voiceAgentTranscribe(audio);
}

export async function voiceAgentGenerateResponse(prompt: string): Promise<string> {
  return requireProvider('voiceAgentGenerateResponse').voiceAgentGenerateResponse(prompt);
}

export async function voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array> {
  return requireProvider('voiceAgentSynthesizeSpeech').voiceAgentSynthesizeSpeech(text);
}

export async function cleanupVoiceAgent(): Promise<void> {
  if (!_provider) return;
  await Promise.resolve(_provider.cleanupVoiceAgent());
}

/**
 * Mirror Swift `RunAnywhere.streamVoiceAgent() -> AsyncStream<RAVoiceEvent>`.
 *
 * Returns an `AsyncIterable<VoiceEvent>` driven by the backend's
 * `rac_voice_agent_set_proto_callback` (or a custom transport for tests).
 * The provider must implement `getVoiceAgentStream()`; if absent, throws
 * `backendNotAvailable`.
 */
export function streamVoiceAgent(
  req: VoiceAgentRequest = { eventFilter: '' },
): AsyncIterable<VoiceEvent> {
  const provider = requireProvider('streamVoiceAgent');
  if (typeof provider.getVoiceAgentStream !== 'function') {
    throw SDKException.backendNotAvailable(
      'streamVoiceAgent',
      'Backend voice-agent provider does not implement getVoiceAgentStream().',
    );
  }
  const src = provider.getVoiceAgentStream();
  if (src == null) {
    throw SDKException.backendNotAvailable(
      'streamVoiceAgent',
      'Backend has not constructed a voice-agent handle yet — call ' +
      'initializeVoiceAgent / initializeVoiceAgentWithLoadedModels first.',
    );
  }
  const adapter = 'transport' in src
    ? new VoiceAgentStreamAdapter(src.transport)
    : new VoiceAgentStreamAdapter(src.handle, src.module);
  return adapter.stream(req);
}

export const VoiceAgent = {
  setProvider: setVoiceAgentProvider,
  initialize: initializeVoiceAgent,
  initializeWithLoadedModels: initializeVoiceAgentWithLoadedModels,
  isReady: isVoiceAgentReady,
  getComponentStates: getVoiceAgentComponentStates,
  areAllComponentsReady: areAllVoiceComponentsReady,
  processTurn: processVoiceTurn,
  transcribe: voiceAgentTranscribe,
  generateResponse: voiceAgentGenerateResponse,
  synthesizeSpeech: voiceAgentSynthesizeSpeech,
  stream: streamVoiceAgent,
  cleanup: cleanupVoiceAgent,
};
