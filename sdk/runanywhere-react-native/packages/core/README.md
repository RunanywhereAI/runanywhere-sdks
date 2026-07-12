# @runanywhere/core

Core SDK for RunAnywhere React Native. Foundation package providing the public API, events, model management, and native bridge infrastructure.

---

## Overview

`@runanywhere/core` is the foundation package of the RunAnywhere React Native SDK. It mirrors the Swift SDK's generated proto-byte/native ownership model from `sdk/runanywhere-swift/ARCHITECTURE.md` while exposing a TypeScript facade. It provides:

- **RunAnywhere API** — Main SDK singleton with all public methods
- **Tool Calling** — Register tools and let LLMs call them during generation
- **Structured Output** — Generate type-safe JSON responses with schema validation
- **SDK Events** — Native proto-byte event stream decoded into generated event types
- **Model Lifecycle** — Registry, download, import, delete, and load methods owned by native commons
- **Storage** — Cache and storage management through native `RunAnywhere` calls
- **Native Bridge** — Nitrogen/Nitro JSI bindings to C++ core
- **Error Handling** — Structured SDK errors with recovery suggestions
- **Logging** — Configurable logging with multiple levels

This package is **required** for all RunAnywhere functionality. Additional capabilities are provided by:
- `@runanywhere/llamacpp` — LLM text generation (GGUF models)
- `@runanywhere/mlx` — Apple MLX inference (LLM, VLM, speech, embeddings)
- `@runanywhere/onnx` — Speech-to-Text and Text-to-Speech

---

## Installation

```bash
npm install @runanywhere/core
# or
yarn add @runanywhere/core
```

### Peer Dependencies

Install the Nitro runtime with the package. Other optional peers remain in
package metadata for host-app compatibility, but SDK model download/storage does
not route through JavaScript file or blob-util helpers.

```bash
npm install react-native-nitro-modules
```

### iOS Setup

```bash
cd ios && pod install && cd ..
```

If your app uses the SDK's microphone capture (`AudioCaptureManager`, STT
recording), add a usage description to your app's `Info.plist` — iOS refuses
microphone access without it:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for speech recognition.</string>
```

### Android Setup

No additional setup required. The SDK's library manifest already declares
`android.permission.RECORD_AUDIO` for microphone capture; your app must still
request the runtime permission (handled automatically by
`AudioCaptureManager.requestPermission()`).

---

## Quick Start

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';

// Initialize SDK
await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});

// Check initialization
const isReady = RunAnywhere.isInitialized;
console.log('SDK ready:', isReady);

// Get SDK version
console.log('Version:', RunAnywhere.version);
```

---

## Hermes streaming

Hermes (the default JS engine in React Native since 0.70) does not support
`for await...of` with NitroModules-backed async iterables. Every SDK API
that returns an `AsyncIterable` must be consumed with a manual
`Symbol.asyncIterator` loop:

```typescript
const stream = RunAnywhere.generateStream(prompt);
const iterator = stream[Symbol.asyncIterator]();
while (true) {
  const { value, done } = await iterator.next();
  if (done) break;
  // handle value
}
```

**Affected surfaces** (every public `AsyncIterable` the core exposes):

| Surface | Yields |
|---------|--------|
| `RunAnywhere.generateStream(prompt, options)` | `LLMStreamEvent` (`token`, `completed`, `failed`, ...) |
| `RunAnywhere.transcribe(audio, options)` / `transcribeStream(...)` | `STTStreamEvent` |
| `RunAnywhere.synthesize(text, options)` / `synthesizeStream(...)` | `TTSStreamEvent` (audio chunks) |
| `RunAnywhere.processImage(request)` | `VLMStreamEvent` (vision-language tokens) |
| `RunAnywhere.downloadModel(id, onProgress?)` (when consumed as async iterable) | `DownloadProgress` |
| `RunAnywhere.voiceAgent.start(...)` | `VoiceEvent` |

