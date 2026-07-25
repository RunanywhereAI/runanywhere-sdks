import {
  DiarizationRequest,
  DiarizationResult,
  type DiarizationRequest as ProtoDiarizationRequest,
  type DiarizationResult as ProtoDiarizationResult,
} from '@runanywhere/proto-ts/diarization';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

/**
 * Typed bridge for lifecycle-owned standalone speaker diarization.
 *
 * The provider and its model are owned by the shared commons lifecycle. Web
 * callers therefore never receive or manufacture a native handle; the
 * serialized request is routed to the model already loaded in the speaker
 * diarization category. Mirrors {@link SegmentationProtoAdapter} (handle-free,
 * lifecycle-owned) and the Swift `CppBridge.Diarization.diarize` path.
 */
export class DiarizationProtoAdapter {
  static tryDefault(): DiarizationProtoAdapter | null {
    const module = adapterState.modalitySlots.diarization;
    return module ? new DiarizationProtoAdapter(module) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsLifecycleProtoDiarization(): boolean {
    return missingExports(
      this.module,
      ['_rac_diarization_diarize_lifecycle_proto'],
    ).length === 0;
  }

  async diarizeLifecycle(
    request: ProtoDiarizationRequest,
  ): Promise<ProtoDiarizationResult | null> {
    if (!ensureExports(this.module, 'diarization.diarizeLifecycle', [
      '_rac_diarization_diarize_lifecycle_proto',
    ])) {
      return null;
    }

    return this.bridge().withEncodedRequestAsync(
      request,
      DiarizationRequest,
      DiarizationResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_diarization_diarize_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_diarization_diarize_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_diarization_diarize_lifecycle_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
