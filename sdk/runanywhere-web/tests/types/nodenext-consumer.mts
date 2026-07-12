/**
 * Published-package consumer fixture.
 *
 * This file intentionally resolves only package entrypoints through their
 * package.json exports maps. NodeNext rejects extensionless relative imports
 * in emitted ESM declarations, catching a class of release breakage that the
 * Web workspace's normal `moduleResolution: "bundler"` build accepts.
 */
import {
  RunAnywhere,
  SDKException,
  type ModelLoadRequest,
} from '@runanywhere/web';
import {
  registerWasmModule,
  type BackendRegistrationState,
} from '@runanywhere/web/backend';
import {
  AudioCapture,
  type AudioCaptureConfig,
} from '@runanywhere/web/browser';
import {
  LlamaCPP,
  type LlamaCPPRegisterOptions,
} from '@runanywhere/web-llamacpp';
import {
  ONNX,
  onnxStatus,
  type ONNXRegisterOptions,
} from '@runanywhere/web-onnx';

export const nodeNextConsumerValues = {
  RunAnywhere,
  SDKException,
  registerWasmModule,
  AudioCapture,
  LlamaCPP,
  ONNX,
  onnxStatus,
};

export interface NodeNextConsumerContracts {
  modelLoad: ModelLoadRequest;
  backendState: BackendRegistrationState;
  audioCapture: AudioCaptureConfig;
  llamaOptions: LlamaCPPRegisterOptions;
  onnxOptions: ONNXRegisterOptions;
}
