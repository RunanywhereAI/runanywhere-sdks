/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Top-level Voice Agent C-ABI parity surface. Mirrors Swift's
 * `RunAnywhere.processVoiceTurn`, `voiceAgentTranscribe`,
 * `voiceAgentGenerateResponse`, `voiceAgentSynthesizeSpeech`, and
 * `cleanupVoiceAgent` static verbs.
 *
 * Today, the Web SDK has two unrelated voice-agent paths:
 *   1. `VoicePipeline` — TS-side STT->LLM->TTS composition (already shipped).
 *   2. `VoiceAgentStreamAdapter` — proto-byte stream over the C voice-agent.
 *
 * This module is the third path: a one-shot symmetric API matching the
 * other SDKs. By default it composes STT/LLM/TTS via existing providers
 * registered through `ExtensionPoint`. A backend can override by calling
 * `setVoiceAgentProvider(...)` with a tighter implementation (e.g. once
 * the `rac_voice_agent_*` WASM exports are built).
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import type { LLMProvider, STTProvider, TTSProvider } from '../../Infrastructure/ProviderTypes';
import type {
  VoiceAgentConfig,
  VoiceAgentComponentStates,
  VoiceAgentResult,
} from '../../types/index';
import { ComponentLoadState } from '../../types/index';

const logger = new SDKLogger('VoiceAgent');

/**
 * Optional backend-supplied voice-agent provider. When set, the public verbs
 * delegate directly. When unset, calls compose STT/LLM/TTS providers.
 */
