# RunAnywhere React Native SDK - Components

This directory contains the component architecture for the RunAnywhere React Native SDK, following the exact patterns from the Swift SDK.

## Architecture Overview

The component architecture follows a clean, layered design:

```
┌─────────────────────────────────────────────────────┐
│              Application Layer                       │
│  (Uses STTComponent, TTSComponent, etc.)            │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│           Component Layer (TypeScript)               │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐      │
│  │    STT     │ │    TTS     │ │    LLM     │      │
│  │ Component  │ │ Component  │ │ Component  │      │
│  └────────────┘ └────────────┘ └────────────┘      │
│         │              │              │             │
│         └──────────────┴──────────────┘             │
│                       │                             │
│              ┌────────────────┐                     │
│              │ BaseComponent  │                     │
│              │ (Abstract)     │                     │
│              └────────────────┘                     │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│          Service Layer (Native Bridge)               │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐      │
│  │NativeSTT   │ │NativeTTS   │ │NativeLLM   │      │
│  │Service     │ │Service     │ │Service     │      │
│  └────────────┘ └────────────┘ └────────────┘      │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│         Native Layer (C++ TurboModule)               │
│             NativeRunAnywhere.ts                     │
└─────────────────────────────────────────────────────┘
```

## Files

### 1. `BaseComponent.ts`

Abstract base class that all SDK components extend.

**Key Features:**
- Lifecycle management (notInitialized → initializing → ready → error)
- State tracking with ComponentState enum
- Event emission for state changes
- Service creation pattern
- Cleanup and resource management

**Reference:** `sdk/runanywhere-swift/Sources/RunAnywhere/Core/Components/BaseComponent.swift`

**Protocols/Interfaces:**
- `Component` - Core component interface
- `ServiceComponent<T>` - Components that provide services
- `ComponentInput` - Base for component inputs
- `ComponentOutput` - Base for component outputs
- `ComponentConfiguration` - Base for configurations
- `ComponentInitParameters` - Initialization parameters

### 2. `STT/STTComponent.ts`

Speech-to-Text component extending BaseComponent.

**Key Features:**
- Batch transcription (`transcribe()`)
- Streaming transcription (`liveTranscribe()`)
- Service wrapper pattern (`STTServiceWrapper`)
- Native service implementation (`NativeSTTService`)
- Configuration with validation
- Strong typing for all inputs/outputs

**Reference:** `sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift`

**Main Classes:**
- `STTComponent` - Main component class
- `STTServiceWrapper` - Service wrapper
- `NativeSTTService` - Native bridge implementation

**Interfaces:**
- `STTConfiguration` - Component configuration
- `STTInput` - Input for transcription
- `STTOutput` - Output with transcription results
- `STTService` - Service protocol/interface

## Component Lifecycle

Every component follows this lifecycle:

```typescript
// 1. Create component with configuration
const config = createSTTConfiguration({
  language: 'en-US',
  enablePunctuation: true,
});

const component = new STTComponent(config);

// 2. Initialize (triggers lifecycle)
await component.initialize();
// State: notInitialized → initializing → ready

// 3. Use component
const result = await component.transcribe(audioData);

// 4. Cleanup
await component.cleanup();
// State: ready → cleaningUp → notInitialized
```

### State Flow

```
notInitialized
      │
      ▼ initialize()
initializing
      │
      ├─ validation
      ├─ service_creation
      └─ service_initialization
      │
      ▼ (success)
    ready
      │
      ▼ cleanup()
cleaningUp
      │
      ▼
notInitialized
```

## Creating New Components

To create a new component that matches the Swift SDK patterns:

### 1. Define Configuration

```typescript
export interface MyComponentConfiguration extends ComponentConfiguration {
  readonly componentType: SDKComponent;
  modelId?: string;
  // ... component-specific config
}

export function createMyComponentConfiguration(
  config: Partial<Omit<MyComponentConfiguration, 'componentType' | 'validate'>>
): MyComponentConfiguration {
  return {
    componentType: SDKComponent.MyComponent,
    ...DEFAULT_MY_COMPONENT_CONFIGURATION,
    ...config,
    validate(): void {
      // Validation logic
    },
  };
}
```

