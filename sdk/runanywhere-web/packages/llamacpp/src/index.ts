/**
 * @runanywhere/web-llamacpp
 *
 * LlamaCpp WASM backend for the RunAnywhere Web SDK.
 *
 * V2 canonical: this package is a SHELL. It loads `racommons-llamacpp.wasm`
 * (or the WebGPU variant) as an independent Emscripten module, registers
 * the platform adapter + the llama.cpp + llama.cpp-VLM backends, then
 * installs the module on every core proto-byte adapter via
 * `setRunanywhereModule()`.
 *
 * After `LlamaCPP.register()` resolves, the public surface in
 * `@runanywhere/web` (`RunAnywhere.generate`, `RunAnywhere.generateStream`,
 * `RunAnywhere.textGeneration.*`, `RunAnywhere.toolCalling.*`,
 * `RunAnywhere.structuredOutput.*`, embeddings, diffusion, VLM) flows
 * through the proto-byte adapters into the WASM module without any
 * further per-package wiring.
 *
 * Usage:
 *
 *     import { RunAnywhere } from '@runanywhere/web';
 *     import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 *     await RunAnywhere.initialize({ environment: 'development' });
 *     await LlamaCPP.register({ acceleration: 'auto' });
 *
 *     const stream = await RunAnywhere.generateStream('Tell me a joke', {
 *       maxTokens: 256,
 *       temperature: 0.7,
 *     });
 *     for await (const token of stream.stream) {
 *       process.stdout.write(token);
 *     }
 *     const result = await stream.result;
 *
 * @packageDocumentation
 */

export { LlamaCPP, autoRegister } from './LlamaCPP';
export type { LlamaCPPRegisterOptions } from './LlamaCPP';
export { LlamaCppBridge } from './Foundation/LlamaCppBridge';
export type { LlamaCppModule } from './Foundation/LlamaCppBridge';

// Off-main-thread VLM runtime — apps that need to dispatch vision inference
// directly (e.g. example apps that own the camera capture loop) can call
// `VLMWorkerBridge.shared.process(image, options)` after a VLM model has been
// loaded into the worker.
export { VLMWorkerBridge } from './Infrastructure/VLMWorkerBridge';
export type {
  VLMWorkerCommand,
  VLMWorkerResponse,
  VLMLoadModelParams,
  ProgressListener,
} from './Infrastructure/VLMWorkerBridge';