Breaking out of the loop (`break` / `return` / `throw`) automatically
unsubscribes the underlying native subscription, so idiomatic "cancel by
breaking" behaviour is preserved. `for await` only works reliably when
Hermes is disabled (Node, plain JSC).

---

## API Reference

### RunAnywhere (Main API)

The `RunAnywhere` object is the main entry point for all SDK functionality.

#### Initialization

```typescript
// Initialize SDK
await RunAnywhere.initialize({
  apiKey?: string,           // API key (production/staging)
  baseURL?: string,          // API base URL
  environment?: SDKEnvironment,
  debug?: boolean,
});

// Check status
const isInit = RunAnywhere.isInitialized;
const isActive = RunAnywhere.isActive;

// Reset SDK
await RunAnywhere.reset();
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `boolean` | Whether SDK core initialization has completed |
| `isActive` | `boolean` | Whether SDK core is active |
| `areServicesReady` | `boolean` | Whether services are ready |
| `environment` | `SDKEnvironment \| null` | Current environment |
| `version` | `string` | SDK version |
| `deviceId` | `Promise<string>` | Persistent device ID |
| `events` | SDK event helpers | Subscribe to the native proto-byte event stream |

#### Model Management

```typescript
// Get available models
const models = await RunAnywhere.listModels();

// Get specific model info
const model = await RunAnywhere.getModel(ModelGetRequest.fromPartial({ modelId: 'model-id' }));

// List downloaded models
const downloaded = await RunAnywhere.downloadedModels();

// Download with progress
const iterator = RunAnywhere.downloadModel('model-id')[Symbol.asyncIterator]();
let next = await iterator.next();
while (!next.done) {
  const progress = next.value;
  console.log(`${(progress.progress * 100).toFixed(1)}%`);
  next = await iterator.next();
}

import { StorageDeleteRequest } from '@runanywhere/proto-ts/storage_types';

// Remove SDK-owned files through storage APIs when needed.
await RunAnywhere.deleteStorage(StorageDeleteRequest.fromPartial({
  modelId: 'model-id',
}));
```

#### Storage Management

```typescript
// Get storage info
const storage = await RunAnywhere.getStorageInfo();
console.log('Free:', storage?.device?.freeBytes ?? 0);
console.log('Used:', storage?.device?.usedBytes ?? 0);

// Clear cache
await RunAnywhere.clearCache();
await RunAnywhere.cleanTempFiles();
```

---

### Tool Calling

Register tools that LLMs can invoke during generation. Tool calling enables models to request external actions (API calls, device functions, calculations, etc.) and incorporate the results into their responses.

#### Register a Tool

```typescript
import { RunAnywhere } from '@runanywhere/core';

RunAnywhere.registerTool(
  {
    name: 'get_weather',
    description: 'Get the current weather for a location',
    parameters: [
      {
        name: 'location',
        type: 'string',
        description: 'City name or coordinates',
        required: true,
      },
      {
        name: 'units',
        type: 'string',
        description: 'Temperature units',
        required: false,
        enum: ['celsius', 'fahrenheit'],
      },
    ],
  },
  async (args) => {
    // Example app/tool code may call fetch; SDK internals use native C++ HTTP.
    const response = await fetch(`https://api.weather.com?q=${args.location}`);
    const data = await response.json();
    return { temperature: data.temp, condition: data.condition };
  }
);
```

#### Generate with Tools

```typescript
import { ToolCallFormatName } from '@runanywhere/proto-ts/tool_calling';

const result = await RunAnywhere.generateWithTools(
  'What is the weather in San Francisco?',
  {
    autoExecute: true,         // Automatically execute tool calls
    maxToolCalls: 3,           // Max tool invocations per turn
    temperature: 0.7,
    maxTokens: 512,
    format: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
    keepToolsAvailable: false, // Remove tools after first call
  }
);

console.log('Response:', result.text);
console.log('Tool calls made:', result.toolCalls.length);
console.log('Tool results:', result.toolResults);
```

#### Manual Tool Execution

```typescript
// Step-by-step control over tool execution
const result = await RunAnywhere.generateWithTools(prompt, {
  autoExecute: false, // Don't auto-execute
});

