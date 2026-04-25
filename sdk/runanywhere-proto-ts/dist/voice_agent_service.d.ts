import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Empty request type — the voice agent already has its config set via
 * `rac_voice_agent_init()` at handle creation time. The Stream rpc just
 * opens a new event subscription on an existing handle.
 */
export interface VoiceAgentRequest {
    /**
     * Optional: filter the stream to only certain VoiceEvent.payload arms
     * (e.g. "user_said,assistant_token"). Empty = all events.
     */
    eventFilter: string;
}
export declare const VoiceAgentRequest: {
    encode(message: VoiceAgentRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceAgentRequest;
    fromJSON(object: any): VoiceAgentRequest;
    toJSON(message: VoiceAgentRequest): unknown;
    create<I extends Exact<DeepPartial<VoiceAgentRequest>, I>>(base?: I): VoiceAgentRequest;
    fromPartial<I extends Exact<DeepPartial<VoiceAgentRequest>, I>>(object: I): VoiceAgentRequest;
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
//# sourceMappingURL=voice_agent_service.d.ts.map