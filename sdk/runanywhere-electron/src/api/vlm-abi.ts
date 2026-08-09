// vlm-abi.ts — typed access to the commons VLM proto ABI.
//
// The vision counterpart of `llm-abi.ts`, and handle-free for the same reason:
// these read the model `rac_model_lifecycle_load_proto` put in commons' own
// store. The image travels inside the request as a `VLMImage`, so the three
// N-API image shapes the addon used to accept are gone; commons decodes the
// container and owns the vision-token budget.

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import { SDKException } from '../errors';
import {
  VLMGenerationRequest,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
  VLMStreamEventKind,
} from '../proto/vlm_options';
import type { RaBackend } from './backend';
import { bridgeStream } from './iter';
import { invokeProto } from './proto-abi';
import { requireOneOf } from './types';
import type { GenerationMetrics, ImageInput } from './types';

/** A request-ready image and whatever has to be cleaned up after the call. */
export interface MaterializedImage {
  image: VLMImage;
  release(): void;
}

/**
 * Map the public image shape onto the proto message.
 *
 * Encoded bytes are the interesting case. Commons refuses `VLMImage.data`
 * outright (`rac_proto_adapters.cpp:571` — "SDKs must decode containers to
 * RAW_RGB or supply a file path before calling C") and the llama.cpp backend
 * rejects `base64` for the same reason: neither the C ABI nor mtmd carries a
 * compressed container. The file-path arm does decode one, through
 * `mtmd_helper_bitmap_init_from_file`. So encoded bytes are spilled to a temp
 * file and passed as a path, which is platform I/O and therefore this layer's
 * job rather than a gap in commons. `release()` removes it.
 */
export function materializeImage(input: ImageInput): MaterializedImage {
  requireOneOf(input, ['path', 'bytes', 'rgb'], 'image');
  if (input.path) {
    return {
      image: VLMImage.fromPartial({ filePath: input.path, mediaType: mediaTypeFor(input.path) }),
      release: () => undefined,
    };
  }
  if (input.rgb) {
    if (!input.width || !input.height) {
      throw SDKException.validationFailed({
        fieldPath: 'image.width',
        message: 'raw RGB pixels need width and height',
      });
    }
    return {
      image: VLMImage.fromPartial({
        rawRgb: input.rgb,
        width: input.width,
        height: input.height,
      }),
      release: () => undefined,
    };
  }
  const file = path.join(
    os.tmpdir(),
    `runanywhere-vlm-${process.pid}-${Date.now()}-${spillCounter++}${extensionFor(
      input.bytes as Uint8Array
    )}`
  );
  fs.writeFileSync(file, input.bytes as Uint8Array);
  return {
    image: VLMImage.fromPartial({ filePath: file, mediaType: mediaTypeFor(file) }),
    release: () => {
      try {
        fs.rmSync(file, { force: true });
      } catch {
        // A leftover temp file is not worth failing a completed generation for.
      }
    },
  };
}

let spillCounter = 0;

// Enough of a sniff to name the file honestly; mtmd decides the real format
// from the bytes either way.
function extensionFor(bytes: Uint8Array): string {
  if (bytes.length > 3 && bytes[0] === 0x89 && bytes[1] === 0x50) return '.png';
  if (bytes.length > 11 && bytes[8] === 0x57 && bytes[9] === 0x45) return '.webp';
  return '.jpg';
}

function mediaTypeFor(file: string): string {
  const ext = file.slice(file.lastIndexOf('.') + 1).toLowerCase();
  if (ext === 'png') return 'image/png';
  if (ext === 'webp') return 'image/webp';
  return 'image/jpeg';
}

/**
 * `VLMResult.finish_reason` is the LLM domain's vocabulary as free text
 * ("stop" | "length" | "stop_sequence"), not the `FinishReason` enum the text
 * path carries, so it is mapped here rather than in the namespace.
 */
export function toPublicVlmFinishReason(reason: string): 'STOP' | 'LENGTH' | 'CANCELLED' {
  const normalized = reason.trim().toLowerCase();
  if (normalized === 'length') return 'LENGTH';
  if (normalized === 'cancelled' || normalized === 'canceled') return 'CANCELLED';
  return 'STOP';
}

/** Throughput and token accounting, straight out of the result. */
export function toPublicVlmMetrics(
  result: VLMResult,
  requestId: string,
  model: string
): GenerationMetrics {
  const usage = result.usage;
  return {
    inputTokens: usage?.inputTokens ?? 0,
    outputTokens: usage?.outputTokens ?? 0,
    timeToFirstTokenMs: usage?.ttftMs ?? 0,
    tokensPerSecond: usage?.decodeTokensPerSecond ?? 0,
    requestId,
    model,
  };
}

function orThrow<T extends { error?: { message?: string } | undefined }>(result: T): T {
  if (result.error) throw SDKException.fromProto(result.error as never);
  return result;
}

/** The commons VLM layer, bound to one backend. */
export class VlmAbi {
  constructor(private readonly backend: RaBackend) {}

  async generate(request: VLMGenerationRequest): Promise<VLMResult> {
    return orThrow(
      await invokeProto(
        (bytes) => this.backend.vlmGenerateProto(bytes),
        VLMGenerationRequest,
        request,
        VLMResult
      )
    );
  }

  /** One `VLMStreamEvent` per callback; breaking out cancels native work. */
  generateStream(request: VLMGenerationRequest): AsyncIterableIterator<VLMStreamEvent> {
    const bytes = VLMGenerationRequest.encode(request).finish();
    let inflight: Promise<void> | null = null;
    return bridgeStream<VLMStreamEvent>(
      (sink) => {
        inflight = this.backend.vlmStreamProto(bytes, (event) => {
          sink.push(VLMStreamEvent.decode(event));
        });
        return inflight;
      },
      async () => {
        await this.cancel();
        // Same reason as the LLM path: requesting a cancel is not the same as
        // the generation having stopped, and the next one must not inherit it.
        await inflight?.catch(() => undefined);
      }
    );
  }

  async cancel(): Promise<void> {
    await this.backend.vlmCancelProto();
  }
}

export { VLMGenerationRequest, VLMStreamEvent, VLMStreamEventKind };
export type { VLMResult };