// Check if the LLM wants to call a tool
if (result.toolCalls.length > 0) {
  const toolCall = result.toolCalls[0];
  console.log(`LLM wants to call: ${toolCall.name}`);
  console.log('Arguments:', toolCall.argumentsJson);

  // Execute manually. JS owns only the executor callback; parsing and
  // validation stay in native commons.
  const toolResult = await RunAnywhere.executeTool(toolCall);
  console.log('Tool result:', toolResult.resultJson || toolResult.error);
}
```

#### Tool Calling Types

```typescript
import type { ToolExecutor } from '@runanywhere/core';
import type {
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  ToolCallingOptions,
  ToolCallingResult,
} from '@runanywhere/proto-ts/tool_calling';
```

---

### Structured Output

Generate type-safe JSON responses with schema validation.

#### Generate Structured Data

```typescript
import { RunAnywhere } from '@runanywhere/core';

// Generate JSON matching a schema
const result = await RunAnywhere.generateStructured(
  'Extract the product info: The new Widget Pro costs $29.99 and is available now',
  {
    type: 'object',
    properties: {
      name: { type: 'string', description: 'Product name' },
      price: { type: 'number', description: 'Price in USD' },
      inStock: { type: 'boolean' },
    },
    required: ['name', 'price'],
  },
  { temperature: 0.3, maxTokens: 256 }
);

