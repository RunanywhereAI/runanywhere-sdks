import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Conversational role of a ChatMessage.
 * ---------------------------------------------------------------------------
 */
export declare enum MessageRole {
    MESSAGE_ROLE_UNSPECIFIED = 0,
    MESSAGE_ROLE_USER = 1,
    MESSAGE_ROLE_ASSISTANT = 2,
    MESSAGE_ROLE_SYSTEM = 3,
    /**
     * MESSAGE_ROLE_TOOL - Tool-result messages injected back into the conversation after a
     * tool call has been executed. Required for OpenAI-style tool flows.
     */
    MESSAGE_ROLE_TOOL = 4,
    UNRECOGNIZED = -1
}
export declare function messageRoleFromJSON(object: any): MessageRole;
export declare function messageRoleToJSON(object: MessageRole): string;
/**
 * ---------------------------------------------------------------------------
 * A single message in a chat conversation.
 * ---------------------------------------------------------------------------
 */
export interface ChatMessage {
    /**
     * Unique identifier for the message (caller-supplied or generated).
     * Empty = unset (proto3 scalar default).
     */
    id: string;
    /** Role (user / assistant / system / tool). */
    role: MessageRole;
    /**
     * Message text content. May be empty for messages that only carry tool
     * calls (assistant role) or tool results (tool role).
     */
    content: string;
    /**
     * Wall-clock timestamp the message was authored, in microseconds since
     * Unix epoch. 0 = unset; consumers may stamp at receive-time.
     */
    timestampUs: number;
    /**
     * Optional human-readable display name. Used by some chat UIs to
     * distinguish multiple users in a multi-party conversation.
     */
    name?: string | undefined;
    /**
     * Optional tool calls embedded in this assistant message. Each entry is
     * a JSON-encoded ToolCall (see tool_calling.proto) — kept as a string
     * here to avoid a circular import; consumers parse on demand.
     */
    toolCallsJson: string[];
    /**
     * Optional tool-call ID this message is responding to (only set when
     * role == MESSAGE_ROLE_TOOL).
     */
    toolCallId?: string | undefined;
}
export declare const ChatMessage: {
    encode(message: ChatMessage, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ChatMessage;
    fromJSON(object: any): ChatMessage;
    toJSON(message: ChatMessage): unknown;
    create<I extends Exact<DeepPartial<ChatMessage>, I>>(base?: I): ChatMessage;
    fromPartial<I extends Exact<DeepPartial<ChatMessage>, I>>(object: I): ChatMessage;
};
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
export {};
//# sourceMappingURL=chat.d.ts.map