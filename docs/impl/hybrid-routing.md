# Hybrid Routing

Per-request selection between local and cloud backends. Router lives in C++ (`runanywhere-commons`); Kotlin/Swift just register backends and call `run_<cap>`.

## Core idea

Each capability (STT, LLM, TTS, …) keeps a `Registry<Service>` of long-lived components. On every request the router:

1. **Resolves** candidates: eligibility filter (network, model availability, custom predicates) → policy filter (`LOCAL_ONLY`/`CLOUD_ONLY`/…) → score sort.
2. **Cascades**: invoke top candidate. Stop on high-confidence success. On low-confidence local success, checkpoint the result and try the next candidate; if every later attempt fails, restore the checkpoint (low-confidence answer beats no answer).
3. **Returns** result + metadata (`chosen_module_id`, `was_fallback`, `primary_confidence`, `attempt_count`).

Threshold for "low confidence" is `RAC_ROUTING_CONFIDENCE_THRESHOLD` (0.5). `NaN` confidence means "no signal" — treated as trusted (no cascade).

## Where the code lives

| File | Purpose |
|---|---|
| `sdk/runanywhere-commons/include/rac/routing/rac_router.h` | Public C API |
| `sdk/runanywhere-commons/include/rac/routing/rac_routing_types.h` | Descriptor / condition / policy enums |
| `sdk/runanywhere-commons/src/routing/rac_routing_internal.h` | `Registry`, `Entry`, `resolve`, `cascade` templates |
| `sdk/runanywhere-commons/src/routing/rac_router.cpp` | Per-capability public entry points |
| `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | JNI bridge |
| `sdk/runanywhere-kotlin/.../foundation/bridge/extensions/RouterRegistration.kt` | Kotlin glue: registers loaded components with router |
| `sdk/runanywhere-kotlin/.../foundation/bridge/extensions/CppBridgeRouter.kt` | Kotlin call surface (`runStt`, …) |

## Adding a new capability to the router

Worked example: adding LLM routing. Repeat verbatim for TTS/VAD/etc.

### 1. Add a registry slot

`src/routing/rac_router.cpp`:

```cpp
struct rac_router {
    Registry<rac_stt_service_t> stt;
    Registry<rac_llm_service_t> llm;   // new
};
```

### 2. Add C entry points

Copy the three STT functions (`rac_router_register_stt`, `rac_router_unregister_stt`, `rac_router_stt_count`) and swap the type + registry field. Declare them in `rac_router.h`.

### 3. Write `rac_router_run_<cap>`

The only capability-specific part is the checkpoint callbacks — they know how to move ownership of the result struct. For STT that's `text`, `detected_language`, `words`. For LLM it'd be `generated_text`, `logprobs`, etc.

```cpp
rac_result_t rac_router_run_llm(
    rac_router_t*                router,
    const rac_routing_context_t* context,
    const char*                  prompt,
    const rac_llm_options_t*     options,
    rac_llm_result_t*            out_result,
    rac_routed_metadata_t*       out_meta) {
    // ... arg checks, zero out_meta ...

    rac_llm_result_t checkpoint = {};

    return cascade(
        router->llm, *context, out_meta,
        [&](const Entry<rac_llm_service_t>& e, float* out_conf) -> rac_result_t {
            auto* svc = static_cast<rac_llm_service_t*>(e.impl);
            *out_result = rac_llm_result_t{};
            rac_result_t rc = svc->ops->generate(svc->impl, prompt, options, out_result);
            if (rc == RAC_SUCCESS && out_conf) *out_conf = out_result->confidence;
            return rc;
        },
        /*on_keep*/    [&] { checkpoint = *out_result; *out_result = rac_llm_result_t{}; },
        /*on_restore*/ [&] { *out_result = checkpoint; checkpoint = rac_llm_result_t{}; },
        /*on_drop*/    [&] { rac_llm_result_free(&checkpoint); checkpoint = rac_llm_result_t{}; });
}
```

If the capability has no meaningful confidence signal (TTS: either it synthesizes or it doesn't), pass `NaN` and use the three-arg overload of `cascade` — no checkpoint needed.

### 4. JNI bridge

In `runanywhere_commons_jni.cpp`, mirror the STT JNI methods: `racRouterRegisterLlm`, `racRouterUnregisterLlm`, `racRouterRunLlm`, `racRouterLlmCount`. Marshal the result struct to JSON (or a dedicated return object). Add declarations to `RunAnywhereBridge.kt`.

### 5. Kotlin glue

Extend `RouterRegistration.kt` to track the LLM component handle alongside STT. Add `registerLocalLlm`/`unregisterLocalLlm` and — if you have a cloud LLM provider — `register<Provider>Llm`. Call them from the LLM load/unload path the same way `CppBridgeSTT.loadModel` calls `registerLocal`.

Add `CppBridgeRouter.runLlm(...)` as the single call surface and wire it into the public `RunAnywhere.generate(...)` path in `jvmAndroidMain`.

## Adding a new backend to an existing capability

Much simpler — no router changes, just register with the existing `rac_router_register_<cap>`:

1. Implement the capability's service vtable (`rac_<cap>_service_ops_t`).
2. Register the factory with the service registry (via `rac_backend_<name>_register()`).
3. From Kotlin/Swift, after your component loads, call `RunAnywhereBridge.racRouterRegister<Cap>(...)` with a descriptor:
   - `module_id`, `module_name`, `base_priority`
   - conditions: `RAC_COND_LOCAL_ONLY`, `RAC_COND_NETWORK_REQUIRED`, `RAC_COND_COST_MODEL`, `RAC_COND_MODEL_AVAILABILITY`, `RAC_COND_CUSTOM`
   - `inference_framework` string (used by `FRAMEWORK_PREFERRED` policy)
4. Call `racRouterUnregister<Cap>(module_id)` on unload **before** the native unload — the router holds a non-owning service pointer that would dangle otherwise.

## Routing policies

| Policy | Effect |
|---|---|
| `AUTO` | Default sort by `base_priority` + cascade on low local confidence |
| `LOCAL_ONLY` / `CLOUD_ONLY` | Hard filter by the `LOCAL_ONLY` condition flag |
| `PREFER_LOCAL` | `+100` score to local candidates |
| `PREFER_ACCURACY` | `+50` score to non-local candidates |
| `FRAMEWORK_PREFERRED` | `+200` score to candidates whose `inference_framework` matches `ctx.preferred_framework` |

## Invariants / gotchas

- **Registry holds non-owning pointers.** Backend unload MUST unregister first. `RouterRegistration.unregister<X>()` handles this for the current backends; any new backend must follow the same contract.
- **Checkpoint storage owns heap pointers.** `on_drop` is mandatory when a later candidate succeeds; skipping it leaks the checkpoint.
- **`NaN` is a signal, not an error.** Treated as "no confidence" → no cascade, no NaN comparisons. Serialize as JSON `null` (JNI emits `null` explicitly; Kotlin regex handles both `null` and numbers).
- **Streaming bypasses the router.** A cascade only makes sense on a final score; mid-utterance handoff isn't meaningful. Streaming paths use whichever local component is currently loaded.
- **No Kotlin-side cascade.** All routing decisions live in C++. Kotlin only registers/unregisters and calls `run_<cap>`.

## Confidence from local backends

The cascade only works if local backends emit a real confidence signal. Sources per backend:

- **Whisper (ONNX, via Sherpa)** — uses a forked Sherpa-ONNX at `github.com/runanywhere/sherpa-onnx-runanywhere`. Upstream Sherpa drops the decoder's log-probs; our fork plumbs them through `OfflineWhisperDecoderResult::ys_log_probs` (greedy decoder logs max log-prob per picked token), aligned with filtered text tokens in `offline-recognizer-whisper-impl.h`. Kotlin SDK pulls prebuilts from this fork into `runanywhere-commons/third_party/sherpa-onnx-android/`. If you rebuild Sherpa, refresh both the `.so` files in `jniLibs/` **and** the `c-api.h`/`cxx-api.h` headers — struct layout drifts between versions and a mismatch will silently corrupt results.
- **Sarvam / other cloud** — emit `NaN` (no meaningful per-request score from the API). Cascade treats `NaN` as trusted.
- **A new local backend** — must populate `rac_stt_result_t::confidence` in [0,1]. If your backend has no signal, emit `NaN` and it will be treated as high-confidence (no cascade) rather than low-confidence (always cascade). Picking `0.0` by default is the classic bug — it triggers cascade on every request.

## Testing a new capability

- Unit test in `sdk/runanywhere-commons/tests/test_router.cpp` — add a fake `Service` vtable, register two instances with different priorities/conditions, drive `resolve()` and `cascade()` through every policy and eligibility branch, including the checkpoint restore path.
- On-device: register one local + one cloud backend, trigger a request with weak input (low-confidence local), verify `was_fallback=true` and `chosen_module_id` flipped to cloud. Then trigger with cloud-impossible input (e.g. airplane mode) and verify checkpoint restore — local result still returned.
