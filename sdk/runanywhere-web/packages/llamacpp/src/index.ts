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
 * `@runanywhere/web` (`RunAnywhere.textGeneration.*`, `RunAnywhere.toolCalling.*`,
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
 *     const stream = await RunAnywhere.textGeneration.generateStream({
 *       prompt: 'Tell me a joke',
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
