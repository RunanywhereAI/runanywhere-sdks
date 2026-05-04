/**
 * RunAnywhere+Convenience.ts
 *
 * Top-level convenience verbs that mirror Swift's `RunAnywhere.chat / generate /
 * transcribe / synthesize / speak / detectSpeech / generateStructured` static
 * methods. Each one is a thin shim that dispatches to the appropriate
 * backend provider via `ExtensionPoint`, so consumers no longer need to
 * `import { TextGeneration } from '@runanywhere/web-llamacpp'` etc.
 *
 * Reference (Swift): RunAnywhere+TextGeneration.swift / RunAnywhere+STT.swift /
 *                    RunAnywhere+TTS.swift / RunAnywhere+VAD.swift /
 *                    RunAnywhere+StructuredOutput.swift
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import { AudioPlayback } from '../../Infrastructure/AudioPlayback';
import type {
  LLMProvider,
  STTProvider,
  TTSProvider,
  VADProvider,
} from '../../Infrastructure/ProviderTypes';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import type {
  LLMStreamingResult,
  STTTranscriptionResult,
  STTTranscribeOptions,
  TTSSynthesisResult,
  TTSSynthesizeOptions,
  SpeechActivityCallback,
} from '../../types/index';

const logger = new SDKLogger('Convenience');

// Shared singleton playback for `speak()`.
let _playback: AudioPlayback | null = null;
function getPlayback(): AudioPlayback {
  if (_playback == null) _playback = new AudioPlayback();
  return _playback;
}

// Shared VAD speech-activity unsubscriber so setVADCallback is replaceable.
let _vadUnsubscribe: (() => void) | null = null;

// ---------------------------------------------------------------------------
// LLM
// ---------------------------------------------------------------------------

function requireLLM(): LLMProvider {
  return ExtensionPoint.requireProvider('llm', '@runanywhere/web-llamacpp');
}

/**
 * Simple chat — equivalent to Swift `RunAnywhere.chat(prompt)`.
 * Returns just the generated text.
 */
export async function chat(
  prompt: string,
  options?: Partial<LLMGenerationOptions>,
): Promise<string> {
  const result = await generate(prompt, options);
  return result.text;
}

/**
 * Generate text — equivalent to Swift `RunAnywhere.generate(prompt, options)`.
 */
export async function generate(
  prompt: string,
  options: Partial<LLMGenerationOptions> = {},
): Promise<LLMGenerationResult> {
  const llm = requireLLM();
  if (typeof llm.generate === 'function') {
    return llm.generate(prompt, options);
  }
  // Fallback: drain the streaming API into a single result.
  const streaming = await llm.generateStream(prompt, {
    maxTokens: options.maxTokens,
    temperature: options.temperature,
    systemPrompt: options.systemPrompt,
  });
  for await (const _chunk of streaming.stream) { /* drain */ }
  return streaming.result;
}

/**
 * Streaming generate — equivalent to Swift `RunAnywhere.generateStream`.
 */
export async function generateStream(
  prompt: string,
  options: Partial<LLMGenerationOptions> = {},
): Promise<LLMStreamingResult> {
  const llm = requireLLM();
  return llm.generateStream(prompt, {
    maxTokens: options.maxTokens,
    temperature: options.temperature,
    systemPrompt: options.systemPrompt,
  });
}

// ---------------------------------------------------------------------------
// STT
// ---------------------------------------------------------------------------

function requireSTT(): STTProvider {
  return ExtensionPoint.requireProvider('stt', '@runanywhere/web-onnx');
}

/**
 * Transcribe audio — equivalent to Swift `RunAnywhere.transcribe(audioData)`.
 *
 * @param audio Float32Array PCM samples (mono, defaults to 16 kHz)
 *              or a `File` (any encoding; auto-decoded).
 */
export async function transcribe(
  audio: Float32Array | File,
  options?: STTTranscribeOptions,
): Promise<STTTranscriptionResult> {
  const stt = requireSTT();
  if (audio instanceof Float32Array) {
    return stt.transcribe(audio, options);
  }
  // File path: we delegate via the extended STT singleton interface.
  const sttExt = stt as STTProvider & {
    transcribeFile?: (file: File, opts?: STTTranscribeOptions) => Promise<STTTranscriptionResult>;
  };
  if (typeof sttExt.transcribeFile === 'function') {
    return sttExt.transcribeFile(audio, options);
  }
  // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
  throw SDKException.backendNotAvailable(
    'transcribe(File)',
    'STT provider does not implement transcribeFile.',
  );
}

// ---------------------------------------------------------------------------
// TTS
// ---------------------------------------------------------------------------

function requireTTS(): TTSProvider {
  return ExtensionPoint.requireProvider('tts', '@runanywhere/web-onnx');
}

/**
 * Synthesize text into PCM audio — equivalent to Swift
 * `RunAnywhere.synthesize(text, options)`.
 */
export async function synthesize(
  text: string,
  options?: TTSSynthesizeOptions,
): Promise<TTSSynthesisResult> {
  return requireTTS().synthesize(text, options);
}

