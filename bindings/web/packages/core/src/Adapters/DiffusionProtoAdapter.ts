import {
  DiffusionGenerationOptions,
  DiffusionGenerationRequest,
  DiffusionProgress,
  DiffusionResult,
  type DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  type DiffusionGenerationRequest as ProtoDiffusionGenerationRequest,
  type DiffusionProgress as ProtoDiffusionProgress,
  type DiffusionResult as ProtoDiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  withOptionalCallback,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes.js';

/**
 * Thin proto-byte adapter for diffusion — mirrors Swift/Kotlin by calling the
 * handle-free lifecycle ABI (`rac_diffusion_generate_lifecycle_proto`).
 */
export class DiffusionProtoAdapter {
  static tryDefault(): DiffusionProtoAdapter | null {
    const mod = adapterState.modalitySlots.diffusion;
    return mod ? new DiffusionProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoDiffusion(): boolean {
    return missingExports(this.module, [
      '_rac_diffusion_generate_lifecycle_proto',
      '_rac_diffusion_cancel_proto',
    ]).length === 0;
  }

  async generateLifecycle(
    request: ProtoDiffusionGenerationRequest,
  ): Promise<ProtoDiffusionResult | null> {
    if (!ensureExports(this.module, 'diffusion.generateLifecycle', [
      '_rac_diffusion_generate_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequestAsync(
      request,
      DiffusionGenerationRequest,
      DiffusionResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_diffusion_generate_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_diffusion_generate_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_diffusion_generate_lifecycle_proto',
    );
  }

  /**
   * Progress-capable path keeps the legacy handle export when present so
   * engines that already emit step callbacks remain usable. Prefer
   * {@link generateLifecycle} for Swift/Kotlin parity.
   */
  generateWithProgress(
    handle: number,
    options: ProtoDiffusionGenerationOptions,
    onProgress: ProtoEventHandler<ProtoDiffusionProgress> | null,
  ): ProtoDiffusionResult | null {
    if (!ensureExports(this.module, 'diffusion.generateWithProgress', [
      '_rac_diffusion_generate_with_progress_proto',
    ])) {
      return null;
    }
    const optionsBytes = DiffusionGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return withOptionalCallback(
      this.module,
      DiffusionProgress,
      onProgress,
      'rac_diffusion_generate_with_progress_proto',
      (callbackPtr) => bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          DiffusionResult,
          (outResult) => this.module._rac_diffusion_generate_with_progress_proto!(
            handle,
            optionsPtr,
            optionsSize,
            callbackPtr,
            0,
            outResult,
          ),
          'rac_diffusion_generate_with_progress_proto',
        )
      )),
    );
  }

  cancel(handle: number): boolean {
    if (!ensureExports(this.module, 'diffusion.cancel', ['_rac_diffusion_cancel_proto'])) {
      return false;
    }
    const rc = this.module._rac_diffusion_cancel_proto!(handle);
    if (rc !== 0) logger.warning(`rac_diffusion_cancel_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
