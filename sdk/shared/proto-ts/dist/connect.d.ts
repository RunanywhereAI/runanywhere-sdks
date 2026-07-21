import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { LLMGenerateRequest, LLMStreamEvent } from "./llm_service";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Platform identity is explicit so commons can evaluate role availability
 * from one policy table. Platform SDKs must not hardcode the host/client
 * matrix in UI or transport code.
 */
export declare enum ConnectPlatform {
    CONNECT_PLATFORM_UNSPECIFIED = 0,
    CONNECT_PLATFORM_MACOS = 1,
    CONNECT_PLATFORM_IOS = 2,
    CONNECT_PLATFORM_IPADOS = 3,
    /**
     * CONNECT_PLATFORM_ANDROID - Reserved for the follow-on SDK integrations. Keeping the values in the
     * canonical IDL avoids a later wire-format migration.
     */
    CONNECT_PLATFORM_ANDROID = 4,
    CONNECT_PLATFORM_REACT_NATIVE = 5,
    CONNECT_PLATFORM_FLUTTER = 6,
    CONNECT_PLATFORM_WEB = 7,
    /**
     * CONNECT_PLATFORM_WINDOWS - Reserved now so adding the planned Windows host adapter does not require
     * a platform-identity wire migration. Its host role remains PLANNED until
     * the native transport, discovery, and protected-storage adapter ships.
     */
    CONNECT_PLATFORM_WINDOWS = 8,
    UNRECOGNIZED = -1
}
export declare function connectPlatformFromJSON(object: any): ConnectPlatform;
export declare function connectPlatformToJSON(object: ConnectPlatform): string;
/**
 * Role availability is richer than a boolean so the wire contract can reserve
 * planned platforms without accidentally advertising them as usable.
 */
export declare enum ConnectRoleAvailability {
    CONNECT_ROLE_AVAILABILITY_UNSPECIFIED = 0,
    CONNECT_ROLE_AVAILABILITY_DISABLED = 1,
    CONNECT_ROLE_AVAILABILITY_PLANNED = 2,
    CONNECT_ROLE_AVAILABILITY_ENABLED = 3,
    UNRECOGNIZED = -1
}
export declare function connectRoleAvailabilityFromJSON(object: any): ConnectRoleAvailability;
export declare function connectRoleAvailabilityToJSON(object: ConnectRoleAvailability): string;
export declare enum ConnectHandshakeStatus {
    CONNECT_HANDSHAKE_STATUS_UNSPECIFIED = 0,
    CONNECT_HANDSHAKE_STATUS_ACCEPTED = 1,
    CONNECT_HANDSHAKE_STATUS_REJECTED = 2,
    UNRECOGNIZED = -1
}
export declare function connectHandshakeStatusFromJSON(object: any): ConnectHandshakeStatus;
export declare function connectHandshakeStatusToJSON(object: ConnectHandshakeStatus): string;
export declare enum ConnectSessionState {
    CONNECT_SESSION_STATE_UNSPECIFIED = 0,
    CONNECT_SESSION_STATE_CONNECTING = 1,
    CONNECT_SESSION_STATE_CONNECTED = 2,
    CONNECT_SESSION_STATE_DISCONNECTED = 3,
    CONNECT_SESSION_STATE_FAILED = 4,
    UNRECOGNIZED = -1
}
export declare function connectSessionStateFromJSON(object: any): ConnectSessionState;
export declare function connectSessionStateToJSON(object: ConnectSessionState): string;
export interface ConnectPlatformPolicyRequest {
    platform: ConnectPlatform;
}
/**
 * Commons is the authority for this policy. SDKs may query it to shape UI,
 * but every host/client entrypoint also enforces it inside C++.
 */
export interface ConnectPlatformPolicy {
    platform: ConnectPlatform;
    hostRole: ConnectRoleAvailability;
    clientRole: ConnectRoleAvailability;
}
/**
 * Non-secret metadata published through LAN service discovery and echoed by
 * the handshake. `instance_id` is generated anew whenever the host starts;
 * it is not a persistent device identifier or a credential.
 */
export interface ConnectDiscoveryMetadata {
    instanceId: string;
    displayName: string;
    platform: ConnectPlatform;
    protocolVersion: number;
}
/**
 * The single language model currently shared by a host. A host must select a
 * loaded model before it starts publishing; this lets clients enter chat
 * immediately without downloading or selecting a local model.
 */