console.log(result.rawText);
```

#### Parse Existing Text

```typescript
const parsed = await RunAnywhere.extractStructuredOutput(
  'John Smith from Acme Corp called about order #12345',
  {
    type: 'object',
    properties: {
      person: { type: 'string' },
      company: { type: 'string' },
      orderId: { type: 'string' },
    },
  }
);
console.log(parsed.rawText);
```

#### Structured Output Types

```typescript
import type {
  JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
```

---

### SDK Events

All SDK events (initialization, model lifecycle, generation, voice pipeline,
download progress, telemetry, ...) flow through a single native proto-byte
pipe owned by `runanywhere-commons`. Subscribe via
`RunAnywhere.subscribeSDKEvents(...)`, which decodes the bytes into a
generated `SDKEvent` proto message before handing them to your callback.

```typescript
import { RunAnywhere } from '@runanywhere/core';

const unsubscribe = await RunAnywhere.subscribeSDKEvents((event) => {
  // `event` is a decoded SDKEvent proto message.
  // Its `payload` oneof identifies the concrete event type
  // (generation, model, voice, download, telemetry, ...).
  console.log('SDK event:', event.payload?.$case, event);
});

// Later, when you no longer care about events:
await unsubscribe();
```

Audio-session internals may publish local events, but consumers must use
`RunAnywhere.subscribeSDKEvents(...)` for SDK event observation.

---

### Model Registry And Downloads

The public registry surface lives on `RunAnywhere` and mirrors Swift naming:
`registerModel`, `listModels`, `queryModels`, `getModel`, `downloadedModels`,
`importModel`, `downloadModel`, `loadModel(ModelLoadRequest)`,
`unloadModel(ModelUnloadRequest)`, and `currentModel(CurrentModelRequest)`.
The registry and download state live in native
commons; React Native encodes requests and decodes generated proto responses.

```typescript
await RunAnywhere.registerModel({
  id: 'my-model',
  name: 'My Model',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  url: 'https://...',
});

const models = await RunAnywhere.listModels();
const downloaded = await RunAnywhere.downloadedModels();
const model = await RunAnywhere.getModel(ModelGetRequest.fromPartial({ modelId: 'my-model' }));

const iterator = RunAnywhere.downloadModel('my-model')[Symbol.asyncIterator]();
let next = await iterator.next();
while (!next.done) {
  console.log(`Progress: ${next.value.progress * 100}%`);
  next = await iterator.next();
}
```

---

### Storage

Use the `RunAnywhere` storage and model lifecycle methods for SDK-owned data.
Direct host-app file helpers are separate from model management.

```typescript
const storage = await RunAnywhere.getStorageInfo();
await RunAnywhere.clearCache();
await RunAnywhere.cleanTempFiles();
```

---

### Error Handling

```typescript
import {
  SDKException,
  isSDKException,
  asSDKException,
  ErrorCode,
  ErrorCategory,
} from '@runanywhere/core';

try {
  await RunAnywhere.generate('Hello');
} catch (error) {
  if (isSDKException(error)) {
    console.log('Code:', error.code);          // ErrorCode (proto enum)
    console.log('Category:', error.category);  // ErrorCategory (proto enum)
    console.log('cAbiCode:', error.cAbiCode);  // optional negative rac_result_t
    console.log('Context:', error.context);    // optional ErrorContext
  } else {
    // Coerce non-SDKException values (Error / string / unknown) into one.
    const sdkError = asSDKException(error);
    console.log('Code:', sdkError.code);
  }
}

// Create errors via the static factories on SDKException.
throw SDKException.notInitialized();
throw SDKException.modelNotFound('model-id');
throw SDKException.of(ErrorCode.ERROR_CODE_INVALID_INPUT, 'Prompt is empty');
```

---

### Logging

`SDKLogger` and `LogLevel` are part of the internal subpath
(`@runanywhere/core/internal`) and not the stable root surface — the API may
change between releases. Import from the internal subpath explicitly if you
need them, otherwise prefer console/your own logger plus the EventBus stream
for stable observability.

```typescript
import { SDKLogger, LogLevel } from '@runanywhere/core/internal';

// Set global log level
RunAnywhere.setLogLevel(LogLevel.LOG_LEVEL_DEBUG);

// Create custom logger
const logger = new SDKLogger('MyModule');
logger.debug('Debug message', { data: 'value' });
logger.info('Info message');
logger.warning('Warning message');
logger.error('Error message', new Error('...'));
```

---

## Types

### Enums

Only `SDKEnvironment` is re-exported from the `@runanywhere/core` root barrel.
All other generated enums (`ExecutionTarget`, `InferenceFramework`,
`ModelCategory`, `ModelFormat`, `HardwareAcceleration`, `ComponentState`, …)
live in `@runanywhere/proto-ts/model_types` and should be imported directly
from there.

```typescript
import { SDKEnvironment } from '@runanywhere/core';
import {
  ExecutionTarget,
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  HardwareAcceleration,
  ComponentState,
} from '@runanywhere/proto-ts/model_types';
```

### Interfaces

The `@runanywhere/core` root barrel exports `SDKInitOptions`, `ToolExecutor`,
`EventBus` types (`EventBusCancellable`, `SDKEventHandler`), and the plugin
loader types (`PluginInfo`, `PluginLoaderCapability`). All other interfaces are
proto-generated DTOs and should be imported from `@runanywhere/proto-ts/*`:

```typescript
import type {
  SDKInitOptions,
  ToolExecutor,
  EventBusCancellable,
  SDKEventHandler,
  PluginInfo,
  PluginLoaderCapability,
} from '@runanywhere/core';

import type {
  // Models
  ModelInfo,
  StorageInfo,
  // Generation
  LLMGenerationOptions,
  LLMGenerationResult,
  PerformanceMetrics,
  // Download
  DownloadProgress,
} from '@runanywhere/proto-ts/model_types';

import type {
  STTOptions,
  STTResult,
} from '@runanywhere/proto-ts/stt_options';

import type {
  TTSConfiguration,
  TTSResult,
} from '@runanywhere/proto-ts/tts_options';

import type {
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  RegisteredTool,
  ToolCallingOptions,
  ToolCallingResult,
  JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  EntityExtractionResult,
  ClassificationResult,
} from '@runanywhere/proto-ts/llm_options';

import type {
  SDKEvent,
  SDKGenerationEvent,
  SDKModelEvent,
  SDKVoiceEvent,
} from '@runanywhere/proto-ts/sdk_events';
```

---

## Package Structure

```
packages/core/
├── src/
│   ├── index.ts                    # Public package exports (RunAnywhere
│   │                               #   facade + SDKException + proto re-exports)
│   ├── internal.ts                 # `@runanywhere/core/internal` provider /
│   │                               #   plugin plumbing
│   ├── Public/
│   │   ├── RunAnywhere.ts          # Main API singleton
│   │   ├── Events/                 # EventBus (public)
│   │   └── Extensions/             # API method implementations
│   │       ├── LLM/RunAnywhere+TextGeneration.ts
│   │       ├── LLM/RunAnywhere+ToolCalling.ts
│   │       ├── LLM/RunAnywhere+StructuredOutput.ts
│   │       ├── LLM/RunAnywhere+LoRA.ts
│   │       ├── STT/RunAnywhere+STT.ts
│   │       ├── TTS/RunAnywhere+TTS.ts
│   │       ├── VAD/RunAnywhere+VAD.ts
│   │       ├── VLM/RunAnywhere+VisionLanguage.ts
│   │       ├── VoiceAgent/RunAnywhere+VoiceAgent.ts
│   │       ├── Models/             # Model lifecycle + downloads
│   │       ├── Storage/RunAnywhere+Storage.ts
│   │       ├── Solutions/          # Convenience solutions
│   │       ├── RAG/RunAnywhere+RAG.ts
│   │       ├── RunAnywhere+Hardware.ts
│   │       ├── RunAnywhere+Logging.ts
│   │       └── RunAnywhere+PluginLoader.ts
│   ├── Foundation/
│   │   ├── Constants/              # Config defaults
│   │   ├── Errors/                 # SDKException + proto re-exports
│   │   ├── Initialization/         # Init state machine
│   │   └── Logging/                # SDKLogger
│   ├── Adapters/                   # VoiceAgent stream adapter
│   ├── Features/
│   │   └── VoiceSession/           # Voice session + audio playback
│   ├── Internal/
│   │   └── Nitro/                  # NitroModules accessor wrappers
│   ├── services/
│   │   ├── ProtoBytes.ts           # ArrayBuffer/protobuf conversion
│   │   └── Network/                # Telemetry/config wrappers
│   ├── specs/                      # Nitro HybridObject TS specs
│   ├── types/                      # TypeScript-only call-site types
│   │   ├── models.ts               # Registry + init shapes
│   │   └── external.d.ts           # External module declarations
│   └── native/                     # NitroModules native module access
├── cpp/                            # C++ HybridObject bridges
│   ├── HybridRunAnywhereCore.cpp   # Core native bridge
│   └── bridges/                    # Platform adapters and native ABI bridges
├── ios/                            # iOS native module
├── android/                        # Android native module
└── nitrogen/                       # Generated Nitro specs
```

---

## Native Integration

This package includes native bindings via Nitrogen/Nitro for:

- **RACommons** — Core C++ infrastructure
- **PlatformAdapter** — Platform-specific implementations
- **SecureStorage** — Keychain (iOS) / Android Keystore-backed storage (Android)
- **SDKLogger** — Native logging
- **AudioDecoder** — Audio file decoding

### iOS

The package uses the bundled `ios/Binaries/RACommons.xcframework` staged from
the Swift-shaped native binary layout.

### Android

Native libraries (`librac_commons.so`, `librunanywhere_jni.so`) are staged into
`android/src/main/jniLibs/`.

---

## See Also

- [Main SDK README](../../README.md) — Full SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API docs
- [@runanywhere/llamacpp](../llamacpp/README.md) — LLM backend
- [@runanywhere/mlx](../mlx/README.md) — Apple MLX backend
- [@runanywhere/onnx](../onnx/README.md) — STT/TTS backend

---

## License

RunAnywhere License. See [LICENSE](LICENSE) for details.
