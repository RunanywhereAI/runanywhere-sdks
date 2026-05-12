# @runanywhere/core

Core SDK for RunAnywhere React Native. Foundation package providing the public API, events, model management, and native bridge infrastructure.

---

## Overview

`@runanywhere/core` is the foundation package of the RunAnywhere React Native SDK. It provides:

- **RunAnywhere API** — Main SDK singleton with all public methods
- **Tool Calling** — Register tools and let LLMs call them during generation
- **Structured Output** — Generate type-safe JSON responses with schema validation
- **EventBus** — Event subscription system for SDK events
- **ModelRegistry** — Model metadata management and discovery
- **DownloadService** — Model downloads with progress and resume
- **FileSystem** — Cross-platform file operations
- **Native Bridge** — Nitrogen/Nitro JSI bindings to C++ core
- **Error Handling** — Structured SDK errors with recovery suggestions
- **Logging** — Configurable logging with multiple levels

This package is **required** for all RunAnywhere functionality. Additional capabilities are provided by:
- `@runanywhere/llamacpp` — LLM text generation (GGUF models)
- `@runanywhere/onnx` — Speech-to-Text and Text-to-Speech

---

## Installation

```bash
npm install @runanywhere/core
# or
yarn add @runanywhere/core
```

### Peer Dependencies

The following peer dependencies are optional but recommended:

```bash
npm install react-native-nitro-modules react-native-fs react-native-blob-util react-native-device-info react-native-zip-archive
```

### iOS Setup

```bash
cd ios && pod install && cd ..
```

### Android Setup

No additional setup required.

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
const isActive = RunAnywhere.isSDKInitialized;

// Reset SDK
await RunAnywhere.reset();
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isSDKInitialized` | `boolean` | Whether SDK is initialized |
| `areServicesReady` | `boolean` | Whether services are ready |
| `currentEnvironment` | `SDKEnvironment` | Current environment |
| `version` | `string` | SDK version |
| `deviceId` | `string` | Persistent device ID |
| `events` | `EventBus` | Event subscription system |

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

// Delete model
await RunAnywhere.deleteModel('model-id');
```

#### Storage Management

```typescript
// Get storage info
const storage = await RunAnywhere.getStorageInfo();
console.log('Free:', storage.freeSpace);
console.log('Used:', storage.usedSpace);

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
const result = await RunAnywhere.generateWithTools(
  'What is the weather in San Francisco?',
  {
    autoExecute: true,         // Automatically execute tool calls
    maxToolCalls: 3,           // Max tool invocations per turn
    temperature: 0.7,
    maxTokens: 512,
    format: 'default',         // 'default' or 'lfm2' for Liquid AI models
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
  console.log(`LLM wants to call: ${toolCall.toolName}`);
  console.log('Arguments:', toolCall.arguments);

  // Execute manually
  const toolResult = await RunAnywhere.executeTool(
    toolCall.toolName,
    toolCall.arguments
  );

  // Continue generation with the tool result
  const finalResult = await RunAnywhere.continueWithToolResult(
    prompt,
    toolCall.toolName,
    toolResult
  );
  console.log('Final response:', finalResult.text);
}
```

#### Tool Calling Types

```typescript
import type {
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  ToolExecutor,
  RegisteredTool,
  ToolCallingOptions,
  ToolCallingResult,
} from '@runanywhere/core';
```

---

### Structured Output

Generate type-safe JSON responses with schema validation.

#### Generate Structured Data

```typescript
import { RunAnywhere } from '@runanywhere/core';

// Generate JSON matching a schema
const result = await RunAnywhere.generateStructured(
  {
    type: 'object',
    properties: {
      name: { type: 'string', description: 'Product name' },
      price: { type: 'number', description: 'Price in USD' },
      inStock: { type: 'boolean' },
    },
    required: ['name', 'price'],
  },
  'Extract the product info: The new Widget Pro costs $29.99 and is available now',
  { temperature: 0.3, maxTokens: 256 }
);

console.log(result.data); // { name: "Widget Pro", price: 29.99, inStock: true }
```

#### Extract Entities

```typescript
const entities = await RunAnywhere.extractEntities(
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
// { entities: { person: "John Smith", company: "Acme Corp", orderId: "12345" }, confidence: 0.95 }
```

#### Classify Text

```typescript
const classification = await RunAnywhere.classify(
  'I love this product! Best purchase ever.',
  ['positive', 'negative', 'neutral']
);
// { category: "positive", confidence: 0.97 }
```

#### Structured Output Types

```typescript
import type {
  JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  EntityExtractionResult,
  ClassificationResult,
} from '@runanywhere/core';
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

The in-process `EventBus` export is a publish-only façade used internally
by the audio managers — it has no `on*` subscribers. Consumers must use
`RunAnywhere.subscribeSDKEvents(...)` for all event observation.

---

### Model Registry And Downloads

The public registry surface lives on `RunAnywhere` and mirrors Swift naming:
`registerModel`, `listModels`, `queryModels`, `getModel`, `downloadedModels`,
`importModel`, `downloadModel`, `cancelDownload`, `deleteModel`, and
`loadModel(ModelLoadRequest)`.

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

### FileSystem

Cross-platform file operations.

```typescript
import { FileSystem } from '@runanywhere/core';

