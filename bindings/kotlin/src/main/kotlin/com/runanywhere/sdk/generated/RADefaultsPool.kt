// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE — DO NOT EDIT.
// Regenerate with: idl/codegen/generate_defaults_pool.py
//
// Values come from `(runanywhere.v1.rac_default)` annotations in
// idl/sdk_defaults.proto. That file is the single declaration of every default
// here; the C header and the other three SDK languages are generated from
// the same annotations, so editing this copy only desynchronizes one SDK.

package com.runanywhere.sdk.generated

/** Central default pool. Read these instead of retyping a literal. */
public object RADefaults {
    public object Network {
        public const val REQUEST_TIMEOUT_MS: Int = 60000
        public const val RESOURCE_TIMEOUT_MS: Int = 600000
        public const val STREAMING_TIMEOUT_MS: Int = 86400000
        public const val ADAPTER_TIMEOUT_MS: Int = 30000
        public const val CONNECT_TIMEOUT_MS: Int = 30000
        public const val STREAM_CHUNK_BYTES: Int = 262144
        public const val MAX_RETRIES: Int = 3
        public const val RETRY_BACKOFF_BASE_MS: Int = 100
    }

    public object Connect {
        public const val CONNECT_TIMEOUT_MS: Int = 5000
        public const val GENERATION_READ_TIMEOUT_MS: Int = 120000
    }

    public object AudioCapture {
        public const val MIC_SAMPLE_RATE_HZ: Int = 16000
        public const val MIC_CHANNELS: Int = 1
        public const val MIC_CHANNEL_CAPACITY: Int = 128
        public const val TTS_SAMPLE_RATE_HZ: Int = 22050
    }

    public object VoiceAgent {
        public const val MAX_TOKENS: Int = 96
        public const val TEMPERATURE: Float = 0.0f
        public const val DEFAULT_VAD_MODEL_ID: String = "silero-vad"
        public const val SPEECH_RMS_THRESHOLD: Float = 0.015f
        public const val SPEECH_FLOOR_MULTIPLIER: Float = 2.0f
    }

    public object Hybrid {
        public const val STT_CONFIDENCE_THRESHOLD: Float = 0.5f
    }

    public object Worker {
        public const val HANDSHAKE_TIMEOUT_MS: Int = 10000
        public const val BACKEND_INIT_TIMEOUT_MS: Int = 120000
    }

    public object FFI {
        public const val PATH_BUFFER_BYTES: Int = 1024
    }

    public object Environment {
        public const val PRODUCTION_BASE_URL: String = "https://api.runanywhere.ai"
        public const val DEVELOPMENT_BASE_URL: String = "https://dev-api.runanywhere.ai"
        public const val DEVELOPMENT_PLACEHOLDER_URL: String = "https://dev.runanywhere.local"
    }

    public object StructuredOutput {
        public const val MAX_TOKENS: Int = 512
        public const val TEMPERATURE: Float = 0.0f
    }

    public object Storage {
        public const val CONTEXT_LENGTH: Int = 2048
    }
}
