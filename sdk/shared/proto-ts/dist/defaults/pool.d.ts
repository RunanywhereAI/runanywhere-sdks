/** Central default pool. Read these instead of retyping a literal. */
export declare const networkDefaults: Readonly<{
    requestTimeoutMs: number;
    resourceTimeoutMs: number;
    streamingTimeoutMs: number;
    adapterTimeoutMs: number;
    connectTimeoutMs: number;
    streamChunkBytes: number;
    maxRetries: number;
    retryBackoffBaseMs: number;
}>;
export declare const connectDefaults: Readonly<{
    connectTimeoutMs: number;
    generationReadTimeoutMs: number;
}>;
export declare const audioCaptureDefaults: Readonly<{
    micSampleRateHz: number;
    micChannels: number;
    micChannelCapacity: number;
    micTapBufferFrames: number;
    ttsSampleRateHz: number;
}>;
export declare const voiceAgentDefaults: Readonly<{
    maxTokens: number;
    temperature: number;
    defaultVadModelId: string;
    speechRmsThreshold: number;
    speechFloorMultiplier: number;
}>;
export declare const hybridDefaults: Readonly<{
    sttConfidenceThreshold: number;
}>;
export declare const workerDefaults: Readonly<{
    handshakeTimeoutMs: number;
    backendInitTimeoutMs: number;
}>;
export declare const fFIDefaults: Readonly<{
    pathBufferBytes: number;
}>;
export declare const environmentDefaults: Readonly<{
    productionBaseUrl: string;
    developmentBaseUrl: string;
    developmentPlaceholderUrl: string;
}>;
export declare const structuredOutputDefaults: Readonly<{
    maxTokens: number;
    temperature: number;
}>;
export declare const storageDefaults: Readonly<{
    contextLength: number;
}>;
