import {
  SegmentationRequest,
  SegmentationResult,
  type SegmentationRequest as ProtoSegmentationRequest,
  type SegmentationResult as ProtoSegmentationResult,
} from '@runanywhere/proto-ts/segmentation';
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
 * Typed bridge for lifecycle-owned semantic segmentation.
 *
 * The provider and its model are owned by the shared commons lifecycle. Web
 * callers therefore never receive or manufacture a native handle; the
 * serialized request is routed to the model already loaded in the semantic
 * segmentation category.
 */
export class SegmentationProtoAdapter {
  static tryDefault(): SegmentationProtoAdapter | null {
    const module = adapterState.modalitySlots.segmentation;
    return module ? new SegmentationProtoAdapter(module) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsLifecycleProtoSegmentation(): boolean {
    return missingExports(
      this.module,
      ['_rac_segmentation_segment_lifecycle_proto'],
    ).length === 0;
  }

  async segmentLifecycle(
    request: ProtoSegmentationRequest,
  ): Promise<ProtoSegmentationResult | null> {
    if (!ensureExports(this.module, 'segmentation.segmentLifecycle', [
      '_rac_segmentation_segment_lifecycle_proto',
    ])) {
      return null;
    }

    return this.bridge().withEncodedRequestAsync(
      request,
      SegmentationRequest,
      SegmentationResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_segmentation_segment_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_segmentation_segment_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_segmentation_segment_lifecycle_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
