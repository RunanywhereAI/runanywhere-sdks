import {
  StructuredOutputParseRequest,
  StructuredOutputResult,
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputResult as ProtoStructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class StructuredOutputProtoAdapter {
  static tryDefault(): StructuredOutputProtoAdapter | null {
    const mod = adapterState.modalitySlots['structured-output'];
    return mod ? new StructuredOutputProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoParse(): boolean {
    return missingExports(this.module, ['_rac_structured_output_parse_proto']).length === 0;
  }

  parse(
    request: ProtoStructuredOutputParseRequest,
  ): ProtoStructuredOutputResult | null {
    if (!ensureExports(this.module, 'structuredOutput.parse', [
      '_rac_structured_output_parse_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      StructuredOutputParseRequest,
      StructuredOutputResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_structured_output_parse_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_structured_output_parse_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
