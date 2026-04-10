# Sarvam AI Backend

Cloud-based speech-to-text backend using the Sarvam AI API (Saarika model).

## Overview

This backend provides STT capabilities via Sarvam AI's cloud API. It registers as a low-priority provider (priority 10) in the service registry, making it a fallback when local on-device backends are unavailable.

## Supported Capabilities

| Capability | Status | Notes |
|------------|--------|-------|
| STT | Supported | Batch transcription via Saarika v1/v2 |
| TTS | Not yet | Planned (Bulbul model) |
| Translation | Not yet | Planned (Mayura model) |

## API Reference

### Setup

```c
#include "rac/backends/rac_stt_sarvam.h"

// Set API key (required before creating a service)
rac_stt_sarvam_set_api_key("your-api-subscription-key");

// Register backend with service registry
rac_backend_sarvam_register();
```

### Direct Usage

```c
// Create service with default config
rac_handle_t handle = NULL;
rac_stt_sarvam_create(NULL, &handle);

// Or with custom config
rac_stt_sarvam_config_t config = RAC_STT_SARVAM_CONFIG_DEFAULT;
config.model = RAC_STT_SARVAM_MODEL_SAARIKA_V2;
config.language_code = "hi-IN";
config.with_timestamps = RAC_TRUE;
config.timeout_ms = 60000;
rac_stt_sarvam_create(&config, &handle);

// Transcribe PCM Int16 audio (16kHz, mono)
rac_stt_result_t result = {};
rac_stt_sarvam_transcribe(handle, pcm_data, pcm_size, NULL, &result);

printf("Transcript: %s\n", result.text);
printf("Language: %s\n", result.detected_language);

// Cleanup
rac_stt_result_free(&result);
rac_stt_sarvam_destroy(handle);
```

### Via Service Registry

```c
// After rac_backend_sarvam_register(), use the standard service API
rac_service_request_t request = {};
request.identifier = "sarvam:saarika:v2";
request.capability = RAC_CAPABILITY_STT;
request.framework = RAC_FRAMEWORK_SARVAM;

rac_handle_t service = NULL;
rac_service_create(RAC_CAPABILITY_STT, &request, &service);
```

## Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `model` | `rac_stt_sarvam_model_t` | `SAARIKA_V2` | Model variant |
| `language_code` | `const char*` | `"en-IN"` | Language code |
| `with_timestamps` | `rac_bool_t` | `RAC_FALSE` | Word-level timestamps |
| `with_diarization` | `rac_bool_t` | `RAC_FALSE` | Speaker diarization |
| `timeout_ms` | `int32_t` | `30000` | HTTP request timeout |

## Supported Languages

`en-IN`, `hi-IN`, `bn-IN`, `ta-IN`, `te-IN`, `mr-IN`, `kn-IN`, `gu-IN`, `ml-IN`, `pa-IN`, `od-IN`, `ur-IN`

## Audio Requirements

- Format: PCM Int16 (converted to WAV internally)
- Sample rate: 16kHz
- Channels: Mono
- Max duration: 2 minutes per request

## Build

Enable the backend in CMake:

```bash
cmake -B build \
  -DRAC_BUILD_BACKENDS=ON \
  -DRAC_BACKEND_SARVAM=ON \
  -DRAC_BUILD_TESTS=ON

cmake --build build
```

## Tests

```bash
# Run all sarvam tests
./build/tests/test_stt_sarvam --run-all

# Run specific test
./build/tests/test_stt_sarvam --test-wav_encoding
./build/tests/test_stt_sarvam --test-transcribe_with_mock_http
```

## Architecture

```
rac_stt_sarvam.h          Public C API (create, configure, transcribe, destroy)
rac_stt_sarvam.cpp         Implementation (WAV encoding, multipart, HTTP, JSON parsing)
rac_backend_sarvam_register.cpp   Vtable + service registry registration
```

The backend uses the platform HTTP executor (`rac_http_executor_t`) for network requests. The platform SDK (Swift/Kotlin) provides the actual HTTP transport implementation.

## Dependencies

- `nlohmann/json` for JSON response parsing
- `rac_commons` for core types, logging, HTTP client, service registry