export interface ConnectModelDescriptor {
    modelId: string;
    displayName: string;
    framework: string;
    contextWindow: number;
    supportsStreaming: boolean;
}
export interface ConnectHostStartRequest {
    displayName: string;
    platform: ConnectPlatform;
    protocolVersion: number;
    model?: ConnectModelDescriptor | undefined;
}
export interface ConnectHostStopRequest {
}
export interface ConnectHostState {
    isHosting: boolean;
    discoveryMetadata?: ConnectDiscoveryMetadata | undefined;
    activeClientCount: number;
    errorMessage: string;
    model?: ConnectModelDescriptor | undefined;
}
export interface ConnectClientStartRequest {
    displayName: string;
    platform: ConnectPlatform;
    protocolVersion: number;
}
/** Sent by a client immediately after the platform transport is connected. */
export interface ConnectClientHello {
    instanceId: string;
    displayName: string;
    platform: ConnectPlatform;
    protocolVersion: number;
}
/** Sent by the host after commons has accepted or rejected a client hello. */
export interface ConnectHandshakeResponse {
    status: ConnectHandshakeStatus;
    sessionId: string;
    host?: ConnectDiscoveryMetadata | undefined;
    rejectionReason: string;
    model?: ConnectModelDescriptor | undefined;
}
/**
 * The client validates the host response through commons and receives the
 * public session state it can expose to its platform UI.
 */
export interface ConnectClientSessionState {
    state: ConnectSessionState;
    sessionId: string;
    host?: ConnectDiscoveryMetadata | undefined;
    errorMessage: string;
    model?: ConnectModelDescriptor | undefined;
}
export interface ConnectSessionCloseRequest {
    sessionId: string;
}
/**
 * A client sends the existing typed LLM request to the selected host model.
 * `session_id` binds the request to the prior handshake; `generation.model_id`
 * must match the model the host published for that session.
 */
export interface ConnectInvocationRequest {
    sessionId: string;
    requestId: string;
    generation?: LLMGenerateRequest | undefined;
}
/**
 * Commons validates that an invocation belongs to an active session and uses
 * the host's published model before any platform runtime receives the prompt.
 */
export interface ConnectInvocationValidation {
    accepted: boolean;
    rejectionReason: string;
}
/**
 * Hosts forward the SDK's canonical stream events without translating them to
 * a platform-specific token shape. This is the portable streaming surface for
 * future Kotlin, React Native, Flutter, and Web clients.
 */
export interface ConnectInvocationEvent {
    requestId: string;
    event?: LLMStreamEvent | undefined;
}
/**
 * The connection stays open between generations, so the client needs a
 * control-plane exchange that can detect a host stopped while chat is idle.
 * These frames deliberately remain separate from LLM invocation payloads:
 * a health check must never reach a model or appear as an assistant message.
 */
export interface ConnectHeartbeatRequest {
    sessionId: string;
    sequence: number;
}
export interface ConnectHeartbeatResponse {
    sessionId: string;
    sequence: number;
}
/**
 * Every frame after the initial ClientHello handshake is carried in one of
 * these explicit envelopes. This leaves typed inference traffic untouched
 * while allowing clients to verify an otherwise-idle host connection.
 */
export interface ConnectClientFrame {
    invocation?: ConnectInvocationRequest | undefined;
    heartbeat?: ConnectHeartbeatRequest | undefined;
}
export interface ConnectHostFrame {
    invocationEvent?: ConnectInvocationEvent | undefined;
    heartbeat?: ConnectHeartbeatResponse | undefined;
}
export declare const ConnectPlatformPolicyRequest: MessageFns<ConnectPlatformPolicyRequest>;
export declare const ConnectPlatformPolicy: MessageFns<ConnectPlatformPolicy>;
export declare const ConnectDiscoveryMetadata: MessageFns<ConnectDiscoveryMetadata>;
export declare const ConnectModelDescriptor: MessageFns<ConnectModelDescriptor>;
export declare const ConnectHostStartRequest: MessageFns<ConnectHostStartRequest>;
export declare const ConnectHostStopRequest: MessageFns<ConnectHostStopRequest>;
export declare const ConnectHostState: MessageFns<ConnectHostState>;
export declare const ConnectClientStartRequest: MessageFns<ConnectClientStartRequest>;
export declare const ConnectClientHello: MessageFns<ConnectClientHello>;
export declare const ConnectHandshakeResponse: MessageFns<ConnectHandshakeResponse>;
export declare const ConnectClientSessionState: MessageFns<ConnectClientSessionState>;
export declare const ConnectSessionCloseRequest: MessageFns<ConnectSessionCloseRequest>;
export declare const ConnectInvocationRequest: MessageFns<ConnectInvocationRequest>;
export declare const ConnectInvocationValidation: MessageFns<ConnectInvocationValidation>;
export declare const ConnectInvocationEvent: MessageFns<ConnectInvocationEvent>;
export declare const ConnectHeartbeatRequest: MessageFns<ConnectHeartbeatRequest>;
export declare const ConnectHeartbeatResponse: MessageFns<ConnectHeartbeatResponse>;
export declare const ConnectClientFrame: MessageFns<ConnectClientFrame>;
export declare const ConnectHostFrame: MessageFns<ConnectHostFrame>;
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
