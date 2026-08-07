// The vlm namespace: image + prompt -> text over the proto-byte backend. The
// prompt rides in VLMGenerationOptions (the request carries only images).
// Auto-loads the multimodal model named in options.model, mirroring Swift.
import {
  VLMGenerationOptions,
  VLMGenerationRequest,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';

import type { RaBackend } from '../backend.js';
import type { LlmOptions } from '../options.js';
import { LLM_DEFAULTS } from '../options.js';
import { bridgeStream } from '../stream.js';
import type { GenerationEvent, GenerationResult, ImageInput } from '../types.js';
import type { ModelResolver } from './llm.js';

export interface VlmNamespace {
  generate(image: ImageInput, prompt: string, options?: LlmOptions): Promise<GenerationResult>;
  generateStream(image: ImageInput, prompt: string, options?: LlmOptions): AsyncIterableIterator<GenerationEvent>;
  cancel(): Promise<void>;
}

function toImage(image: ImageInput): ReturnType<typeof VLMImage.fromPartial> {
  if (image.kind === 'file') return VLMImage.fromPartial({ filePath: image.path });
  if (image.kind === 'bytes') return VLMImage.fromPartial({ encoded: image.data });
  return VLMImage.fromPartial({ rawRgb: image.data, width: image.width, height: image.height });
}

function requestBytes(image: ImageInput, prompt: string, o: LlmOptions = {}): Uint8Array {
  const options: Partial<VLMGenerationOptions> = {
    prompt,
    maxOutputTokens: o.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
    temperature: o.temperature ?? LLM_DEFAULTS.temperature,
    topP: o.topP ?? LLM_DEFAULTS.topP,
  };
  if (o.systemPrompt !== undefined) options.systemPrompt = o.systemPrompt;
  return VLMGenerationRequest.encode(
    VLMGenerationRequest.fromPartial({ images: [toImage(image)], options })
  ).finish();
}

function toResult(res: VLMResult): GenerationResult {
  return {
    text: res.text,
    thinking: '',
    toolCalls: [],
    finishReason: res.finishReason ?? '',
    metrics: {
      inputTokens: res.usage?.inputTokens ?? 0,
      outputTokens: res.usage?.outputTokens ?? 0,
      totalTokens: res.usage?.totalTokens ?? 0,
      timeToFirstTokenMs: res.timeToFirstTokenMs ?? 0,
      totalTimeMs: res.processingTimeMs ?? 0,
      tokensPerSecond: res.usage?.tokensPerSecond ?? 0,
    },
  };
}

export function createVlmNamespace(backend: RaBackend, resolve: ModelResolver): VlmNamespace {
  return {
    async generate(image, prompt, options) {
      if (options?.model) await resolve(options.model);
      return toResult(VLMResult.decode(await backend.vlmGenerate(requestBytes(image, prompt, options))));
    },
    generateStream(image, prompt, options) {
      let answer = '';
      return bridgeStream<GenerationEvent>(
        async (sink) => {
          if (options?.model) await resolve(options.model);
          return backend.vlmGenerateStream(requestBytes(image, prompt, options), (bytes) => {
            const ev = VLMStreamEvent.decode(bytes);
            if (ev.token) answer += ev.token;
            if (ev.isFinal) {
              const r = ev.result;
              sink.push({
                token: '',
                isFinal: true,
                isThinking: false,
                result: {
                  text: answer || r?.text || '',
                  thinking: '',
                  toolCalls: [],
                  finishReason: r?.finishReason || '',
                  metrics: {
                    inputTokens: r?.usage?.inputTokens || 0,
                    outputTokens: r?.usage?.outputTokens || 0,
                    totalTokens: r?.usage?.totalTokens || 0,
                    timeToFirstTokenMs: r?.timeToFirstTokenMs || 0,
                    totalTimeMs: r?.processingTimeMs || 0,
                    tokensPerSecond: r?.usage?.tokensPerSecond || ev.tokensPerSecond || 0,
                  },
                },
              });
            } else {
              sink.push({ token: ev.token, isFinal: false, isThinking: false });
            }
          });
        },
        () => backend.vlmCancel()
      );
    },
    async cancel() {
      await backend.vlmCancel();
    },
  };
}