### 2. Define Input/Output Types

```typescript
export interface MyComponentInput extends ComponentInput {
  data: string;
  options?: MyComponentOptions;
  validate(): void;
}

export interface MyComponentOutput extends ComponentOutput {
  result: string;
  metadata: MyComponentMetadata;
  timestamp: Date;
}
```

### 3. Define Service Interface

```typescript
export interface MyComponentService {
  initialize(modelPath?: string): Promise<void>;
  process(input: string, options: MyComponentOptions): Promise<MyComponentResult>;
  isReady: boolean;
  currentModel: string | null;
  cleanup(): Promise<void>;
}
```

### 4. Implement Service Wrapper

```typescript
export class MyComponentServiceWrapper {
  public wrappedService: MyComponentService | null = null;

  constructor(service?: MyComponentService) {
    this.wrappedService = service || null;
  }
}
```

### 5. Implement Native Service

```typescript
class NativeMyComponentService implements MyComponentService {
  private nativeModule: any;
  private _isReady = false;
  private _currentModel: string | null = null;

  constructor() {
    this.nativeModule = NativeModules.RunAnywhere;
  }

  async initialize(modelPath?: string): Promise<void> {
    // Initialize native module
    this._isReady = true;
  }

  async process(input: string, options: MyComponentOptions): Promise<MyComponentResult> {
    if (!this._isReady) {
      throw new SDKError(SDKErrorCode.ServiceNotInitialized, 'Service not initialized');
    }
    // Call native methods
    const result = await this.nativeModule.myComponentProcess(input, JSON.stringify(options));
    return JSON.parse(result);
  }

  get isReady(): boolean {
    return this._isReady;
  }

  get currentModel(): string | null {
    return this._currentModel;
  }

  async cleanup(): Promise<void> {
    // Cleanup
    this._isReady = false;
  }
}
```

### 6. Implement Component Class

```typescript
export class MyComponent extends BaseComponent<MyComponentServiceWrapper> {
  static override componentType = SDKComponent.MyComponent;

  private readonly myConfiguration: MyComponentConfiguration;

  constructor(configuration: MyComponentConfiguration) {
    super(configuration);
    this.myConfiguration = configuration;
  }

  protected async createService(): Promise<MyComponentServiceWrapper> {
    const modelId = this.myConfiguration.modelId || 'unknown';

    this.eventBus.emitModel({
      type: 'loadStarted',
      modelId: modelId,
    });

    try {
      const service = new NativeMyComponentService();
      await service.initialize();

      if (this.myConfiguration.modelId) {
        // Load model if needed
      }

      const wrapper = new MyComponentServiceWrapper(service);

      this.eventBus.emitModel({
        type: 'loadCompleted',
        modelId: modelId,
      });

      return wrapper;
    } catch (error) {
      this.eventBus.emitModel({
        type: 'loadFailed',
        modelId: modelId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  protected async performCleanup(): Promise<void> {
    await this.service?.wrappedService?.cleanup();
  }

  // Public API methods
  async process(input: MyComponentInput): Promise<MyComponentOutput> {
    this.ensureReady();

    const service = this.service?.wrappedService;
    if (!service) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'Service not available');
    }

    input.validate();

    const startTime = Date.now();
    const result = await service.process(input.data, input.options || {});
    const processingTime = Date.now() - startTime;

    return {
      result: result.output,
      metadata: {
        modelId: service.currentModel || 'unknown',
        processingTime,
      },
      timestamp: new Date(),
    };
  }
}
```

### 7. Export Factory Function

```typescript
export function createMyComponent(
  config?: Partial<Omit<MyComponentConfiguration, 'componentType' | 'validate'>>
): MyComponent {
  const configuration = createMyComponentConfiguration(config || {});
  return new MyComponent(configuration);
}
```

## Key Design Patterns

### 1. Service Wrapper Pattern

Components don't directly manage services - they use wrappers:

