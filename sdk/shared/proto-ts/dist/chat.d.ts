import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { LLMGenerationOptions, LLMGenerationResult } from "./llm_options";
import { ToolCall, ToolCallingOptions, ToolResult } from "./tool_calling";
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
    MESSAGE_ROLE_DEVELOPER = 5,
    UNRECOGNIZED = -1
}
export declare function messageRoleFromJSON(object: any): MessageRole;
export declare function messageRoleToJSON(object: MessageRole): string;
export declare enum ChatMessageStatus {
    CHAT_MESSAGE_STATUS_UNSPECIFIED = 0,
    CHAT_MESSAGE_STATUS_PENDING = 1,
    CHAT_MESSAGE_STATUS_STREAMING = 2,
    CHAT_MESSAGE_STATUS_COMPLETE = 3,
    CHAT_MESSAGE_STATUS_FAILED = 4,
    CHAT_MESSAGE_STATUS_CANCELLED = 5,
    UNRECOGNIZED = -1
}
export declare function chatMessageStatusFromJSON(object: any): ChatMessageStatus;
export declare function chatMessageStatusToJSON(object: ChatMessageStatus): string;
export declare enum ChatStreamEventKind {
    CHAT_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED = 1,
    CHAT_STREAM_EVENT_KIND_TOKEN = 2,
    CHAT_STREAM_EVENT_KIND_TOOL_CALL = 3,
    CHAT_STREAM_EVENT_KIND_TOOL_RESULT = 4,
    CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED = 5,
    CHAT_STREAM_EVENT_KIND_ERROR = 6,
    UNRECOGNIZED = -1
}
export declare function chatStreamEventKindFromJSON(object: any): ChatStreamEventKind;
export declare function chatStreamEventKindToJSON(object: ChatStreamEventKind): string;
export interface ChatAttachment {
    id: string;
    /** MIME type or SDK-known media class. */
    mediaType: string;
    data?: Uint8Array | undefined;
    uri?: string | undefined;
    adapterHandle?: string | undefined;
    name?: string | undefined;
    sizeBytes: number;
    metadata: {
        [key: string]: string;
    };
}
export interface ChatAttachment_MetadataEntry {
    key: string;
    value: string;
}
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
     * Optional tool-call ID this message is responding to (only set when
     * role == MESSAGE_ROLE_TOOL).
     */
    toolCallId?: string | undefined;
    /** Typed tool calls embedded in this assistant message. */
    toolCalls: ToolCall[];
    /** Typed tool result carried by role == MESSAGE_ROLE_TOOL messages. */
    toolResult?: ToolResult | undefined;
    /** Optional threading and delivery metadata. */
    parentId?: string | undefined;
    status: ChatMessageStatus;
    errorMessage?: string | undefined;
    metadata: {
        [key: string]: string;
    };
    /**
     * Opaque attachments normalized by platform adapters. Capture, picker,
     * and permission flows remain native/Web-owned.
     */
    attachments: ChatAttachment[];
}
export interface ChatMessage_MetadataEntry {
    key: string;
    value: string;
}
export interface ChatGenerationRequest {
    requestId: string;
    conversationId: string;
    messages: ChatMessage[];
    options?: LLMGenerationOptions | undefined;
    toolCalling?: ToolCallingOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface ChatGenerationRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface ChatGenerationResult {
    conversationId: string;
    message?: ChatMessage | undefined;
    generation?: LLMGenerationResult | undefined;
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ChatStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    conversationId: string;
    kind: ChatStreamEventKind;
    token?: string | undefined;
    message?: ChatMessage | undefined;
    toolCall?: ToolCall | undefined;
    toolResult?: ToolResult | undefined;
    finalResult?: LLMGenerationResult | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface ChatConversationState {
    conversationId: string;
    messages: ChatMessage[];
    createdAtMs: number;
    updatedAtMs: number;
    metadata: {
        [key: string]: string;
    };
}
export interface ChatConversationState_MetadataEntry {
    key: string;
    value: string;
}
export declare const ChatAttachment: MessageFns<ChatAttachment>;
export declare const ChatAttachment_MetadataEntry: MessageFns<ChatAttachment_MetadataEntry>;
export declare const ChatMessage: MessageFns<ChatMessage>;
export declare const ChatMessage_MetadataEntry: MessageFns<ChatMessage_MetadataEntry>;
export declare const ChatGenerationRequest: MessageFns<ChatGenerationRequest>;
export declare const ChatGenerationRequest_MetadataEntry: MessageFns<ChatGenerationRequest_MetadataEntry>;
export declare const ChatGenerationResult: MessageFns<ChatGenerationResult>;
export declare const ChatStreamEvent: MessageFns<ChatStreamEvent>;
export declare const ChatConversationState: MessageFns<ChatConversationState>;
export declare const ChatConversationState_MetadataEntry: MessageFns<ChatConversationState_MetadataEntry>;
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
