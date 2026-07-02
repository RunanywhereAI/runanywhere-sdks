import {
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
  type VLMStreamEvent as ProtoVLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
import { VLMProtoAdapter } from '../../Adapters/VLMProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    processImage(handle: number, image: ProtoVLMImage, options: ProtoVLMGenerationOptions): Promise<ProtoVLMResult | null>;
    streamImage(image: ProtoVLMImage, options: ProtoVLMGenerationOptions): AsyncIterable<ProtoVLMStreamEvent>;
    cancelImage(handle: number): Promise<boolean>;
  }
}

function vlm(): VLMProtoAdapter {
  const adapter = VLMProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('VLM');
  return adapter;
}

RunAnywhereSDK.prototype.processImage = function (this: RunAnywhereSDK, handle, image, options) {
  this.ensureInitialized();
  return vlm().process(handle, image, options);
};

RunAnywhereSDK.prototype.streamImage = function (this: RunAnywhereSDK, image, options) {
  this.ensureInitialized();
  return vlm().streamEvents(image, options);
};

RunAnywhereSDK.prototype.cancelImage = function (this: RunAnywhereSDK, handle) {
  return vlm().cancel(handle);
};
