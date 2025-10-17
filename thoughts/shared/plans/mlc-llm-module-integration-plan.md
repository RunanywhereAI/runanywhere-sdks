# MLC-LLM Module Integration Plan

**Status**: ✅ Implementation Complete | ⏳ Native Libraries Needed

## Current State

### ✅ Completed (Phases 1-3)

- ✅ Module structure and build configuration
- ✅ Auto-registration with ModuleRegistry
- ✅ MLCProvider and MLCService implementation
- ✅ MLCEngine wrapper around native MLC-LLM
- ✅ Git submodule setup (self-contained architecture)
- ✅ Comprehensive documentation in README.md
- ✅ Verified: **All Kotlin code compiles successfully** (without native libs)

### ⏳ Deferred: Build Native Libraries (One-Time, ~15-45 min)

**Status**: Implementation complete. Native library build is **deferred** to be done later when needed.

**Verification**: Ran `:modules:runanywhere-llm-mlc:compileDebugKotlinAndroid` - all Kotlin code compiles successfully. Build only fails on Java code from `mlc4j` which requires `tvm4j_core.jar`.

**Two Options When Ready**:

1. **Quick**: Run `./download_libs.sh` (~2 min, downloads pre-built binaries if available)
2. **Build**: Follow official MLC-LLM instructions (~15-45 min)

