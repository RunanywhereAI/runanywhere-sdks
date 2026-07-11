/**
 * @runanywhere/web-llamacpp
 *
 * LlamaCpp WASM backend for the RunAnywhere Web SDK.
 *
 * V2 canonical: this package is a SHELL. It loads `racommons-llamacpp.wasm`
 * (or the WebGPU variant) as an independent Emscripten module, registers
 * the platform adapter + the llama.cpp + llama.cpp-VLM backends, then
 * claims the relevant capabilities (LLM/VLM/embeddings/diffusion/...) on
 * the per-capability registry so every core proto-byte adapter routes
 * through this module.
 *
 * After `LlamaCPP.register()` resolves, the public surface in
 * `@runanywhere/web` (`RunAnywhere.generate(Stream)`,
 * `RunAnywhere.generateWithTools`, `RunAnywhere.generateStructured(Stream)`,
 * `RunAnywhere.processImage(Stream)`) flows through the proto-byte
 * adapters into the WASM module without any further per-package wiring.
 *
 * # Public surface
 *
 * The package root intentionally exposes ONLY the registration facade
 * (`LlamaCPP`, `autoRegister`) and its option types. The `LlamaCppBridge`
 * singleton and `LlamaCppModule` runtime type are internal implementation
 * details (mirroring `@runanywhere/web-onnx`).
 *
 * Usage:
 *
 *     import { RunAnywhere } from '@runanywhere/web';
 *     import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 *     await RunAnywhere.initialize({ environment: 'development' });
 *     await LlamaCPP.register({ acceleration: 'auto' });
 *
 *     const stream = await RunAnywhere.generateStream({
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

export { LlamaCPP, autoRegister } from './LlamaCPP.js';
export type { LlamaCPPRegisterOptions } from './LlamaCPP.js';
export type { BackendRegistrationState } from '@runanywhere/web/backend';
