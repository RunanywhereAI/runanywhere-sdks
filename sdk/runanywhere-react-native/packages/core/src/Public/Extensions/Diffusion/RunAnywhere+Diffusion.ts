/**
 * RunAnywhere+Diffusion.ts
 *
 * Diffusion (on-device image generation) extension for the RunAnywhere core
 * SDK. Mirrors the Swift facade `RunAnywhere+Diffusion.swift` +
 * `CppBridge+Diffusion.swift`, adapted to the RN core Nitro bridge.
 *
 * Loading flows through the canonical lifecycle: load a diffusion model first
 * via `RunAnywhere.loadModel(ModelLoadRequest{ category: IMAGE_GENERATION,
 * component: DIFFUSION })`. There is NO dedicated diffusion load API — the
 * generation call is handle-free (`diffusionGenerateLifecycleProto` →
 * `rac_diffusion_generate_lifecycle_proto` resolves the loaded model in
 * commons, exactly like the VLM / embeddings lifecycle paths).
 *
 * Apple-only: the DIFFUSION primitive is served exclusively by the Apple
 * CoreML Stable-Diffusion backend. On non-Apple platforms (Android) these
 * entry points throw a clear "only supported on Apple/CoreML platforms"
 * `SDKException` and never crash.
 *
 * Streaming note (parity with Swift `CppBridge+Diffusion`): commons' native
 * diffusion stream kickoff (`rac_diffusion_stream_start_proto`) is a documented
 * `RAC_ERROR_NOT_IMPLEMENTED` stub, so `generateImageStream` adapts the real,
 * working lifecycle generate into a stream: it emits `STARTED`, runs the
 * CoreML pipeline, then emits a terminal `COMPLETED` (carrying the full
 * `DiffusionResult`) or `ERROR`. The generated image is genuine — only
 * intermediate per-step progress is unavailable until commons wires the
 * kickoff. When it does, this facade upgrades with no public API change.
 */

import { Platform } from 'react-native';

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../../native';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { ErrorCategory, ErrorCode } from '@runanywhere/proto-ts/errors';
import {
  DiffusionGenerationOptions as DiffusionGenerationOptionsMessage,
  DiffusionGenerationRequest,
  DiffusionResult as DiffusionResultMessage,
  DiffusionStreamEvent as DiffusionStreamEventMessage,
  DiffusionStreamEventKind,
} from '@runanywhere/proto-ts/diffusion_options';
import type {
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionStreamEvent,
} from '@runanywhere/proto-ts/diffusion_options';

const logger = new SDKLogger('RunAnywhere.Diffusion');
let requestCounter = 0;

/**
 * In-flight image generation cancellation token. `cancelImageGeneration`
 * flips `cancelled`, which suppresses the terminal stream event — mirroring
 * Swift's `activeStreamTask?.cancel()`. The single CoreML `generate` call
 * cannot be interrupted mid-flight, so cancellation takes effect at the next
 * checkpoint (before the terminal event is emitted).
 */
let activeGeneration: { cancelled: boolean } | null = null;

/**
 * Apple gate: the DIFFUSION primitive is served only by the Apple CoreML
 * Stable-Diffusion backend. Throw a clear, typed error on Android/other
 * platforms rather than making a native call that would fail obscurely.
 */
function ensureApplePlatform(): void {
  if (Platform.OS !== 'ios' && Platform.OS !== 'macos') {
    throw SDKException.of(
      ErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
      'Image generation (diffusion) is only supported on Apple/CoreML platforms',
      { category: ErrorCategory.ERROR_CATEGORY_COMPONENT }
    );
  }
}

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function nextRequestId(): string {
  requestCounter += 1;
  return `rn-diffusion-${Date.now()}-${requestCounter}`;
}

/**
 * Build a `DiffusionGenerationRequest`. Options pass through `fromPartial` so
 * every unset numeric knob keeps its proto default (0), which commons/CoreML
 * interpret as "use the variant default" (resolution, step count, guidance
 * scale, scheduler). `prompt` is the only required field.
 */
function encodeRequest(options: Partial<DiffusionGenerationOptions>): ArrayBuffer {
  const request = DiffusionGenerationRequest.fromPartial({
    requestId: nextRequestId(),
    options: DiffusionGenerationOptionsMessage.fromPartial({
      ...options,
      prompt: options?.prompt ?? '',
    }),
    metadata: {},
  });
  return encodeProtoMessage(request, DiffusionGenerationRequest);
}

