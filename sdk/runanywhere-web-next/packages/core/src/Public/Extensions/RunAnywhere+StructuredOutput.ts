import {
  type StructuredOutputParseRequest as ProtoStructuredOutputParseRequest,
  type StructuredOutputResult as ProtoStructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import { StructuredOutputProtoAdapter } from '../../Adapters/StructuredOutputProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    parseStructured(request: ProtoStructuredOutputParseRequest): Promise<ProtoStructuredOutputResult | null>;
  }
}

RunAnywhereSDK.prototype.parseStructured = function (this: RunAnywhereSDK, request) {
  this.ensureInitialized();
  const adapter = StructuredOutputProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('StructuredOutput');
  return adapter.parse(request);
};
