"""Central default pool generated from idl/sdk_defaults.proto."""

from __future__ import annotations

# GENERATED FILE - DO NOT EDIT.
# Regenerate with: idl/codegen/generate_defaults_pool.py
#
# Values come from `(runanywhere.v1.rac_default)` annotations. Change the
# value in idl/sdk_defaults.proto, not here.

from typing import Final


class NetworkDefaults:
    """Generated from NetworkDefaults in idl/sdk_defaults.proto."""

    REQUEST_TIMEOUT_MS: Final[int] = 60000
    RESOURCE_TIMEOUT_MS: Final[int] = 600000
    STREAMING_TIMEOUT_MS: Final[int] = 86400000
    ADAPTER_TIMEOUT_MS: Final[int] = 30000
    CONNECT_TIMEOUT_MS: Final[int] = 30000
    STREAM_CHUNK_BYTES: Final[int] = 262144
    MAX_RETRIES: Final[int] = 3
    RETRY_BACKOFF_BASE_MS: Final[int] = 100


class ConnectDefaults:
    """Generated from ConnectDefaults in idl/sdk_defaults.proto."""

    CONNECT_TIMEOUT_MS: Final[int] = 5000
    GENERATION_READ_TIMEOUT_MS: Final[int] = 120000


class AudioCaptureDefaults:
    """Generated from AudioCaptureDefaults in idl/sdk_defaults.proto."""

    MIC_SAMPLE_RATE_HZ: Final[int] = 16000
    MIC_CHANNELS: Final[int] = 1
    MIC_CHANNEL_CAPACITY: Final[int] = 128
    TTS_SAMPLE_RATE_HZ: Final[int] = 22050


class VoiceAgentDefaults:
    """Generated from VoiceAgentDefaults in idl/sdk_defaults.proto."""

    MAX_TOKENS: Final[int] = 96
    TEMPERATURE: Final[float] = 0.0
    DEFAULT_VAD_MODEL_ID: Final[str] = "silero-vad"
    SPEECH_RMS_THRESHOLD: Final[float] = 0.015
    SPEECH_FLOOR_MULTIPLIER: Final[float] = 2.0


class HybridDefaults:
    """Generated from HybridDefaults in idl/sdk_defaults.proto."""

    STT_CONFIDENCE_THRESHOLD: Final[float] = 0.5


class WorkerDefaults:
    """Generated from WorkerDefaults in idl/sdk_defaults.proto."""

    HANDSHAKE_TIMEOUT_MS: Final[int] = 10000
    BACKEND_INIT_TIMEOUT_MS: Final[int] = 120000


class FFIDefaults:
    """Generated from FFIDefaults in idl/sdk_defaults.proto."""

    PATH_BUFFER_BYTES: Final[int] = 1024


class EnvironmentDefaults:
    """Generated from EnvironmentDefaults in idl/sdk_defaults.proto."""

    PRODUCTION_BASE_URL: Final[str] = "https://api.runanywhere.ai"
    DEVELOPMENT_BASE_URL: Final[str] = "https://dev-api.runanywhere.ai"
    DEVELOPMENT_PLACEHOLDER_URL: Final[str] = "https://dev.runanywhere.local"


class StructuredOutputDefaults:
    """Generated from StructuredOutputDefaults in idl/sdk_defaults.proto."""

    MAX_TOKENS: Final[int] = 512
    TEMPERATURE: Final[float] = 0.0


class StorageDefaults:
    """Generated from StorageDefaults in idl/sdk_defaults.proto."""

    CONTEXT_LENGTH: Final[int] = 2048


__all__ = ["NetworkDefaults", "ConnectDefaults", "AudioCaptureDefaults", "VoiceAgentDefaults", "HybridDefaults", "WorkerDefaults", "FFIDefaults", "EnvironmentDefaults", "StructuredOutputDefaults", "StorageDefaults"]
