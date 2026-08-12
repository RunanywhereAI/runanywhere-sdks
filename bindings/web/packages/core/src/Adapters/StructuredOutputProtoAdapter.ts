import {
  StructuredOutputParseRequest,
  StructuredOutputResult,
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputResult as ProtoStructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import {
  getLlamaBackendWorkerDeadReason,
  mustUseLlamaBackendWorker,
} from '../runtime/BackendWorkerModelOwnership.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { SDKException } from '../Foundation/SDKException.js';
import {
  adapterState,
  decodeWorkerInferResult,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';
import { requireLlamaWorkerHost } from './LLMProtoAdapter.js';

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
    if (mustUseLlamaBackendWorker()) {
      // Sync facade cannot await worker RPC. Callers should use parseAsync.
      throw SDKException.backendNotAvailable(
        'structuredOutput.parse',
        getLlamaBackendWorkerDeadReason()
          ?? 'Structured-output parse against a BackendWorker-owned model requires parseAsync().',
      );
    }
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

  async parseAsync(
    request: ProtoStructuredOutputParseRequest,
  ): Promise<ProtoStructuredOutputResult | null> {
    if (mustUseLlamaBackendWorker()) {
      const host = requireLlamaWorkerHost(
        getActiveBackendWorkerHost('llamacpp'),
        'structuredOutput.parseAsync',
      );
      const requestBytes = StructuredOutputParseRequest.encode(request).finish();
      const response = await host.infer('structured.parse', { requestBytes });
      return decodeWorkerInferResult(response, StructuredOutputResult);
    }
    return this.parse(request);
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
