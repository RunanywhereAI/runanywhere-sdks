# Hybrid Routing System

The hybrid routing system decides which AI backend handles each request at runtime. Local backends are preferred by default. When local inference confidence is low, the system automatically cascades to a cloud backend. Adding a new provider requires implementing one interface and one registration call.

## How it works

When `transcribeWithOptions(audio, options)` is called:

1. The router gathers all registered backends for the requested capability (STT, LLM, TTS).
2. Backends whose conditions fail are excluded (e.g., cloud backend excluded when offline, local excluded when model not loaded).
3. The routing policy is applied. `LOCAL_ONLY` keeps only local backends, `CLOUD_ONLY` keeps only cloud.
4. Remaining candidates are scored and sorted. Highest score wins.
5. The primary backend (local) transcribes the audio.
6. A confidence score is checked. If below the threshold (0.5), the same audio is sent to the next candidate (cloud). This is the confidence cascade.
7. After cloud fallback, the local model is restored so the next request routes locally again.

The confidence score is currently a mock (`Random.nextFloat()`). Replace it with real inference confidence when available from the C++ layer.

## Confidence cascade

This is per-request routing, not per-chunk. The full audio is transcribed locally first. If confidence is low, the full audio is re-sent to cloud.

```
Record full audio
    |
Whisper transcribes (local) -> result + confidence
    |
confidence >= 0.5?
    YES -> return local result
    NO  -> load Sarvam -> send same audio to cloud -> return cloud result
           restore Whisper model for next request
```

The cascade only triggers when:
- The primary backend is local (`isLocalOnly`)
- Confidence is below threshold (currently 0.5)
- There is a next candidate in the sorted list (cloud backend)

If the cloud fallback also fails, the local result is returned despite low confidence.

## Routing result metadata

`STTOutput` includes routing fields the UI can display:

- `routingBackendId` — which backend produced the result (e.g., "whisper-local", "sarvam-cloud")
- `routingBackendName` — human-readable name (e.g., "Whisper (Local)", "Sarvam AI (Cloud)")
- `wasFallback` — true if the result came from cloud after a low-confidence local result
- `primaryConfidence` — the local confidence score that triggered the fallback (null if no fallback)
- `confidence` — the confidence score of the final result

## Routing conditions

Each backend declares its own conditions. The router never injects conditions from outside.

Available conditions:

- `LocalOnly` — marks the backend as local. Adds +50 score bonus.
- `NetworkRequired` — excluded when offline.
- `ModelAvailability(modelId, isModelLoaded)` — excluded when the specific model is not loaded. The check is a lambda evaluated at routing time. WhisperSTTBackend checks that the loaded model ID contains "whisper" or "sherpa". SarvamSTTBackend loads its model on demand.
- `Custom(description, check)` — arbitrary check. Used for "API key configured?" on Sarvam.
- `QualityTier(HIGH | STANDARD | LOW)` — affects ranking under `PREFER_ACCURACY` policy.
- `CostModel(costPerMinuteCents)` — free backends get +20 bonus.

## Routing policies

Set via `STTOptions.routingPolicy`:

- `AUTO` — local wins by default (score 270 vs 80). Cloud is fallback via confidence cascade.
- `PREFER_LOCAL` — local gets additional +50 bonus, cloud gets -30 penalty.
- `PREFER_ACCURACY` — `QualityTier(HIGH)` gets +50 bonus.
- `LOCAL_ONLY` — cloud excluded entirely. No cascade.
- `CLOUD_ONLY` — local excluded entirely.
- `FRAMEWORK_PREFERRED` — `preferredFramework` match gets +200 bonus.

## Default scoring

| Backend         | Base | LocalOnly | CostFree | Total |
|----------------|------|-----------|----------|-------|
| Whisper (local) | 200  | +50       | +20      | 270   |
| Sarvam (cloud)  | 80   | --        | --       | 80    |

## API key setup (Sarvam)

The Sarvam API key is set in the example app at:

```
examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelList.kt
```

```kotlin
Sarvam.register(apiKey = "YOUR_SARVAM_API_KEY")
```

If no API key is set, the `Custom("Sarvam API key configured")` condition fails and Sarvam is excluded from candidates. The app works with local-only STT.