function decodeResult(buffer: ArrayBuffer): DiffusionResult {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('diffusionGenerateLifecycleProto');
  }
  return DiffusionResultMessage.decode(bytes);
}

/**
 * Generate an image from the lifecycle-loaded diffusion model.
 *
 * Matches iOS: `RunAnywhere.generateImage(_:)`. Load a diffusion model first
 * via `loadModel(ModelLoadRequest{ category: IMAGE_GENERATION })`.
 */
export async function generateImage(
  options: Partial<DiffusionGenerationOptions>
): Promise<DiffusionResult> {
  // Apple gate first — mirror Swift's Apple-only DIFFUSION backend.
  ensureApplePlatform();
  // Swift parity: guard isInitialized (RunAnywhere+Diffusion.swift:31-33).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+Diffusion.swift:34 gates on ensureServicesReady.
  await ensureServicesReady();
  const resultBytes = await native.diffusionGenerateLifecycleProto(
    encodeRequest(options)
  );
  return decodeResult(resultBytes);
}

/**
 * Stream typed diffusion events for an image generation.
 *
 * Yields `STARTED` → terminal `COMPLETED` (carrying the full `DiffusionResult`)
 * or `ERROR`. Matches iOS: `RunAnywhere.generateImageStream(_:)`.
 *
 * Hermes-safe: callers MUST iterate via `iterator.next()` (see CLAUDE.md) —
 * `for await...of` is unsupported on Nitro async iterables.
 */
export async function generateImageStream(
  options: Partial<DiffusionGenerationOptions>
): Promise<AsyncIterable<DiffusionStreamEvent>> {
  ensureApplePlatform();
  requireInitialized();
  const native = ensureNative();
  await ensureServicesReady();
  const requestBytes = encodeRequest(options);

  return {
    [Symbol.asyncIterator](): AsyncIterator<DiffusionStreamEvent> {
      const token = { cancelled: false };
      activeGeneration = token;
      const queue: DiffusionStreamEvent[] = [];
      let resolver:
        | ((value: IteratorResult<DiffusionStreamEvent>) => void)
        | null = null;
      let done = false;
      let started = false;

      const finish = (): void => {
        done = true;
        if (activeGeneration === token) activeGeneration = null;
        if (resolver) {
          resolver({
            value: undefined as unknown as DiffusionStreamEvent,
            done: true,
          });
          resolver = null;
        }
      };

      const push = (event: DiffusionStreamEvent): void => {
        if (resolver) {
          resolver({ value: event, done: false });
          resolver = null;
        } else {
          queue.push(event);
        }
      };

      const start = (): void => {
        if (started) return;
        started = true;

        push(
          DiffusionStreamEventMessage.fromPartial({
            kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_STARTED,
          })
        );

        native
          .diffusionGenerateLifecycleProto(requestBytes)
          .then((resultBytes: ArrayBuffer) => {
            // Honour a consumer/cancel that arrived while the native pipeline
            // was running: skip the terminal event (Swift Task.isCancelled).
            if (token.cancelled) {
              finish();
              return;
            }
            push(
              DiffusionStreamEventMessage.fromPartial({
                kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_COMPLETED,
                result: decodeResult(resultBytes),
              })
            );
            finish();
          })
          .catch((err: Error) => {
            if (!token.cancelled) {
              logger.warning(
                `diffusionGenerateLifecycleProto rejected: ${err.message}`
              );
              push(
                DiffusionStreamEventMessage.fromPartial({
                  kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR,
                  errorMessage: err.message,
                })
              );
            }
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<DiffusionStreamEvent>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (done) {
            return {
              value: undefined as unknown as DiffusionStreamEvent,
              done: true,
            };
          }
          return new Promise<IteratorResult<DiffusionStreamEvent>>(
            (resolve) => {
              resolver = resolve;
            }
          );
        },
        async return(): Promise<IteratorResult<DiffusionStreamEvent>> {
          token.cancelled = true;
          finish();
          return {
            value: undefined as unknown as DiffusionStreamEvent,
            done: true,
          };
        },
      };
    },
  };
}

/**
 * Cancel the current (streaming) image generation.
 *
 * Matches iOS: `RunAnywhere.cancelImageGeneration()`. Flags the in-flight
 * generation so the terminal stream event is suppressed. The single CoreML
 * generate call cannot be interrupted mid-flight; cancellation takes effect at
 * the next checkpoint.
 */
export async function cancelImageGeneration(): Promise<void> {
  if (activeGeneration) {
    activeGeneration.cancelled = true;
    activeGeneration = null;
  }
}
