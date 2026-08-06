// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_defaults_pool.py
//
// Values come from `(runanywhere.v1.rac_default)` annotations in
// idl/sdk_defaults.proto. That file is the single declaration of every default
// here; the C header and the other three SDK languages are generated from
// the same annotations, so editing this copy only desynchronizes one SDK.

/// Central default pool. Read these instead of retyping a literal.
public enum RADefaults {
    public enum Network {
        public static let requestTimeoutMs: Int = 60000
        public static let resourceTimeoutMs: Int = 600000
        public static let streamingTimeoutMs: Int = 86400000
        public static let adapterTimeoutMs: Int = 30000
        public static let connectTimeoutMs: Int = 30000
        public static let streamChunkBytes: Int = 262144
        public static let maxRetries: Int = 3
        public static let retryBackoffBaseMs: Int = 100
    }

    public enum Connect {
        public static let connectTimeoutMs: Int = 5000
        public static let generationReadTimeoutMs: Int = 120000
    }

    public enum AudioCapture {
        public static let micSampleRateHz: Int = 16000
        public static let micChannels: Int = 1
        public static let micChannelCapacity: Int = 128
        public static let ttsSampleRateHz: Int = 22050
    }

    public enum VoiceAgent {
        public static let maxTokens: Int = 96
        public static let temperature: Float = 0.0
        public static let defaultVadModelID: String = "silero-vad"
        public static let speechRmsThreshold: Float = 0.015
        public static let speechFloorMultiplier: Float = 2.0
    }

    public enum Hybrid {
        public static let sttConfidenceThreshold: Float = 0.5
    }

    public enum Worker {
        public static let handshakeTimeoutMs: Int = 10000
        public static let backendInitTimeoutMs: Int = 120000
    }

    public enum FFI {
        public static let pathBufferBytes: Int = 1024
    }

    public enum Environment {
        public static let productionBaseUrl: String = "https://api.runanywhere.ai"
        public static let developmentBaseUrl: String = "https://dev-api.runanywhere.ai"
        public static let developmentPlaceholderUrl: String = "https://dev.runanywhere.local"
    }

    public enum StructuredOutput {
        public static let maxTokens: Int = 512
        public static let temperature: Float = 0.0
    }

    public enum Storage {
        public static let contextLength: Int = 2048
    }
}