// Check availability
if (FileSystem.isAvailable()) {
  // Get directories
  const docs = FileSystem.getDocumentsDirectory();
  const cache = FileSystem.getCacheDirectory();

  // Model operations
  const exists = await FileSystem.modelExists('model-id', 'LlamaCpp');
  const path = await FileSystem.getModelPath('model-id', 'LlamaCpp');

  // File operations
  const fileExists = await FileSystem.exists('/path/to/file');
  const size = await FileSystem.getFileSize('/path/to/file');
  await FileSystem.deleteFile('/path/to/file');
}
```

---

### Error Handling

```typescript
import {
  SDKError,
  SDKErrorCode,
  isSDKError,
  notInitializedError,
  modelNotFoundError,
} from '@runanywhere/core';

try {
  await RunAnywhere.generate('Hello');
} catch (error) {
  if (isSDKError(error)) {
    console.log('Code:', error.code);
    console.log('Category:', error.category);
    console.log('Suggestion:', error.recoverySuggestion);
  }
}

// Create errors
throw notInitializedError();
throw modelNotFoundError('model-id');
```

---

### Logging

```typescript
import { SDKLogger, LogLevel } from '@runanywhere/core';

// Set global log level
RunAnywhere.setLogLevel(LogLevel.Debug);

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

```typescript
import {
  SDKEnvironment,
  ExecutionTarget,
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  HardwareAcceleration,
  ComponentState,
} from '@runanywhere/core';
```

### Interfaces

```typescript
import type {
  // Models
  ModelInfo,
  StorageInfo,

  // Generation (proto-generated)
  LLMGenerationOptions,
  LLMGenerationResult,
  PerformanceMetrics,

  // Tool Calling
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  ToolExecutor,
  RegisteredTool,
  ToolCallingOptions,
  ToolCallingResult,

  // Structured Output
  JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  EntityExtractionResult,
  ClassificationResult,

  // Voice
  STTOptions,
  STTResult,
  TTSConfiguration,
  TTSResult,
  VADConfiguration,

  // Events
  SDKEvent,
  SDKGenerationEvent,
  SDKModelEvent,
  SDKVoiceEvent,

  // Download
  DownloadProgress,
} from '@runanywhere/core';
```

---

## Package Structure

```
packages/core/
├── src/
│   ├── index.ts                    # Package exports
│   ├── Public/
│   │   ├── RunAnywhere.ts          # Main API singleton
│   │   ├── Events/
│   │   │   └── EventBus.ts         # Event pub/sub
│   │   └── Extensions/             # API method implementations
│   │       ├── LLM/RunAnywhere+TextGeneration.ts
│   │       ├── LLM/RunAnywhere+ToolCalling.ts
│   │       ├── LLM/RunAnywhere+StructuredOutput.ts
│   │       ├── STT/RunAnywhere+STT.ts
│   │       ├── TTS/RunAnywhere+TTS.ts
│   │       ├── VAD/RunAnywhere+VAD.ts
│   │       ├── VoiceAgent/RunAnywhere+VoiceAgent.ts
│   │       └── ...
│   ├── Foundation/
│   │   ├── ErrorTypes/             # SDK errors
│   │   ├── Initialization/         # Init state machine
│   │   ├── Security/               # Secure storage
│   │   ├── Logging/                # Logger
│   │   └── DependencyInjection/    # Service registry
│   ├── Infrastructure/
│   │   └── Events/                 # Event internals
│   ├── Features/
│   │   └── VoiceSession/           # Voice session
│   ├── services/
│   │   ├── ModelRegistry.ts        # Model metadata
│   │   ├── DownloadService.ts      # Downloads
│   │   ├── FileSystem.ts           # File ops
│   │   └── Network/                # HTTP, telemetry
│   ├── types/                      # TypeScript types
│   │   ├── enums.ts                # RN-only enums + proto re-exports
│   │   ├── LLMTypes.ts             # RN-local LLM streaming primitives
│   │   ├── models.ts               # Registry + init shapes
│   │   └── ...                     # Tool / structured-output types
│   │                               #   come from @runanywhere/proto-ts
│   └── native/                     # Native module access
├── cpp/                            # C++ HybridObject bridges
│   ├── HybridRunAnywhereCore.cpp   # Core native bridge
│   └── bridges/                    # Platform adapters and legacy JSON RAG bridge
├── ios/                            # iOS native module
├── android/                        # Android native module
└── nitrogen/                       # Generated Nitro specs
```

---

## Native Integration

This package includes native bindings via Nitrogen/Nitro for:

- **RACommons** — Core C++ infrastructure
- **PlatformAdapter** — Platform-specific implementations
- **SecureStorage** — Keychain (iOS) / EncryptedSharedPreferences (Android)
- **SDKLogger** — Native logging
- **AudioDecoder** — Audio file decoding

### iOS

The package uses `RACommons.xcframework` which is automatically downloaded during `pod install`.

### Android

Native libraries (`librac_commons.so`, `librunanywhere_jni.so`) are automatically downloaded during Gradle build.

---

## See Also

- [Main SDK README](../../README.md) — Full SDK documentation
- [API Reference](../../Docs/Documentation.md) — Complete API docs
- [@runanywhere/llamacpp](../llamacpp/README.md) — LLM backend
- [@runanywhere/onnx](../onnx/README.md) — STT/TTS backend

---

## License

MIT License