For production, move the key to `secrets.properties`, `local.properties` / BuildConfig, or remote config.

## Language mapping (Sarvam)

Sarvam requires Indian locale codes (e.g., `en-IN`, `hi-IN`). The `SarvamSTTBackend` maps bare language codes automatically:

- `en` -> `en-IN`
- `hi` -> `hi-IN`
- `auto` -> `unknown`
- Codes already containing `-IN` are passed through

## Adding a new backend

Create one file implementing `STTBackend`:

```kotlin
class GoogleSTTBackend : STTBackend {

    override fun descriptors() = listOf(
        BackendDescriptor(
            moduleId = "google-stt",
            moduleName = "Google Cloud STT",
            capability = SDKComponent.STT,
            inferenceFramework = InferenceFramework.GOOGLE,
            basePriority = 80,
            conditions = listOf(
                RoutingCondition.NetworkRequired,
                RoutingCondition.QualityTier(BackendQuality.HIGH),
                RoutingCondition.CostModel(costPerMinuteCents = 1.5f),
                RoutingCondition.Custom("API key set", check = { GoogleBridge.hasApiKey() }),
            ),
        )
    )

    override suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTOutput {
        // call your HTTP API here
    }
}
```

Register it in `HybridRouterRegistry.initialize()`:

```kotlin
val backends: List<STTBackend> = listOf(
    WhisperSTTBackend(),
    SarvamSTTBackend(),
    GoogleSTTBackend(),  // add this line
)
```

Nothing else changes.

## Adding LLM or TTS support

Same pattern. Create an `LLMBackend` interface alongside `STTBackend`:

```kotlin
interface LLMBackend : RoutableBackend {
    suspend fun generate(prompt: String, options: LLMOptions): LLMOutput
}
```

The `HybridRouter` class requires no changes -- it is capability-agnostic.

## File locations

```
sdk/runanywhere-kotlin/src/
  commonMain/.../routing/
    RoutingCondition.kt       conditions a backend can declare
    RoutingContext.kt         runtime snapshot passed to the router
    RoutingPolicy.kt          user-level preference enum
    BackendDescriptor.kt      backend self-declaration type
    RoutableBackend.kt        interface all routable backends implement
    STTBackend.kt             interface for STT-capable backends
    HybridRouter.kt           the decision engine
    RoutingResult.kt          routing metadata type

  commonMain/.../STT/STTTypes.kt
    STTOutput                 includes routingBackendId, wasFallback, primaryConfidence

  jvmAndroidMain/.../routing/
    HybridRouterRegistry.kt   singleton, initializes router, maps moduleId to backend
    NetworkAvailability.kt    cross-platform network check (reflection for Android)

  jvmAndroidMain/.../backends/stt/
    WhisperSTTBackend.kt      local Whisper backend (ModelAvailability checks loaded model ID)
    SarvamSTTBackend.kt       Sarvam cloud backend (on-demand model loading, language mapping)

  jvmAndroidMain/.../public/extensions/
    RunAnywhere+STT.jvmAndroid.kt   confidence cascade logic, model restoration after fallback

Tests:
  commonTest/.../routing/HybridRouterTest.kt           9 unit tests, no device needed
  androidInstrumentedTest/.../routing/STTRoutingInstrumentedTest.kt  5 device tests

Example app:
  examples/android/RunAnywhereAI/.../data/ModelList.kt          Sarvam.register(apiKey)
  examples/android/RunAnywhereAI/.../stt/SpeechToTextViewModel.kt   uses transcribeWithOptions, shows routing info
  examples/android/RunAnywhereAI/.../stt/SpeechToTextScreen.kt      RoutingInfoRow composable
```

## What is mocked

The confidence score used for cascade decisions is currently `Random.nextFloat()`. To replace with real confidence:

1. The C++ Whisper backend already returns a confidence value in `TranscriptionResult.confidence`
2. In `RunAnywhere+STT.jvmAndroid.kt`, replace `val mockConfidence = kotlin.random.Random.nextFloat()` with the actual `result.confidence` from the backend
3. Remove the `confidence = mockConfidence` override in the `copy()` call
