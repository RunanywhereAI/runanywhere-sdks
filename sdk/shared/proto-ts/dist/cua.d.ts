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
 */
export interface CuaAction {
    type: CuaActionType;
    /** true if x/y are valid */
    coordinateValid: boolean;
    /** viewport-scaled pixels */
    x: number;
    y: number;
    /** SCROLL/HSCROLL: +up / -down */
    scrollPixels: number;
    /** WAIT */
    waitSeconds: number;
    /** primary string arg (see above) */
    text: string;
    /** CoT before the tool_call, if any */
    reasoning: string;
    /** true if a valid tool_call was found */
    parseOk: boolean;
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
