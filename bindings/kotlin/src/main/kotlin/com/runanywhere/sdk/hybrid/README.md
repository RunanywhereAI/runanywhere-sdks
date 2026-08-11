# Hybrid STT Router

Per-request routing between an **on-device** (offline) speech-to-text backend
and a **cloud** (online) backend. The router applies eligibility filters, ranks
the surviving candidates, invokes the primary, and falls back to the secondary
on failure or low transcript confidence.

The API mirrors the Swift SDK's `Hybrid/` surface 1:1 (`HybridSTTRouter`,
`HybridModel`, `HybridRoutingPolicy`, `HybridDeviceState`, `Cloud`). Only the
**STT** capability is wired: offline **sherpa-onnx** ↔ the generic **cloud**
engine. Its HTTP provider is chosen per registered model — either a built-in
adapter (e.g. **Sarvam**) or a developer-defined host-side callback for any
other vendor (see [Custom cloud providers](#custom-cloud-providers)).

---

## Prerequisites

Before `HybridSTTRouter().setPair(...)`, three things must be in place:

1. **On-device backend registered.** The sherpa plugin must be loaded into the
   native registry. On Android this happens when the ONNX/sherpa module is
   registered:

   ```kotlin
   ONNX.register()   // loads librac_backend_sherpa.so → registers "sherpa"
   ```

   If you skip this, `setPair(...)` throws with an actionable message naming the
   missing prerequisite.

2. **Offline model downloaded.** The sherpa model id you pass must be registered
   in the model registry and downloaded to disk (e.g.
   `sherpa-onnx-whisper-tiny.en`). The router resolves the on-disk path via
   `rac_get_model`.

3. **Cloud plugin + credentials registered** (if using the online side).
   `Cloud.register()` folds the native `"cloud"` engine plugin into the registry
   (mirrors `ONNX.register()` for sherpa); `Cloud.register(id, ...)` stores the
   credentials + model string the router resolves by id. The `provider`
   (default `"sarvam"`) is carried in the registered entry and forwarded to the
   engine via `config_json["provider"]`:

   ```kotlin
   Cloud.register()   // plugin registration (once per process)
   Cloud.register(
       id = "saaras",
       provider = "sarvam",   // default; selects the cloud HTTP provider
       model = "saaras:v3",
       apiKey = "sk_...",
       languageCode = null,   // null = let the provider auto-detect
   )
   ```

Optionally, register a device-state provider so the `Network` / `Battery`
filters see live values:

```kotlin
HybridDeviceState.setProvider(AndroidDeviceStateProvider(applicationContext))
```

Without a provider the router assumes online + 100% battery.

---

## Quick start

```kotlin
val router = HybridSTTRouter()

router.setPair(
    offline = HybridModel.offlineSherpa("sherpa-onnx-whisper-tiny.en"),
    online = HybridModel.onlineCloud("saaras"),
    policy = HybridRoutingPolicy.rank(HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST),
)

val result = router.transcribe(audioBytes)
println("${result.text}  via=${result.routing.chosen_model_id}  fallback=${result.routing.was_fallback}")

router.close()
```

`HybridSTTRouter` is `Closeable` — prefer `HybridSTTRouter().use { router -> ... }`
or call `close()` explicitly. `close()` releases the native router handle and
both per-side service handles; it is safe to call multiple times.

`setPair` may be called again to replace the previous bindings (services and
custom filters from the prior pairing are torn down first).

---

## Models

| Factory | Kind | Notes |
|---|---|---|
| `HybridModel.offlineSherpa(id)` | offline | Resolved through the model registry by id. Requires the sherpa plugin loaded. |
| `HybridModel.onlineCloud(id, provider)` | online | Resolved through `Cloud.register(id, ...)` (in-memory credential table); `provider` defaults to `Cloud.DEFAULT_PROVIDER`. |

`Cloud` also exposes `lookup(id)`, `isRegistered(id)`, `unregisterModel(id)`,
`clear()` for the credential table, and `unregister()` for the plugin itself.

---

## Custom cloud providers

Built-in providers (e.g. `"sarvam"`) ship as native adapters in the `cloud`
engine. For **any other vendor** — OpenAI, Deepgram, Groq, your own server —
register a host-side callback with `Cloud.registerProvider`. The engine then
delegates the **entire** request (build + HTTP + parse) to your callback, so you
support a new STT API without a native adapter or a recompile.

It's a two-call flow: `registerProvider` defines the behaviour once; `register`
ties one or more model entries (each with its own credentials) to that provider
name.

```kotlin
// 1. Define the behaviour once — you own the whole HTTP call.
Cloud.registerProvider("openai") { req ->                  // req: CloudSttRequest
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
Cloud.register(
    id = "whisper-1", provider = "openai", model = "whisper-1",
    apiKey = "sk-…", baseUrl = "https://api.openai.com",
)

// 3. Use it in the router exactly like any other online backend.
val router = HybridSTTRouter()
router.setPair(
    offline = HybridModel.offlineSherpa("sherpa-onnx-whisper-tiny.en"),
    online = HybridModel.onlineCloud("whisper-1", provider = "openai"),
    policy = HybridRoutingPolicy.rank(HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST),
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

A policy is passed to `setPair`. Compose filters (AND), an optional cascade,
and a rank directly:

```kotlin
val policy = HybridRoutingPolicy(
    hardFilters = listOf(
        HybridFilter.Network,
        HybridFilter.Battery(minPercent = 20),
    ),
    cascade = HybridCascade.Confidence(threshold = 0.5f),
    rank = HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST,
)
```

or use the single-primitive conveniences:

```kotlin
HybridRoutingPolicy.filter(HybridFilter.Network)
HybridRoutingPolicy.cascade(HybridCascade.Confidence(0.5f))
HybridRoutingPolicy.rank(HybridRank.HYBRID_RANK_PREFER_ONLINE_FIRST)
```

### Filters (drop ineligible candidates; AND-composed)

| Filter | Effect |
|---|---|
| `Network` | Drops the **online** candidate when the device is offline. |
| `Battery(minPercent)` | Drops the **online** candidate below the battery threshold. |
| `Quality(tier)` | Reserved — no-op in the current wire schema. |
| `Custom(name, description, check)` | Predicate `(modelId) -> Boolean` registered by `name` with the commons callback table; **commons** invokes it once per candidate during filtering. Return `false` to drop that candidate. |

### Rank (orders the survivors)

- `HYBRID_RANK_PREFER_LOCAL_FIRST` — try offline first (default when unset).
- `HYBRID_RANK_PREFER_ONLINE_FIRST` — try online first.

### Cascade

- `Confidence(threshold)` — fall back to the secondary when the primary's
  transcript confidence is low.

---

## Transcribe & result

```kotlin
fun transcribe(
    audio: ByteArray,                                        // file-encoded (wav/mp3/flac/…) OR raw PCM
    options: HybridTranscribeOptions = HybridTranscribeOptions(),
): HybridTranscribeResult
```

`HybridTranscribeOptions` is the generated proto
(`language` BCP-47 hint, `sample_rate` raw-PCM hint, `audio_format`
0=PCM 1=WAV 2=MP3 3=OPUS 4=AAC 5=FLAC).

`HybridTranscribeResult`:

| Field | Meaning |
|---|---|
| `text` | Transcript from the chosen backend. |
| `detectedLanguage` | BCP-47 code the backend reported (may be empty). |
| `routing` | Proto-typed `HybridRoutedMetadata` routing decision. |

`routing` fields: `chosen_model_id`, `was_fallback` (`true` if the secondary
served the request), `attempt_count` (1 = primary only, 2 = primary then
secondary), `confidence` (`NaN` when no signal), `primary_confidence`
(primary's confidence before a confidence cascade; `NaN` otherwise), and
`primary_error_code` / `primary_error_message` (why the primary failed when
fallback fired on an error).

A non-zero router rc raises an `SDKException` (mirrors Swift).

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
HybridSTTRouter()                  → allocate native router
setPair(offline, online, policy)   → create offline + online services, install policy
transcribe(audio, options)         → filter → rank → invoke → cascade/fallback
cancel()                           → best-effort cancel of an in-flight transcribe
close()                            → release services + router handle
```

One `HybridSTTRouter` owns one offline + one online service. Calling `setPair`
again replaces the previous bindings.
