/**
 * v2 verb names kept for one release as thin forwarders.
 *
 * Each one does exactly what it used to do and points at its v3 replacement.
 * They are spread onto the public `RunAnywhere` object in `index.ts` and will
 * be deleted in the release after next.
 */

import type { ModelCategory, ModelInfo } from '@runanywhere/proto-ts/model_types';
import type { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import { SDKCore } from '../SDKCore.js';
import type { ToolExecutor } from '../Extensions/RunAnywhere+ToolCalling.js';
import { AudioInput } from './Inputs.js';
import type { AudioInput as AudioInputValue, ImageInput } from './Inputs.js';
import type { LlmOptions, ModelFilter, SttOptions, TtsOptions } from './Options.js';
import type { GenerationEvent } from './Events.js';
import type { Audio, GenerationResult, Transcription } from './Results.js';
import { llm } from './Namespaces/llm.js';
import { models } from './Namespaces/models.js';
import { stt } from './Namespaces/stt.js';
import { tts } from './Namespaces/tts.js';
import { vlm } from './Namespaces/vlm.js';

/** One-shot iterable over a single audio payload, for the old buffer-shaped verbs. */
async function* singleChunk(audio: AudioInputValue): AsyncGenerator<AudioInputValue> {
  yield audio;
}

export const deprecatedForwarders = {
  /** @deprecated Use `RunAnywhere.llm.generate(prompt, options)`. */
  generate(options: LlmOptions & { prompt: string }): Promise<GenerationResult> {
    const { prompt, ...rest } = options;
    return llm.generate(prompt, rest);
  },

  /** @deprecated Use `RunAnywhere.llm.generateStream(prompt, options)`. */
  generateStream(options: LlmOptions & { prompt: string }): AsyncIterable<GenerationEvent> {
    const { prompt, ...rest } = options;
    return llm.generateStream(prompt, rest);
  },

  /** @deprecated Use `RunAnywhere.llm.tools.register(tool, executor)`. */
  registerTool(tool: ToolDefinition, executor: ToolExecutor): void {
    llm.tools.register(tool, executor);
  },

  /** @deprecated Use `RunAnywhere.stt.transcribe(audio, options)`. */
  transcribe(audio: AudioInputValue, options?: SttOptions): Promise<Transcription> {
    return stt.transcribe(audio, options);
  },

  /**
   * @deprecated Use `RunAnywhere.stt.transcribeStream(chunks, options)`, which
   * takes an async iterable of chunks instead of a single buffer.
   */
  transcribeStream(audio: AudioInputValue, options?: SttOptions) {
    return stt.transcribeStream(singleChunk(audio), options);
  },

  /** @deprecated Use `RunAnywhere.tts.synthesize(text, options)`. */
  synthesize(text: string, options?: TtsOptions): Promise<Audio> {
    return tts.synthesize(text, options);
  },

  /** @deprecated Use `RunAnywhere.tts.speak(text, options)`. */
  speak(text: string, options?: TtsOptions): Promise<void> {
    return tts.speak(text, options);
  },

  /** @deprecated Use `RunAnywhere.tts.stop()`. */
  stopSpeaking(): void {
    tts.stop();
  },

  /** @deprecated Use `RunAnywhere.tts.stop()`. */
  stopSynthesis(): void {
    tts.stop();
  },

  /** @deprecated Use `RunAnywhere.vlm.generate(image, prompt, options)`. */
  processImage(image: ImageInput, prompt: string, options?: LlmOptions): Promise<GenerationResult> {
    return vlm.generate(image, prompt, options);
  },

  /** @deprecated Use `RunAnywhere.vlm.generateStream(image, prompt, options)`. */
  processImageStream(image: ImageInput, prompt: string, options?: LlmOptions) {
    return vlm.generateStream(image, prompt, options);
  },

  /** @deprecated Use `RunAnywhere.models.list(filter)`. */
  listModels(filter?: ModelFilter): ModelInfo[] {
    return models.list(filter);
  },

  /** @deprecated Use `RunAnywhere.models.get(id)`. */
  getModel(id: string): ModelInfo | null {
    return models.get(id);
  },

  /** @deprecated Use `RunAnywhere.models.load(id, options)`. */
  loadModel(id: string): Promise<void> {
    return models.load(id);
  },

  /** @deprecated Use `RunAnywhere.models.unload(category)`. */
  unloadModel(category?: ModelCategory): Promise<void> {
    return models.unload(category);
  },

  /** @deprecated Use `RunAnywhere.models.delete(id)`. */
  deleteModel(id: string): Promise<void> {
    return models.delete(id);
  },

  /** @deprecated Use `RunAnywhere.storage.refresh()`. */
  refreshModelRegistry(): Promise<number> {
    return SDKCore.hydrateModelRegistry();
  },

  /** @deprecated `initialize()` now folds both phases; this is a no-op. */
  async completeServicesInitialization(): Promise<void> {
    await SDKCore.completeServicesInitialization();
  },

  /** @deprecated Use `RunAnywhere.reset()`. */
  shutdown(): Promise<void> {
    return SDKCore.reset();
  },
};

export { AudioInput };
