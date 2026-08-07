import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Model-agnostic action type parsed from a CUA model's output. Values match
 * the C enum `rac_cua_action_type_t` (rac_cua.h) one-for-one.
 */
export declare enum CuaActionType {
    /** CUA_ACTION_TYPE_UNSPECIFIED - RAC_CUA_ACTION_UNKNOWN */
    CUA_ACTION_TYPE_UNSPECIFIED = 0,
    CUA_ACTION_TYPE_LEFT_CLICK = 1,
    CUA_ACTION_TYPE_RIGHT_CLICK = 2,
    CUA_ACTION_TYPE_DOUBLE_CLICK = 3,
    CUA_ACTION_TYPE_TRIPLE_CLICK = 4,
    CUA_ACTION_TYPE_MOUSE_MOVE = 5,
    CUA_ACTION_TYPE_LEFT_CLICK_DRAG = 6,
    CUA_ACTION_TYPE_TYPE = 7,
    CUA_ACTION_TYPE_KEY = 8,
    CUA_ACTION_TYPE_SCROLL = 9,
    CUA_ACTION_TYPE_HSCROLL = 10,
    CUA_ACTION_TYPE_VISIT_URL = 11,
    CUA_ACTION_TYPE_HISTORY_BACK = 12,
    CUA_ACTION_TYPE_WEB_SEARCH = 13,
    CUA_ACTION_TYPE_READ_PAGE_ANSWER = 14,
    CUA_ACTION_TYPE_PAUSE_MEMORIZE = 15,
    CUA_ACTION_TYPE_ASK_USER = 16,
    CUA_ACTION_TYPE_WAIT = 17,
    CUA_ACTION_TYPE_TERMINATE = 18,
    UNRECOGNIZED = -1
}
export declare function cuaActionTypeFromJSON(object: any): CuaActionType;
export declare function cuaActionTypeToJSON(object: CuaActionType): string;
/**
 * A single parsed CUA action. Coordinates are already scaled to the caller's
 * viewport. `text` is the action's primary string argument, keyed by `type`:
 * TYPE->text, VISIT_URL->url, WEB_SEARCH->query, TERMINATE->answer,
 * ASK_USER/READ_PAGE_ANSWER->question, PAUSE_MEMORIZE->fact, KEY->space-joined
 * keys. `reasoning` holds any chain-of-thought preceding the tool_call.
 *
 * COORDINATE CONTRACT: x/y are integers in the SAME pixel space as the
 * viewport you passed to parse_action, origin at the TOP-LEFT. That viewport
 * must be the pixel dimensions of the exact image you handed to the VLM — if
 * you downscaled the screenshot before sending it, pass the downscaled
 * dimensions. On a DPR-2/3/4 display, passing logical points while sending a
 * physical-pixel screenshot offsets every click by that factor, silently (see
 * examples/ios/.../ComputerUseAgentViewModel.swift for the correct
 * computation). parse_action has already rescaled out of the profile's own
 * space (1000x1000 for `fara`), so no further scaling is ever correct.
 *
 * LEFT_CLICK_DRAG: x/y are the drag DESTINATION only. Fara emits no origin (it
 * drags from the current cursor), and a touch screen has no cursor, so the
 * HOST must supply the press point — typically the last MOUSE_MOVE target.
 *
 * LENGTH: `text` and `reasoning` are TRUNCATED at 2047 bytes on a UTF-8 lead
 * byte by the fixed C buffers behind them (rac_cua_action_t.text[2048]); no
 * field records that truncation happened. This also caps a TERMINATE answer.
 */
export interface CuaAction {
    type: CuaActionType;
    /** viewport pixels from the LEFT edge; presence = "has a coordinate" */
    x?: number | undefined;
    /** viewport pixels from the TOP edge */
    y?: number | undefined;
    /**
     * HSCROLL/SCROLL axis split. Value is the model's raw `pixels` output,
     * copied verbatim per axis — the sign is UNVERIFIED against any real
     * device trace, so no direction convention is asserted here.
     */
    scrollX: number;
    /** SCROLL */
    scrollY: number;
    /**
     * WAIT: fractional seconds. Clamped by commons to [0, 100] because the
     * value comes from untrusted model output; an unbounded parse would wedge
     * the agent loop. 100s is a RunAnywhere-chosen ceiling, not inherited from
     * any vendor API.
     */
    waitSeconds: number;
    /** primary string arg (see above) */
    text: string;
    /** CoT before the tool_call, if any */
    reasoning: string;
    /** true if a valid tool_call was found */
    isValid: boolean;
}
export declare const CuaAction: MessageFns<CuaAction>;
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
