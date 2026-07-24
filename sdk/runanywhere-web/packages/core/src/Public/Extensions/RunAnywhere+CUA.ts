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
 * this facade only marshals strings and the `rac_cua_action_t` struct across
 * the WASM boundary via the compiler-derived sizeof/offset helpers.
 */

import {
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import { SDKException } from '../../Foundation/SDKException.js';

/**
 * The action a CUA model wants to perform. Numeric values match the commons
 * `rac_cua_action_type_t` enum ordering (rac_cua.h) one-for-one, so a raw
 * struct read maps directly onto this union. There is no generated
 * `@runanywhere/proto-ts` enum for CUA yet (the proto-byte `CuaAction` variant
 * is a planned commons follow-up), so this is the canonical local type.
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

/** Read a required offset helper or throw a rebuild hint. */
function offset(
  fn: (() => number) | undefined,
  name: string,
): number {
  if (typeof fn !== 'function') {
    throw new SDKException(-1, `WASM module missing ${name}. ${REBUILD_HINT}`);
  }
  return fn();
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
    const parseFn = module._rac_cua_parse_action;
    if (typeof parseFn !== 'function') {
      throw new SDKException(-1, `WASM module missing _rac_cua_parse_action. ${REBUILD_HINT}`);
    }

    const structSize = offset(module._rac_wasm_sizeof_cua_action, '_rac_wasm_sizeof_cua_action');
    const offType = offset(module._rac_wasm_offsetof_cua_action_type, '_rac_wasm_offsetof_cua_action_type');
    const offHasCoord = offset(
      module._rac_wasm_offsetof_cua_action_has_coordinate,
      '_rac_wasm_offsetof_cua_action_has_coordinate',
    );
    const offX = offset(module._rac_wasm_offsetof_cua_action_x, '_rac_wasm_offsetof_cua_action_x');
    const offY = offset(module._rac_wasm_offsetof_cua_action_y, '_rac_wasm_offsetof_cua_action_y');
    const offScroll = offset(
      module._rac_wasm_offsetof_cua_action_scroll_pixels,
      '_rac_wasm_offsetof_cua_action_scroll_pixels',
    );
    const offWait = offset(
      module._rac_wasm_offsetof_cua_action_wait_seconds,
      '_rac_wasm_offsetof_cua_action_wait_seconds',
    );
    const offText = offset(module._rac_wasm_offsetof_cua_action_text, '_rac_wasm_offsetof_cua_action_text');
    const offReasoning = offset(
      module._rac_wasm_offsetof_cua_action_reasoning,
      '_rac_wasm_offsetof_cua_action_reasoning',
    );
    const offParseOk = offset(
      module._rac_wasm_offsetof_cua_action_parse_ok,
      '_rac_wasm_offsetof_cua_action_parse_ok',
    );

    const profilePtr = allocCString(module, profile);
    const outputPtr = allocCString(module, modelOutput);
    const actionPtr = module._malloc(structSize);
    try {
      // Zero-init the struct so unread padding never leaks stale heap bytes.
      for (let i = 0; i < structSize; i++) module.setValue(actionPtr + i, 0, 'i8');

      const rc = parseFn(profilePtr, outputPtr, viewport.width, viewport.height, actionPtr);
      if (rc !== 0) return null; // unknown profile / NULL args

      const rawType = module.getValue(actionPtr + offType, 'i32');
      const hasCoordinate = module.getValue(actionPtr + offHasCoord, 'i32') !== 0;
      const kind =
        rawType >= CuaActionKind.Unknown && rawType <= CuaActionKind.Terminate
          ? (rawType as CuaActionKind)
          : CuaActionKind.Unknown;

      return {
        kind,
        coordinate: hasCoordinate
          ? {
              x: module.getValue(actionPtr + offX, 'i32'),
              y: module.getValue(actionPtr + offY, 'i32'),
            }
          : null,
        text: module.UTF8ToString(actionPtr + offText),
        reasoning: module.UTF8ToString(actionPtr + offReasoning),
        scrollPixels: module.getValue(actionPtr + offScroll, 'i32'),
        waitSeconds: module.getValue(actionPtr + offWait, 'double'),
        isValid: module.getValue(actionPtr + offParseOk, 'i32') !== 0,
      };
    } finally {
      module._free(actionPtr);
      module._free(outputPtr);
      module._free(profilePtr);
    }
  },
} as const;