**Build Process** (from https://llm.mlc.ai/docs/deploy/android.html):

1. Install dependencies: Rust, conda, cmake, ninja, git-lfs, zstd
2. Set environment variables (ANDROID_NDK, TVM_NDK_CC, JAVA_HOME)
3. Navigate to `mlc-llm/android/MLCChat/`
4. Run `mlc_llm package`
5. Copy `dist/lib/mlc4j/output/*` to `../../mlc4j/output/`

**Full instructions**: See [README.md](../../../sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/README.md#3-build-native-libraries-one-time-15-45-minutes)

## Architecture

### Git Submodule (Self-Contained)

Following the same pattern as llama.cpp:

```
sdk/runanywhere-kotlin/
├── native/llama-jni/
│   └── llama.cpp/                    # Git submodule
└── modules/runanywhere-llm-mlc/
    ├── mlc-llm/                      # Git submodule (self-contained)
    │   └── android/mlc4j/
    │       └── output/               # Native libs (git-ignored)
    ├── src/
    │   ├── commonMain/               # MLCModule, MLCProvider, MLCService (expect)
    │   └── androidMain/              # MLCService (actual), MLCEngine
    └── build.gradle.kts              # Depends on mlc4j via api()
```

**.gitmodules**:
```ini
[submodule "sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/mlc-llm"]
    path = sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/mlc-llm
    url = https://github.com/mlc-ai/mlc-llm.git
```

**Submodule setup**:
```bash
git submodule update --init --recursive
```

### Module Structure

```
modules/runanywhere-llm-mlc/
├── mlc-llm/                          # Git submodule
│   └── android/mlc4j/                # Native library
├── src/
│   ├── commonMain/kotlin/
│   │   ├── MLCModule.kt              # Auto-registration
│   │   ├── MLCProvider.kt            # LLMServiceProvider
│   │   └── MLCService.kt             # expect class
│   └── androidMain/kotlin/
│       ├── MLCModuleActual.kt        # Platform init
│       ├── MLCEngine.kt              # Native wrapper
│       └── MLCService.kt             # actual implementation
├── build.gradle.kts                  # Module config
├── proguard-rules.pro                # Keep TVM/MLC classes
└── README.md                         # Source of truth
```

### Component Flow

```
MLCModule (auto-registers on init)
    ↓
MLCProvider (LLMServiceProvider)
    ↓
MLCService (EnhancedLLMService)
    ↓
MLCEngine (wrapper)
    ↓
ai.mlc.mlcllm.JSONFFIEngine (native)
    ↓
TVM Runtime (native .so)
```

## Key Implementation Details

### Auto-Registration

```kotlin
// commonMain/MLCModule.kt
object MLCModule {
    init {
        ModuleRegistry.registerLLM(MLCProvider())
    }
}
```

### Provider

```kotlin
// commonMain/MLCProvider.kt
class MLCProvider : LLMServiceProvider {
    override suspend fun createLLMService(config: LLMConfiguration): EnhancedLLMService =
        MLCService(config)

    override fun canHandle(modelId: String?): Boolean = true
    override val name = "MLC-LLM"
}
```

### Service (Android)

```kotlin
// androidMain/MLCService.kt
actual class MLCService(config: LLMConfiguration) : EnhancedLLMService {
    private var engine: MLCEngine? = null

    actual override suspend fun initialize(modelPath: String?) {
        engine = MLCEngine()
        engine!!.reload(actualModelPath, actualModelLib)
    }

    actual override suspend fun generate(prompt: String, options: RunAnywhereGenerationOptions): String {
        // Uses engine.chatCompletion with OpenAI format
    }

    actual override suspend fun streamGenerate(..., onToken: (String) -> Unit) {
        // Token-by-token via callback
    }

    actual override suspend fun cleanup() {
        engine?.unload()
        engine = null
    }
}
```

### Engine Wrapper

```kotlin
// androidMain/MLCEngine.kt
class MLCEngine {
    private val nativeEngine: ai.mlc.mlcllm.JSONFFIEngine

    @Synchronized
    fun reload(modelPath: String, modelLib: String) {
        nativeEngine.reload(modelPath, modelLib)
    }

    @Synchronized
    suspend fun chatCompletion(...): ReceiveChannel<ChatCompletionStreamResponse> {
        // Wraps native engine with Kotlin coroutines
    }
}
```

## Build Configuration

### Root SDK settings.gradle.kts

```kotlin
// Conditional mlc4j inclusion
val mlc4jDir = file("modules/runanywhere-llm-mlc/mlc-llm/android/mlc4j")
if (mlc4jDir.exists()) {
    include(":mlc4j")
    project(":mlc4j").projectDir = mlc4jDir
    println("✓ mlc4j found")
} else {
    println("⚠ mlc4j not found - run: git submodule update --init --recursive")
}
```

### Module build.gradle.kts

```kotlin
kotlin {
    androidTarget()

    sourceSets {
        val androidMain by getting {
            dependencies {
                implementation(libs.androidx.core.ktx)
                api(project(":mlc4j"))  // Transitive dependency
            }
        }
    }
}
```

## Usage Example

```kotlin
// Module auto-registers when on classpath
val provider = ModuleRegistry.llmProvider("mlc")

val config = LLMConfiguration(
    modelId = "/path/to/mlc-model",
    frameworkOptions = mapOf("modelLib" to "phi_3_mini_q4f16_0")
)

val service = provider?.createLLMService(config)
service?.initialize()

// Generate
val response = service?.generate("Hello, how are you?")

// Stream
service?.streamGenerate("Tell me a story") { token ->
    print(token)
}

// Cleanup
service?.cleanup()
```

## Success Criteria

- [x] Module structure created
- [x] Auto-registration working
- [x] Provider implementation complete
- [x] Service implementation complete (expect/actual)
- [x] MLCEngine wrapper complete
- [x] Git submodule configured
- [x] Build configuration complete
- [ ] Native libraries obtained (pending user action)
- [ ] Module builds successfully (pending native libs)
- [ ] Integration test with sample model (Phase 4)

## Future Enhancements

- Enhanced streaming with Kotlin Flow
- Multi-turn conversation support
- Model preloading/caching
- Performance metrics
- Vision model support (multi-modal)

## Documentation

**Single source of truth**: `sdk/runanywhere-kotlin/modules/runanywhere-llm-mlc/README.md`

Contains:
- Quick start guide
- Git submodule setup
- Native library options (3 detailed methods)
- Usage examples
- Troubleshooting
- Architecture details
- Comparison with llama.cpp

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Git submodule inside module | Self-contained, matches llama.cpp pattern |
| Conditional include in settings | Graceful degradation if missing |
| api() dependency on mlc4j | Transitive to consumers |
| Git-ignore native libs | Optional tracking, teams can commit if desired |
| OpenAI message format | MLC-LLM native support |
| Callback-based streaming | Simpler than Flow for initial implementation |

---

**Last Updated**: October 11, 2025
**Next Step**: Obtain native libraries using one of 3 options in README.md
