/**
 * Capability routing for solution graphs that span the split Web WASM
 * backends. A solution handle itself belongs to one host module, while its
 * operators may be owned by sibling modules.
 *
 * The current `rac_solution_*` C ABI does not accept this operator map, so
 * cross-WASM host dispatch remains a native-runtime limitation. Keeping the
 * routing decision here makes the precondition explicit and lets a future
 * host-dispatch ABI consume the same capability map without changing callers.
 */
import { SDKException } from '../Foundation/SDKException.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
  type WasmCapability,
} from '../runtime/EmscriptenModule.js';

export type SolutionKind = 'generic' | 'rag' | 'voice-agent';

export interface SolutionModuleResolution {
  /** WASM module that owns the solution handle and `rac_solution_*` ABI. */
  readonly hostModule: EmscriptenRunanywhereModule;
  /** Capability → owning WASM module for every operator in the graph. */
  readonly operatorModules: ReadonlyMap<WasmCapability, EmscriptenRunanywhereModule>;
}

const REQUIRED_CAPABILITIES: Readonly<Record<SolutionKind, readonly WasmCapability[]>> = {
  generic: [],
  rag: ['llm', 'embedding', 'rag'],
  'voice-agent': ['llm', 'stt', 'tts', 'vad', 'voice-agent'],
};

export class SolutionModuleCoordinator {
  /**
   * Resolve the solution host plus each operator owner. Voice-agent and RAG
   * configurations deliberately require both LlamaCPP (`llm`) and
   * ONNX/Sherpa (`embedding`/speech) to have registered before a native graph
   * is created.
   */
  static resolve(
    kind: SolutionKind,
    explicitHost?: EmscriptenRunanywhereModule,
  ): SolutionModuleResolution {
    const operatorModules = new Map<WasmCapability, EmscriptenRunanywhereModule>();
    const missing: WasmCapability[] = [];

    for (const capability of REQUIRED_CAPABILITIES[kind]) {
      const module = getModuleForCapability(capability);
      if (module) operatorModules.set(capability, module);
      else missing.push(capability);
    }

    if (missing.length > 0) {
      throw SDKException.backendNotAvailable(
        `Solutions.${kind}`,
        `${kind} solutions require registered Web backends for: ${missing.join(', ')}. ` +
        'Register LlamaCPP and ONNX before creating this solution.',
      );
    }

    const hostCapability: WasmCapability | null =
      kind === 'rag' ? 'rag' : kind === 'voice-agent' ? 'voice-agent' : null;
    const hostModule = explicitHost
      ?? (hostCapability ? getModuleForCapability(hostCapability) : null)
      ?? getModuleForCapability('commons')
      ?? getModuleForCapability('llm')
      ?? getModuleForCapability('embedding')
      ?? getModuleForCapability('stt');

    if (!hostModule) {
      throw SDKException.backendNotAvailable(
        `Solutions.${kind}`,
        'No registered Web WASM module owns the solution host ABI.',
      );
    }

    return { hostModule, operatorModules };
  }
}
