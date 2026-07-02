import {
  type DiffusionGenerationOptions as ProtoDiffusionGenerationOptions,
  type DiffusionResult as ProtoDiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import { DiffusionProtoAdapter } from '../../Adapters/DiffusionProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    generateImage(handle: number, options: ProtoDiffusionGenerationOptions): Promise<ProtoDiffusionResult | null>;
    cancelDiffusion(handle: number): Promise<boolean>;
  }
}

function diffusion(): DiffusionProtoAdapter {
  const adapter = DiffusionProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('Diffusion');
  return adapter;
}

RunAnywhereSDK.prototype.generateImage = function (this: RunAnywhereSDK, handle, options) {
  this.ensureInitialized();
  return diffusion().generate(handle, options);
};

RunAnywhereSDK.prototype.cancelDiffusion = function (this: RunAnywhereSDK, handle) {
  return diffusion().cancel(handle);
};
