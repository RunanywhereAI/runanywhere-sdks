# Hybrid STT Router

Per-request routing between an **on-device** (offline) speech-to-text backend
and a **cloud** (online) backend. The router applies eligibility filters, ranks
the surviving candidates, invokes the primary, and falls back to the secondary
on failure or low transcript confidence.

Today only the **STT** capability is wired: offline **sherpa-onnx** ↔ the
generic **cloud** engine. Its HTTP provider is chosen per registered model —
either a built-in adapter (e.g. **Sarvam**) or a developer-defined host-side
callback for any other vendor (see [Custom cloud providers](#custom-cloud-providers)).
`router.tts` / `router.vlm` exist for API shape but throw `UnsupportedOperationException`.

---

## Prerequisites

Before `RACRouter.stt.init(...)`, three things must be in place:

1. **On-device backend registered.** The sherpa plugin must be loaded into the
   native registry. On Android this happens when the ONNX/sherpa module is
   registered:

   ```kotlin
   ONNX.register()   // loads librac_backend_sherpa.so → registers "sherpa"
   ```

   If you skip this, `addPair(...)` throws with an actionable message naming the
   missing prerequisite.

2. **Offline model downloaded.** The sherpa model id you pass must be registered
   in the model registry and downloaded to disk (e.g.
   `sherpa-onnx-whisper-tiny.en`). The router resolves the on-disk path via
   `rac_get_model`.

3. **Cloud credentials registered** (if using the online side). This also
   registers the native `"cloud"` engine plugin with the registry (mirrors
   `ONNX.register()` for sherpa), so the router can route the online side to it.
   The `provider` (default `"sarvam"`) is carried in the registered entry and
   forwarded to the engine via `config_json["provider"]`:

   ```kotlin
   BACKEND.CLOUD.register(
       id = "saaras",
       model = "saaras:v3",
       apiKey = "sk_...",
       provider = "sarvam",   // default; selects the cloud HTTP provider
       languageCode = null,   // null = let the provider auto-detect
   )
   ```

   `BACKEND.SARVAM.register(...)` remains as a thin alias that pins
   `provider = "sarvam"`.

Optionally, register a device-state provider so the `NETWORK` / `Battery`
filters see live values:

```kotlin
RACRouter.setDeviceStateProvider(AndroidDeviceStateProvider(applicationContext))
```

Without a provider the router assumes online + 100% battery.

---

## Quick start

```kotlin
val router = RACRouter.stt.init(
    backendOffline = BACKEND.SHERPA.STT,
    backendOnline  = BACKEND.CLOUD.STT,
)

router.stt.addPair(
    model1 = RACModel(id = "sherpa-onnx-whisper-tiny.en", modelType = ROUTER.OFFLINE),
    model2 = RACModel(id = "saaras",                       modelType = ROUTER.ONLINE),
    routerPolicy = RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferLocalFirst),
)

val result = router.stt.transcribe(audioBytes)
println("${result.text}  via=${result.routing.chosenModelId}  fallback=${result.routing.wasFallback}")

router.close()
```

`RACRouter` is `Closeable` — prefer `RACRouter.stt.init(...).use { router -> ... }`
or call `close()` explicitly. `close()` releases the native router handle and
both per-side service handles; it is safe to call multiple times.

`addPair` order is irrelevant — the `OFFLINE` model binds to the offline slot,
the `ONLINE` model to the online slot.

---

## Backends

| Accessor | Kind | Notes |
|---|---|---|
| `BACKEND.SHERPA.STT` | offline | Resolved through the model registry by id. Requires the sherpa plugin loaded. |
| `BACKEND.CLOUD.STT` | online | Resolved through `BACKEND.CLOUD.register(...)` (in-memory credential table); each entry carries its `provider`. |

`BACKEND.CLOUD` also exposes `lookup(id)`, `isRegistered(id)`, `unregister(id)`,
`clear()`. `BACKEND.SARVAM` is a backwards-compatible alias that delegates to
`BACKEND.CLOUD` with `provider = "sarvam"`.

---

## Custom cloud providers

Built-in providers (e.g. `"sarvam"`) ship as native adapters in the `cloud`
engine. For **any other vendor** — OpenAI, Deepgram, Groq, your own server —
register a host-side callback with `registerProvider`. The engine then delegates
the **entire** request (build + HTTP + parse) to your callback, so you support a
new STT API without a native adapter or a recompile.

It's a two-call flow: `registerProvider` defines the behaviour once; `register`
ties one or more model entries (each with its own credentials) to that provider
name.

```kotlin
// 1. Define the behaviour once — you own the whole HTTP call.
BACKEND.CLOUD.registerProvider("openai") { req ->          // req: CloudSttRequest
    // Honour req.audioFormat — OpenAI needs a real container, not raw PCM.
    val mime = when (req.audioFormat) {
        CloudAudioFormat.WAV -> "audio/wav"
        CloudAudioFormat.MP3 -> "audio/mpeg"
        CloudAudioFormat.FLAC -> "audio/flac"
        else -> error("OpenAI needs a container format, got ${req.audioFormat}")
    }
    val body = MultipartBody.Builder().setType(MultipartBody.FORM)
        .addFormDataPart("file", "audio", req.audio.toRequestBody(mime.toMediaType()))
        .addFormDataPart("model", req.model)
        .build()
    val httpReq = Request.Builder()
        .url("${req.baseUrl ?: "https://api.openai.com"}/v1/audio/transcriptions")
        .header("Authorization", "Bearer ${req.apiKey}")
        .post(body).build()
    OkHttpClient().newCall(httpReq).execute().use { resp ->
        val text = JSONObject(resp.body!!.string()).optString("text")
        CloudSttResult(text = text)        // optionally languageCode / confidence
    }
}

// 2. Register model entries that use it (same provider string).
BACKEND.CLOUD.register(
    id = "whisper-1", model = "whisper-1", apiKey = "sk-…",
    provider = "openai", baseUrl = "https://api.openai.com",
)

// 3. Use it in the router exactly like any other online backend.
val router = RACRouter.stt.init(backendOffline = BACKEND.SHERPA.STT, backendOnline = BACKEND.CLOUD.STT)
router.stt.addPair(
    RACModel("sherpa-onnx-whisper-tiny.en", ROUTER.OFFLINE),
    RACModel("whisper-1", ROUTER.ONLINE),
    RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferLocalFirst),
)
```

`registerProvider(name, handler)` is a `fun interface` (`CloudSttProvider`), so a
trailing lambda works. `unregisterProvider(name)` removes it (idempotent).

**`CloudSttRequest`** (everything the engine hands your callback):

| Field | Meaning |
|---|---|
| `provider` | The provider name this entry was registered under. |
| `model` | Provider model id from `register(...)`. |
| `apiKey` | API key from `register(...)`. Sensitive — never log. |
| `baseUrl` | Optional base-URL override, if set at registration. |
| `languageCode` | Optional BCP-47 hint, if set. |
| `audio` | `ByteArray` for this utterance. |
| `audioFormat` | `CloudAudioFormat` (PCM/WAV/MP3/OPUS/AAC/FLAC) of `audio`. |
| `configJson` | Full registered config as JSON, for any extra keys beyond the typed fields. |

**`CloudSttResult`**: `CloudSttResult(text, languageCode? = null, confidence: Float = NaN)`.

Notes:
- The callback runs on the engine's request thread (off-main), **may block** on
  network, and **must be thread-safe** — the engine may invoke it concurrently
  for distinct utterances.
- **Throwing is allowed** — it surfaces as a transcribe failure, so the router's
  failure fallback can take over.
- **Built-in providers cannot be shadowed** — a static adapter always wins over a
  host callback registered under the same name.
- Return a real `confidence` (0..1) to participate in a `Confidence(...)` cascade
  on the online side; the default `NaN` means "no signal" and never cascades.

---

## Policies

A policy is passed to `addPair`. Two shapes:

**`SimpleRouterPolicy`** — exactly one primitive:

```kotlin
RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.NETWORK())
RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.PreferOnlineFirst)
RACRouter.SimpleRouterPolicy(RACRouter.RoutingPolicy.Confidence(0.5f))
```

**`AdvanceRouterPolicy`** — compose filters (AND), an optional cascade, a rank:

```kotlin
val policy = RACRouter.AdvanceRouterPolicy {
    hardFilters = arrayOf(
        RACRouter.RoutingPolicy.NETWORK(),
        RACRouter.RoutingPolicy.Battery(minPercent = 20),
    )
    cascadeConditions = RACRouter.RoutingPolicy.Confidence(0.5f)
    rankSort = RACRouter.RoutingPolicy.PreferLocalFirst
}
```

### Filters (drop ineligible candidates; AND-composed)

| Filter | Effect |
|---|---|
| `NETWORK()` | Drops the **online** candidate when the device is offline. |
| `Battery(minPercent)` | Drops the **online** candidate below the battery threshold. |
| `Quality(tier)` | Reserved — no-op in the current wire schema. |
| `CustomDefine(name, description, check)` | Predicate `(modelId) -> Boolean` registered by `name` with the commons callback table; **commons** invokes it once per candidate during filtering. Return `false` to drop that candidate. |

### Rank (orders the survivors)

- `PreferLocalFirst` — try offline first (default when unset).
- `PreferOnlineFirst` — try online first.

### Cascade

- `Confidence(threshold)` — fall back to the secondary when the primary's
  transcript confidence is low.

---

## Transcribe & result

```kotlin
fun transcribe(
    audioBytes: ByteArray,   // file-encoded (wav/mp3/flac/…) OR raw PCM
    language: String = "",   // BCP-47 hint; "" = auto-detect
    sampleRate: Int = 0,     // raw-PCM hint; 0 = engine default (16000)
    audioFormat: Int = 0,    // 0=PCM 1=WAV 2=MP3 3=OPUS 4=AAC 5=FLAC; 0 = unspecified
): TranscribeResult
```

`TranscribeResult`:

| Field | Meaning |
|---|---|
| `text` | Transcript from the chosen backend. |
| `detectedLanguage` | BCP-47 code the backend reported (may be empty). |
| `routing.chosenModelId` | Model id that produced the result. |
| `routing.wasFallback` | `true` if the secondary served the request. |
| `routing.attemptCount` | `1` = primary only, `2` = primary then secondary. |
| `routing.confidence` | Confidence of the returned result. `NaN` when no signal. |
| `routing.primaryConfidence` | Primary's confidence before a confidence cascade. `NaN` otherwise. |
| `routing.primaryErrorCode` / `primaryErrorMessage` | Why the primary failed (when fallback fired on an error). |

---

## Fallback behaviour

The native router evaluates two independent fallbacks per request:

- **Failure fallback** — if the primary errors and an eligible secondary
  exists, the secondary is invoked. **Always active**, independent of policy.
- **Confidence cascade** — **opt-in**: only when the policy includes
  `Confidence(threshold)`. It fires when the primary succeeds with a real
  (non-`NaN`) confidence **below that threshold** and an eligible secondary
  exists; the secondary's result is then returned. With no `Confidence(...)` in
  the policy, the primary result always stands (subject to failure fallback).

Offline confidence flows from the sherpa engine (`exp(mean(ys_log_probs))`, which
requires the confidence-patched sherpa build). Built-in cloud providers (e.g.
Sarvam) return `NaN`, so the online side never triggers a cascade — but a
[custom provider](#custom-cloud-providers) may return its own `confidence` to
opt the online side into the cascade.

---

## Lifecycle summary

```
init(offline, online)        → allocate native router
addPair(m1, m2, policy)      → create offline + online services, install policy
transcribe(audio, …)         → filter → rank → invoke → cascade/fallback
close()                      → release services + router handle
```

One `RACRouter` owns one offline + one online service. Calling `addPair` again
replaces the previous bindings.
