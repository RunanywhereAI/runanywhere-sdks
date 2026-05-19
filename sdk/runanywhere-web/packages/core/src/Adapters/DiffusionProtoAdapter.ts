import {
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  type DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  type DiffusionProgress as ProtoDiffusionProgress,
  type DiffusionResult as ProtoDiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  withOptionalCallback,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes';

export class DiffusionProtoAdapter {
  static tryDefault(): DiffusionProtoAdapter | null {
    const mod = adapterState.modalitySlots.diffusion;
    return mod ? new DiffusionProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoDiffusion(): boolean {
    return missingExports(this.module, [
      '_rac_diffusion_generate_proto',
      '_rac_diffusion_generate_with_progress_proto',
      '_rac_diffusion_cancel_proto',
    ]).length === 0;
  }

  generate(
    handle: number,
    options: ProtoDiffusionGenerationOptions,
  ): ProtoDiffusionResult | null {
    if (!ensureExports(this.module, 'diffusion.generate', ['_rac_diffusion_generate_proto'])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      options,
      DiffusionGenerationOptions,
      DiffusionResult,
      (optionsPtr, optionsSize, outResult) => (
        this.module._rac_diffusion_generate_proto!(
          handle,
          optionsPtr,
          optionsSize,
          outResult,
        )
      ),
      'rac_diffusion_generate_proto',
    );
  }

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