```typescript
// Service wrapper allows protocol types to work with BaseComponent
export class STTServiceWrapper {
  public wrappedService: STTService | null = null;
}

// Component uses the wrapper
export class STTComponent extends BaseComponent<STTServiceWrapper> {
  private get sttService(): STTService | null {
    return this.service?.wrappedService || null;
  }
}
```

### 2. Configuration Factory Pattern

Configurations use factory functions with defaults:

```typescript
const DEFAULT_STT_CONFIGURATION = {
  language: 'en-US',
  sampleRate: 16000,
  // ...
};

export function createSTTConfiguration(
  config: Partial<STTConfiguration>
): STTConfiguration {
  return {
    componentType: SDKComponent.STT,
    ...DEFAULT_STT_CONFIGURATION,
    ...config,
    validate(): void {
      // Validation logic
    },
  };
}
```

### 3. Input/Output Validation Pattern

All inputs must validate themselves:

```typescript
export interface STTInput extends ComponentInput {
  audioData: string;
  validate(): void;
}

// Usage in component
async process(input: STTInput): Promise<STTOutput> {
  input.validate(); // Validate before processing
  // ...
}
```

### 4. Event Emission Pattern

Components emit events for lifecycle and operations:

```typescript
// Start event
this.eventBus.emitModel({
  type: 'loadStarted',
  modelId: modelId,
});

// Success event
this.eventBus.emitModel({
  type: 'loadCompleted',
  modelId: modelId,
});

// Error event
this.eventBus.emitModel({
  type: 'loadFailed',
  modelId: modelId,
  error: error.message,
});
```

## Best Practices

1. **Always extend BaseComponent** - Don't create standalone component classes
2. **Use strong typing** - Never use `any` or `unknown` for component APIs
3. **Validate configurations** - Implement the `validate()` method
4. **Emit events** - Keep the UI informed of component state
5. **Handle errors gracefully** - Use SDKError with appropriate error codes
6. **Document with JSDoc** - Include @example blocks
7. **Match Swift SDK exactly** - Same method names, same parameters, same return types
8. **Use service wrappers** - Never directly manage service instances in components

## Reference Swift SDK Files

For exact patterns, refer to:

1. **BaseComponent**: `sdk/runanywhere-swift/Sources/RunAnywhere/Core/Components/BaseComponent.swift`
2. **Component Protocol**: `sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Component/Component.swift`
3. **STTComponent**: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift`
4. **TTSComponent**: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift`
5. **LLMComponent**: `sdk/runanywhere-swift/Sources/RunAnywhere/Components/LLM/LLMComponent.swift`

## Testing Components

```typescript
describe('STTComponent', () => {
  let component: STTComponent;

  beforeEach(() => {
    const config = createSTTConfiguration({
      language: 'en-US',
    });
    component = new STTComponent(config);
  });

  afterEach(async () => {
    await component.cleanup();
  });

  it('should initialize successfully', async () => {
    await component.initialize();
    expect(component.isReady).toBe(true);
    expect(component.state).toBe(ComponentState.Ready);
  });

  it('should transcribe audio', async () => {
    await component.initialize();
    const result = await component.transcribe(audioDataBase64);
    expect(result.text).toBeDefined();
    expect(result.confidence).toBeGreaterThan(0);
  });

  it('should emit events during lifecycle', async () => {
    const events: any[] = [];
    const unsubscribe = EventBus.getInstance().subscribeToComponentInitialization((event) => {
      events.push(event);
    });

    await component.initialize();

    expect(events).toContainEqual(
      expect.objectContaining({ type: 'componentInitializing' })
    );
    expect(events).toContainEqual(
      expect.objectContaining({ type: 'componentReady' })
    );

    unsubscribe();
  });
});
```

## Next Steps

Components to implement next:

1. **TTSComponent** - Text-to-Speech
2. **LLMComponent** - Large Language Model inference
3. **VADComponent** - Voice Activity Detection
4. **VoiceAgentComponent** - Full voice pipeline (STT → LLM → TTS)
5. **SpeakerDiarizationComponent** - Multi-speaker identification
6. **WakeWordComponent** - Wake word detection

All should follow the exact patterns established in BaseComponent and STTComponent.
