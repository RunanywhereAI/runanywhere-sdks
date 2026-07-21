import {
  VocoderRequest,
  VocoderResult,
  type VocoderRequest as ProtoVocoderRequest,
  type VocoderResult as ProtoVocoderResult,
} from '@runanywhere/proto-ts/vocoder';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { SDKException } from '../Foundation/SDKException.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

/** Typed bridge for the lifecycle-owned mel-spectrogram vocoder. */
export class VocoderProtoAdapter {
  static tryDefault(): VocoderProtoAdapter | null {
    const module = adapterState.modalitySlots.vocoder;
    return module ? new VocoderProtoAdapter(module) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsLifecycleProtoVocoder(): boolean {
    return missingExports(
      this.module,
      ['_rac_vocoder_vocode_lifecycle_proto'],
    ).length === 0;
  }

  async vocodeLifecycle(
    request: ProtoVocoderRequest,
  ): Promise<ProtoVocoderResult | null> {
    if (!ensureExports(this.module, 'vocoder.vocodeLifecycle', [
      '_rac_vocoder_vocode_lifecycle_proto',
    ])) {
      return null;
    }

    return this.bridge().withEncodedRequestAsync(
      request,
      VocoderRequest,
      VocoderResult,
      (requestPtr, requestSize, outResult) => callEmscriptenAsyncNumber(
        this.module,
        'rac_vocoder_vocode_lifecycle_proto',
        ['number', 'number', 'number'],
        [requestPtr, requestSize, outResult],
        () => this.module._rac_vocoder_vocode_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        ),
      ),
      'rac_vocoder_vocode_lifecycle_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger, {
      onNativeFailure: (failure) => {
        throw SDKException.fromCode(
          failure.resultCode,
          failure.message ??
            `${failure.functionName} failed with native status ${failure.resultCode}.`,
        );
      },
    });
  }
}