export interface VoiceAgentProvider {
  initializeVoiceAgent?(config: VoiceAgentConfig): Promise<void>;
  initializeVoiceAgentWithLoadedModels?(): Promise<void>;
  isVoiceAgentReady?(): Promise<boolean> | boolean;
  getVoiceAgentComponentStates?(): Promise<VoiceAgentComponentStates> | VoiceAgentComponentStates;
  processVoiceTurn?(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult>;
  voiceAgentTranscribe?(audio: Float32Array | Uint8Array): Promise<string>;
  voiceAgentGenerateResponse?(prompt: string): Promise<string>;
  voiceAgentSynthesizeSpeech?(text: string): Promise<Float32Array>;
  cleanupVoiceAgent?(): Promise<void> | void;
}

let _provider: VoiceAgentProvider | null = null;
let _config: VoiceAgentConfig | null = null;

export function setVoiceAgentProvider(provider: VoiceAgentProvider | null): void {
  _provider = provider;
}

// ---------------------------------------------------------------------------
// Helpers — compose-mode dispatch via STT/LLM/TTS providers
// ---------------------------------------------------------------------------

function getSTT(): STTProvider | undefined {
  return ExtensionPoint.getProvider('stt');
}
function getLLM(): LLMProvider | undefined {
  return ExtensionPoint.getProvider('llm');
}
function getTTS(): TTSProvider | undefined {
  return ExtensionPoint.getProvider('tts');
}

function toFloat32(audio: Float32Array | Uint8Array): Float32Array {
  if (audio instanceof Float32Array) return audio;
  // Treat Uint8Array as raw 16-bit PCM little-endian; decode to Float32.
  const samples = new Float32Array(audio.length / 2);
  const view = new DataView(audio.buffer, audio.byteOffset, audio.byteLength);
  for (let i = 0; i < samples.length; i++) {
    samples[i] = view.getInt16(i * 2, true) / 32768;
  }
  return samples;
}

function componentLoadStateFromBoolean(loaded: boolean): ComponentLoadState {
  return loaded
    ? ComponentLoadState.COMPONENT_LOAD_STATE_LOADED
    : ComponentLoadState.COMPONENT_LOAD_STATE_NOT_LOADED;
}

// ---------------------------------------------------------------------------
// Public API — Swift-symmetric verbs.
// ---------------------------------------------------------------------------

/**
 * Initialize the voice agent. Stores the config and ensures STT/LLM/TTS
 * providers are present. If a backend `VoiceAgentProvider` is registered,
 * delegates directly.
 */
export async function initializeVoiceAgent(config: VoiceAgentConfig): Promise<void> {
  if (_provider?.initializeVoiceAgent) {
    return _provider.initializeVoiceAgent(config);
  }
  _config = config;
  // Compose-mode: just verify providers exist; concrete loaders are the
  // application's responsibility (loadModel via TextGeneration / STT.loadModel etc.).
  if (!getSTT() || !getLLM() || !getTTS()) {
    throw SDKException.backendNotAvailable(
      'VoiceAgent',
      'STT/LLM/TTS providers must be registered (via @runanywhere/web-llamacpp + ' +
      '@runanywhere/web-onnx) before initializing the voice agent.',
    );
  }
  logger.info('VoiceAgent initialized (compose-mode)');
}

export async function initializeVoiceAgentWithLoadedModels(): Promise<void> {
  if (_provider?.initializeVoiceAgentWithLoadedModels) {
    return _provider.initializeVoiceAgentWithLoadedModels();
  }
  return initializeVoiceAgent({});
}

export async function isVoiceAgentReady(): Promise<boolean> {
  if (_provider?.isVoiceAgentReady) {
    return Promise.resolve(_provider.isVoiceAgentReady());
  }
  const states = await getVoiceAgentComponentStates();
  return states.ready;
}

export async function getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> {
  if (_provider?.getVoiceAgentComponentStates) {
    return Promise.resolve(_provider.getVoiceAgentComponentStates());
  }
  const stt = getSTT() as (STTProvider & { isModelLoaded?: boolean; modelId?: string }) | undefined;
  const llm = getLLM() as (LLMProvider & { isModelLoaded?: boolean }) | undefined;
  const tts = getTTS() as (TTSProvider & { isVoiceLoaded?: boolean; voiceId?: string }) | undefined;

  const sttState = componentLoadStateFromBoolean(stt?.isModelLoaded ?? false);
  const llmState = componentLoadStateFromBoolean(llm?.isModelLoaded ?? false);
  const ttsState = componentLoadStateFromBoolean(tts?.isVoiceLoaded ?? false);
  const vadState = ComponentLoadState.COMPONENT_LOAD_STATE_NOT_LOADED;

  const ready =
    sttState === ComponentLoadState.COMPONENT_LOAD_STATE_LOADED &&
    llmState === ComponentLoadState.COMPONENT_LOAD_STATE_LOADED &&
    ttsState === ComponentLoadState.COMPONENT_LOAD_STATE_LOADED;

  return { sttState, llmState, ttsState, vadState, ready, anyLoading: false };
}

export async function areAllVoiceComponentsReady(): Promise<boolean> {
  return (await getVoiceAgentComponentStates()).ready;
}

/** Mirror Swift `RunAnywhere.processVoiceTurn(audioData) -> VoiceAgentResult`. */
export async function processVoiceTurn(
  audio: Float32Array | Uint8Array,
): Promise<VoiceAgentResult> {
  if (_provider?.processVoiceTurn) {
    return _provider.processVoiceTurn(audio);
  }
  // Compose mode: STT -> LLM -> TTS. Each step throws if its provider is absent.
  const samples = toFloat32(audio);
  const transcription = await voiceAgentTranscribe(samples);
  const assistantResponse = transcription
    ? await voiceAgentGenerateResponse(transcription)
    : '';
  let synthesizedAudio: Uint8Array | undefined;
  if (assistantResponse) {
    const tts = getTTS();
    if (tts) {
      const synth = await tts.synthesize(assistantResponse);
      // Proto carries audio as raw bytes (PCM-F32-LE per AudioFrameEvent
      // conventions). Re-pack the Float32Array as a Uint8Array view.
      synthesizedAudio = new Uint8Array(synth.audioData.buffer);
    }
  }
  return {
    speechDetected: transcription.length > 0,
    transcription: transcription || undefined,
    assistantResponse: assistantResponse || undefined,
    synthesizedAudio,
  };
}

export async function voiceAgentTranscribe(
  audio: Float32Array | Uint8Array,
): Promise<string> {
  if (_provider?.voiceAgentTranscribe) {
    return _provider.voiceAgentTranscribe(audio);
  }
  const stt = getSTT();
  if (!stt) {
    throw SDKException.backendNotAvailable(
      'voiceAgentTranscribe',
      'No STT provider registered. Install and register @runanywhere/web-onnx.',
    );
  }
  const result = await stt.transcribe(toFloat32(audio));
  return (result.text ?? '').trim();
}

export async function voiceAgentGenerateResponse(prompt: string): Promise<string> {
  if (_provider?.voiceAgentGenerateResponse) {
    return _provider.voiceAgentGenerateResponse(prompt);
  }
  const llm = getLLM();
  if (!llm) {
    throw SDKException.backendNotAvailable(
      'voiceAgentGenerateResponse',
      'No LLM provider registered. Install and register @runanywhere/web-llamacpp.',
    );
  }
  if (typeof llm.generate === 'function') {
    const r = await llm.generate(prompt, {
      systemPrompt: _config?.systemPrompt ?? undefined,
    });
    return r.text;
  }
  // Fallback: drain the streaming API.
  const streaming = await llm.generateStream(prompt, {
    systemPrompt: _config?.systemPrompt,
  });
  let text = '';
  for await (const chunk of streaming.stream) text += chunk;
  return text;
}

export async function voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array> {
  if (_provider?.voiceAgentSynthesizeSpeech) {
    return _provider.voiceAgentSynthesizeSpeech(text);
  }
  const tts = getTTS();
  if (!tts) {
    throw SDKException.backendNotAvailable(
      'voiceAgentSynthesizeSpeech',
      'No TTS provider registered. Install and register @runanywhere/web-onnx.',
    );
  }
  const synth = await tts.synthesize(text);
  return synth.audioData as unknown as Float32Array;
}

export async function cleanupVoiceAgent(): Promise<void> {
  if (_provider?.cleanupVoiceAgent) {
    await Promise.resolve(_provider.cleanupVoiceAgent());
  }
  _config = null;
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
  cleanup: cleanupVoiceAgent,
};
