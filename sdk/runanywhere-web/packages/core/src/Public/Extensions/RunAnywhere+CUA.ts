/**
 * RunAnywhere+CUA.ts
 *
 * Public Computer-Use-Agent namespace mirroring Swift's `RunAnywhere.CUA`
 * (RunAnywhere+CUA.swift). Turns a VLM into a drivable computer-use agent
 * using a model *profile* (data describing prompt / output format / coordinate
 * convention). Fara1.5 ships built in; adding another CUA model is a new
 * profile in commons, not new API.
 *
 * This layer is stateless and model-agnostic — pair it with
 * `processImage`/`processImageStream` for inference; the app owns screenshot
 * capture, executing the returned action, and the agent loop. All prompt /
 * parse / coordinate knowledge stays in commons behind the `rac_cua_*` C ABI;
 * this facade marshals strings across the WASM boundary and decodes the
 * canonical `runanywhere.v1.CuaAction` proto commons serializes — the same
 * proto-byte bridging every other modality uses.
 */

import { CuaAction as CuaActionProto } from '@runanywhere/proto-ts/cua';

import {
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import { ProtoWasmBridge, type ProtoWasmModule } from '../../runtime/ProtoWasm.js';
import { SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';

/**
 * The action a CUA model wants to perform. Numeric values match the commons
 * `rac_cua_action_type_t` enum (rac_cua.h) and the generated
 * `@runanywhere/proto-ts/cua` `CuaActionType` one-for-one — this is the public,
 * Swift-shaped local type the decoded proto maps onto.
 */
export enum CuaActionKind {
  Unknown = 0,
  LeftClick = 1,
  RightClick = 2,
  DoubleClick = 3,
  TripleClick = 4,
  MouseMove = 5,
  LeftClickDrag = 6,
  Type = 7,
  Key = 8,
  Scroll = 9,
  HScroll = 10,
  VisitURL = 11,
  HistoryBack = 12,
  WebSearch = 13,
  ReadPageAnswer = 14,
  PauseMemorize = 15,
  AskUser = 16,
  Wait = 17,
  Terminate = 18,
}

/** A viewport-scaled pixel coordinate (click / move / drag targets). */
export interface CuaCoordinate {
  readonly x: number;
  readonly y: number;
}

/**
 * A single parsed computer-use action, with coordinates already scaled to the
 * caller's viewport. Mirrors Swift's `CuaAction`.
 */
export interface CuaAction {
  /** The action the model wants to perform. */
  readonly kind: CuaActionKind;
  /** Viewport-scaled pixel coordinate (click / move / drag), else null. */
  readonly coordinate: CuaCoordinate | null;
  /**
   * Primary string argument, interpreted by `kind`: Type→text, VisitURL→url,
   * WebSearch→query, Terminate→answer, AskUser/ReadPageAnswer→question,
   * PauseMemorize→fact, Key→space-joined keys.
   */
  readonly text: string;
  /** Chain-of-thought the model emitted before the tool call, if any. */
  readonly reasoning: string;
  /** Scroll amount for Scroll/HScroll (+up / -down). */
  readonly scrollPixels: number;
  /** Seconds to wait for Wait. */
  readonly waitSeconds: number;
  /** Whether a valid tool call was found. */
  readonly isValid: boolean;
}

/** Coordinate space passed to the model / used to rescale its output. */
export interface CuaDisplaySize {
  readonly width: number;
  readonly height: number;
}

/** Built-in profile for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`. */
const FARA_PROFILE = 'fara';

/** Fara's fixed native coordinate space. */
const DEFAULT_DISPLAY: CuaDisplaySize = { width: 1000, height: 1000 };

const REBUILD_HINT =
  'Rebuild the WASM artifact from wasm/src/wasm_exports.cpp (npm run build:wasm) ' +
  'so the rac_cua_* exports are linked.';

const logger = new SDKLogger('CUA');

/**
 * Resolve the module that carries the stateless CUA exports. They are compiled
 * into commons, so every backend WASM (and the commons-only artifact) exports
 * them — `tryRunanywhereModule()` returns whichever is registered.
 */
function requireModule(): EmscriptenRunanywhereModule {
  const module = tryRunanywhereModule();
  if (!module) {
    throw SDKException.wasmNotLoaded(
      'CUA requires a loaded WASM module. Call RunAnywhere.initialize() first.',
    );
  }
  return module;
}

/** Write a NUL-terminated UTF-8 C string into the heap; caller frees. */
function allocCString(module: EmscriptenRunanywhereModule, value: string): number {
  const size = module.lengthBytesUTF8(value) + 1;
  const ptr = module._malloc(size);
  module.stringToUTF8(value, ptr, size);
  return ptr;
}

/**
 * Computer-use-agent scaffold namespace. Attached as `RunAnywhere.CUA`.
 */
export const CUA = {
  /** Built-in profile id for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`. */
  faraProfile: FARA_PROFILE,

  /**
   * The system prompt (identity + `computer_use` tool schema) for a profile,
   * rendered at a declared coordinate space (pass the profile's native space,
   * e.g. 1000×1000 for Fara). Returns null for an unknown profile.
   */
  systemPrompt(
    profile: string = FARA_PROFILE,
    display: CuaDisplaySize = DEFAULT_DISPLAY,
  ): string | null {
    const module = requireModule();
    const systemPromptFn = module._rac_cua_system_prompt;
    if (typeof systemPromptFn !== 'function') {
      throw new SDKException(-1, `WASM module missing _rac_cua_system_prompt. ${REBUILD_HINT}`);
    }

    const profilePtr = allocCString(module, profile);
    try {
      // Size first with a NULL out buffer.
      const needed = systemPromptFn(profilePtr, display.width, display.height, 0, 0);
      if (needed <= 0) return null;

      const bufferSize = needed + 1;
      const bufferPtr = module._malloc(bufferSize);
      try {
        systemPromptFn(profilePtr, display.width, display.height, bufferPtr, bufferSize);
        return module.UTF8ToString(bufferPtr);
      } finally {
        module._free(bufferPtr);
      }
    } finally {
      module._free(profilePtr);
    }
  },

  /**
   * Parse a model's raw output into a `CuaAction`, rescaling coordinates from
   * the profile's model space to `viewport`. Returns null for an unknown
   * profile; `CuaAction.isValid` is false when no tool call was found.
   */
  parseAction(
    modelOutput: string,
    profile: string = FARA_PROFILE,
    viewport: CuaDisplaySize,
  ): CuaAction | null {
    const module = requireModule();
    const parseFn = module._rac_cua_parse_action_proto;
    if (typeof parseFn !== 'function') {
      throw new SDKException(-1, `WASM module missing _rac_cua_parse_action_proto. ${REBUILD_HINT}`);
    }

    const profilePtr = allocCString(module, profile);
    const outputPtr = allocCString(module, modelOutput);
    try {
      const bridge = new ProtoWasmBridge(module as unknown as ProtoWasmModule, logger);
      const bytes = bridge.readResultProto(
        (outBufferPtr) =>
          parseFn(profilePtr, outputPtr, viewport.width, viewport.height, outBufferPtr),
        'rac_cua_parse_action_proto',
      );
      // null → unknown profile (or missing exports) → Swift nil parity. An empty
      // (but non-null) buffer decodes to a CuaAction with parseOk = false.
      if (!bytes) return null;

      const proto = CuaActionProto.decode(bytes);
      const rawType = proto.type as number;
      const kind =
        rawType >= CuaActionKind.Unknown && rawType <= CuaActionKind.Terminate
          ? (rawType as CuaActionKind)
          : CuaActionKind.Unknown;

      return {
        kind,
        coordinate: proto.coordinateValid ? { x: proto.x, y: proto.y } : null,
        text: proto.text,
        reasoning: proto.reasoning,
        scrollPixels: proto.scrollPixels,
        waitSeconds: proto.waitSeconds,
        isValid: proto.parseOk,
      };
    } finally {
      module._free(outputPtr);
      module._free(profilePtr);
    }
  },
} as const;