/**
 * Synthesize and play through the browser audio output — equivalent to Swift
 * `RunAnywhere.speak(text, options)`. Resolves once playback completes.
 *
 * Uses the SDK's bundled `AudioPlayback` helper (Web Audio API) so callers
 * don't need to wire AudioContext themselves.
 */
export async function speak(
  text: string,
  options?: TTSSynthesizeOptions,
): Promise<void> {
  const result = await synthesize(text, options);
  const playback = getPlayback();
  await playback.play(result.audioData, result.sampleRate);
}

/** Whether the SDK is currently playing TTS audio (Swift `RunAnywhere.isSpeaking`). */
export function isSpeaking(): boolean {
  return _playback?.isPlaying ?? false;
}

/** Stop any in-progress TTS playback (Swift `RunAnywhere.stopSpeaking`). */
export function stopSpeaking(): void {
  _playback?.stop();
}

// ---------------------------------------------------------------------------
// VAD
// ---------------------------------------------------------------------------

function getVAD(): VADProvider | undefined {
  return ExtensionPoint.getProvider('vad');
}

function requireVAD(): VADProvider {
  return ExtensionPoint.requireProvider('vad', '@runanywhere/web-onnx');
}

/**
 * Run VAD on a single audio buffer — equivalent to Swift
 * `RunAnywhere.detectSpeech(in: samples)`. Returns whether speech is present.
 */
export function detectSpeech(audio: Float32Array): boolean {
  return requireVAD().processSamples(audio);
}

/**
 * Register a speech-activity callback — equivalent to Swift
 * `RunAnywhere.setVADSpeechActivityCallback(_:)`. Replaces the previous
 * callback if any. Pass `null` to clear.
 */
export function setVADCallback(callback: SpeechActivityCallback | null): void {
  // Tear down any existing subscription.
  if (_vadUnsubscribe) {
    try { _vadUnsubscribe(); } catch { /* ignore */ }
    _vadUnsubscribe = null;
  }
  if (callback != null) {
    _vadUnsubscribe = requireVAD().onSpeechActivity(callback);
  }
}

/** Mirror of Swift `RunAnywhere.startVAD()`. Currently a no-op — the VAD
 *  driver only processes audio during `processSamples()` calls. Reserved for
 *  future continuous-mic-loop support. */
export async function startVAD(): Promise<void> {
  // No-op: the Web VAD is sample-driven; the consumer pumps audio in.
  if (!getVAD()) {
    // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
    throw SDKException.backendNotAvailable(
      'startVAD',
      'No VAD provider registered. Install and register @runanywhere/web-onnx.',
    );
  }
  logger.debug('startVAD() — VAD provider ready');
}

/** Mirror of Swift `RunAnywhere.stopVAD()`. Currently resets the VAD state. */
export async function stopVAD(): Promise<void> {
  const vad = getVAD();
  if (vad) vad.reset();
}

/** Mirror of Swift `RunAnywhere.cleanupVAD()`. Releases VAD resources. */
export async function cleanupVAD(): Promise<void> {
  const vad = getVAD();
  if (vad) vad.cleanup();
  if (_vadUnsubscribe) {
    try { _vadUnsubscribe(); } catch { /* ignore */ }
    _vadUnsubscribe = null;
  }
}

/** Whether the VAD model is loaded (Swift `RunAnywhere.isVADReady`). */
export function isVADReady(): boolean {
  return getVAD()?.isInitialized ?? false;
}

// ---------------------------------------------------------------------------
// Structured Output
// ---------------------------------------------------------------------------

/**
 * Schema-driven structured output — Web equivalent of Swift's
 * `RunAnywhere.generateStructured<T: Generatable>`.
 *
 * TypeScript has no Codable/Generatable equivalent, so we accept either:
 *   - A JSON Schema string + a generic type parameter (caller asserts T)
 *   - A type-tagged object whose runtime parser the caller provides
 *
 * The native LLM service owns schema prompting, extraction, and validation.
 * Web only deserializes the generated JSON payload into the caller's type.
 */
export async function generateStructured<T = unknown>(
  prompt: string,
  schema: { jsonSchema: string; parse?: (text: string) => T },
  options?: Partial<LLMGenerationOptions>,
): Promise<T> {
  const result = await generate(prompt, {
    ...options,
    jsonSchema: schema.jsonSchema,
  });
  if (result.structuredOutputValidation && !result.structuredOutputValidation.isValid) {
    throw SDKException.generationFailed(
      result.structuredOutputValidation.errorMessage ?? 'Structured output validation failed',
    );
  }
  const text = result.jsonOutput
    ?? result.structuredOutputValidation?.extractedJson
    ?? result.text;
  if (typeof schema.parse === 'function') {
    return schema.parse(text);
  }
  try {
    return JSON.parse(text) as T;
  } catch (err) {
    throw SDKException.generationFailed(
      `Structured output JSON parse failed: ${(err as Error).message}; raw: ${text.slice(0, 200)}`,
    );
  }
}
