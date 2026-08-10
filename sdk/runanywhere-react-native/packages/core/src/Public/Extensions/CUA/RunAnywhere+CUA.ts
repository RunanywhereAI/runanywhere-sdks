/**
 * RunAnywhere+CUA.ts
 *
 * Computer-Use Agent (CUA) extension for the RunAnywhere core SDK.
 *
 * Turns a VLM into a drivable computer-use agent WITHOUT baking any single
 * model into the SDK. A CUA *profile* (data) describes how a family of models
 * is driven: its system prompt, output format, and coordinate convention. The
 * API is model-AGNOSTIC — callers pass a `profile`; `fara` (Microsoft Fara1.5 /
 * Qwen3.5-VL `computer_use`, a fixed 1000x1000 coordinate space) ships built
 * in. Adding another CUA model is a new profile in commons, not new API.
 *
 * This layer is stateless and I/O-free (no model handle, no inference): it
 * pairs with the `processImage` / `processImageStream` VLM calls. The app owns
 * screenshot capture, executing the returned action (tap/type/scroll), and the
 * agent loop — none of the prompt/parse/coordinate knowledge leaks into it.
 *
 * Mirrors the Swift `RunAnywhere.CUA` facade (RunAnywhere+CUA.swift), backed by
 * the RN core Nitro bridge over commons `rac_cua_system_prompt` and
 * `rac_cua_parse_action_proto`. `parseAction` decodes the canonical
 * `runanywhere.v1.CuaAction` proto the bridge returns — the same proto-byte
 * bridging every other modality uses. Both calls are synchronous — pure CPU
 * string work with no init dependency (matching the Swift facade).
 */

import { CuaAction as CuaActionProto } from '@runanywhere/proto-ts/cua';

import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../../native';

/**
 * Built-in profile for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`
 * (a fixed 1000x1000 model coordinate space). Matches `RAC_CUA_PROFILE_FARA`.
 */
export const FARA_PROFILE = 'fara';

/**
 * The action a CUA model wants to perform. Raw values match the commons
 * `rac_cua_action_type_t` enum (and Swift `CuaAction.Kind`).
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

/** Map a raw native ordinal onto the enum, degrading to Unknown out of range. */
function clampKind(raw: number): CuaActionKind {
  return raw >= CuaActionKind.Unknown && raw <= CuaActionKind.Terminate
    ? (raw as CuaActionKind)
    : CuaActionKind.Unknown;
}

/** A viewport-scaled pixel coordinate. */
export interface CuaCoordinate {
  x: number;
  y: number;
}

/**
 * A computer-use-agent action parsed from a model's output, with coordinates
 * already scaled to the caller's viewport. Model-agnostic. Mirrors the Swift
 * `CuaAction` struct.
 */
export interface CuaAction {
  /** The action the model wants to perform. */
  kind: CuaActionKind;
  /** Viewport-scaled pixel coordinate (for click / move / drag), else undefined. */
  coordinate?: CuaCoordinate;
  /**
   * Primary string argument, interpreted by `kind`: Type→text, VisitURL→url,
   * WebSearch→query, Terminate→answer, AskUser/ReadPageAnswer→question,
   * PauseMemorize→fact, Key→space-joined keys.
   */
  text: string;
  /** Chain-of-thought the model emitted before the tool call, if any. */
  reasoning: string;
  /**
   * Horizontal scroll amount for `HScroll`. `CuaAction.scrollPixels` (a
   * single field) is deleted outright, split into a `scrollX`/`scrollY` pair
   * on the wire — the model's raw `pixels` output, copied verbatim per axis.
   */
  scrollX: number;
  /** Vertical scroll amount for `Scroll`. */
  scrollY: number;
  /** Seconds to wait for the `Wait` action. */
  waitSeconds: number;
  /** Whether a valid tool call was found. */
  isValid: boolean;
}

/** A width/height coordinate space (model display or app viewport). */
export interface CuaDisplaySize {
  width: number;
  height: number;
}

/** The profile's native coordinate space for `fara` (1000x1000). */
const DEFAULT_DISPLAY: CuaDisplaySize = { width: 1000, height: 1000 };

/**
 * The system prompt (identity + `computer_use` tool schema) for a profile,
 * rendered at the profile's coordinate space. Returns `null` for an unknown
 * profile, or if `display` is neither the profile's own space (1000x1000 for
 * Fara) nor zero: the space is a property of the model, and declaring a
 * different one would contradict how `parseAction` rescales its output.
 *
 * Matches Swift `RunAnywhere.CUA.systemPrompt(profile:display:)`.
 */
export function systemPrompt(options?: {
  profile?: string;
  display?: CuaDisplaySize;
}): string | null {
  if (!isNativeModuleAvailable()) {
    return null;
  }
  const profile = options?.profile ?? FARA_PROFILE;
  const display = options?.display ?? DEFAULT_DISPLAY;
  const prompt = requireNativeModule().cuaSystemPrompt(
    profile,
    display.width,
    display.height
  );
  // Commons returns an empty string for an unknown profile (rc <= 0).
  return prompt.length > 0 ? prompt : null;
}

/**
 * Parse a model's raw output into a `CuaAction`, rescaling coordinates from the
 * profile's model space to `viewport`. Returns `null` for an unknown profile;
 * `CuaAction.isValid` is false when no valid tool call was found.
 *
 * Matches Swift `RunAnywhere.CUA.parseAction(_:profile:viewport:)`.
 */
export function parseAction(
  modelOutput: string,
  options: { viewport: CuaDisplaySize; profile?: string }
): CuaAction | null {
  if (!isNativeModuleAvailable()) {
    return null;
  }
  const profile = options.profile ?? FARA_PROFILE;
  let bytes: ArrayBuffer;
  try {
    bytes = requireNativeModule().cuaParseAction(
      profile,
      modelOutput,
      options.viewport.width,
      options.viewport.height
    );
  } catch {
    // Unknown profile → the native bridge throws → null (Swift returns nil).
    return null;
  }
  const proto = CuaActionProto.decode(new Uint8Array(bytes));
  return {
    // Clamp like every other SDK (Swift `?? .unknown`, Kotlin `fromRawValue`,
    // Web's range check): a value outside the enum must degrade to Unknown
    // rather than produce a CuaActionKind that matches no member.
    kind: clampKind(proto.type as number),
    // `coordinateValid` is deleted outright — presence of `x`/`y` (both
    // optional int32) is itself "has a coordinate" now.
    coordinate:
      proto.x !== undefined && proto.y !== undefined
        ? { x: proto.x, y: proto.y }
        : undefined,
    text: proto.text,
    reasoning: proto.reasoning,
    scrollX: proto.scrollX,
    scrollY: proto.scrollY,
    waitSeconds: proto.waitSeconds,
    // `parseOk` renamed `isValid`.
    isValid: proto.isValid,
  };
}

/**
 * Computer-use-agent namespace — mirrors the Swift `RunAnywhere.CUA` surface.
 * Exposed as `RunAnywhere.cua`.
 */
export const cua = {
  /** Built-in profile id for Fara1.5 / Qwen3.5-VL `computer_use`. */
  faraProfile: FARA_PROFILE,
  systemPrompt,
  parseAction,
};
