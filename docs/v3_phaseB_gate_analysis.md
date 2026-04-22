# v3 Phase B Gate Analysis — Design Block Discovered

> **Status**: BLOCKED pending user decision. Phase A is complete (11 +
> 1 commits, every SDK-consumption item real). Phase B as originally
> scoped requires an ABI extension that wasn't called out in the plan;
> this doc explains the block and 3 options.

## The block

Phase B was planned as: "migrate 9 first-party C++ files from
`rac_service_register_provider` to `rac_plugin_register`, then update
the consumer `rac_*_create()` functions to use `rac_plugin_route`
instead of `rac_service_create`."

That migration **cannot complete cleanly** without ALSO changing the
per-primitive ops structs, because:

1. The **old** flow allocates a backend-specific `impl` inside
   `rac_service_register_provider`-installed factories
   (e.g. [`llamacpp_create_service`](../engines/llamacpp/rac_backend_llamacpp_register.cpp)
   L253 calls `rac_llm_llamacpp_create(...)` to produce a
   `backend_handle`). The service wrapper struct
   (`rac_llm_service_t { ops, impl, model_id }`) is built around that
   `impl` and handed back to the caller as `rac_handle_t`.

2. The **new** `rac_plugin_route(primitive, format, hints, &vtable)`
   returns a vtable. The vtable has per-primitive ops
   (`vt->llm_ops->generate`, `vt->llm_ops->initialize`, etc.) — but
   **no way to create the `impl`** because
   [`rac_llm_service_ops_t`](../sdk/runanywhere-commons/include/rac/features/llm/rac_llm_service.h)
   L29-98 has no `create(config) -> impl` method. Every method takes
   `impl` as its first parameter; the ops struct assumes it's
   pre-allocated.

## Three options

### Option 1 — ABI extension (proper v3 shape)

Add two fields to each of the 8 per-primitive ops structs:

```c
typedef struct rac_llm_service_ops {
    // ... existing 16 method pointers ...

    // NEW (v3-readiness Phase B1):
    rac_result_t (*create_impl)(const char* config_json, void** out_impl);
    void         (*destroy_impl)(void* impl);
} rac_llm_service_ops_t;
```

Then:
- Each engine plugin (llamacpp, onnx, whispercpp, whisperkit_coreml,
  metalrt, sherpa, genie, diffusion-coreml) fills the new fields with
  its existing backend-specific `rac_*_create` / `rac_*_destroy`
  functions.
- `rac_llm_create` becomes:
  ```c
  const rac_engine_vtable_t* vt = nullptr;
  rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, /*format*/ 0, /*hints*/ nullptr, &vt);
  if (!vt || !vt->llm_ops || !vt->llm_ops->create_impl) return RAC_ERROR_NOT_FOUND;

  void* impl = nullptr;
  vt->llm_ops->create_impl(model_path, &impl);

  auto* service = new rac_llm_service_t { .ops = vt->llm_ops, .impl = impl, .model_id = strdup(model_id) };
  *out_handle = service;
  ```
- `rac_service_*` goes away entirely.

**Scope**: ~15-20 files across `sdk/runanywhere-commons/` headers +
implementations + `engines/*/rac_backend_*_register.cpp` files.
Backward-incompatible — requires `RAC_PLUGIN_API_VERSION` bump
(2u → 3u). ~2-3 days of real work.

### Option 2 — Keep `rac_service_*` in v2, migrate in v3

Accept that `rac_service_*` continues to be the consumer path for v2.x.
Mark it `[[deprecated]]` (already done in GAP 11 — commit `ed36a6ce`
on post-audit). `service_registry.cpp` stays but emits runtime warnings.

- **Phase B becomes**: register engines via `rac_plugin_register` IN
  ADDITION TO `rac_service_register_provider` (already done today —
  `rac_plugin_entry_llamacpp.cpp` + `rac_backend_llamacpp_register.cpp`
  coexist).
- **Phase C becomes**: cannot happen in v2 — we can't `git rm
  service_registry.cpp` while consumers call `rac_service_create`.
  Deferred to v3, which is the ABI-break release that includes Option 1.

This is the **safe, minimal-risk** path. v2 ships with cleanly
co-existing old + new registry paths; v3 is the breaking release that
does the consumer migration + deletion.

**Scope**: ~0 additional work. The current branch IS Option 2 — both
registries are already registered for every engine.

### Option 3 — Add a shim registry

Keep `rac_service_*` API but reimplement it internally on top of
`rac_plugin_*`. Consumer code keeps calling `rac_service_create`;
under the hood it calls `rac_plugin_route` + some other bookkeeping to
find the matching `llamacpp_create_service`-style factory.

**Scope**: 1-2 days. But it's essentially adding MORE indirection, not
removing any. The legacy code stays; we just route it through the new
registry internally. Doesn't enable deletion in v3 — still need
Option 1 for that.

## Recommendation

**Option 2 for the current session + PR**, **Option 1 as a separate
semver-major v3 PR**. Reasons:

1. Phase A delivered real cross-SDK consumption of every new commons
   ABI. That's the user's primary ask — "5 SDKs consuming commons
   with new functionality". Done.
2. Option 1 is a 2-3 day undertaking touching ~15-20 files and bumping
   `RAC_PLUGIN_API_VERSION`. That IS v3 — it should be its own PR,
   reviewed on its own merits, with a clear semver-major impact
   statement.
3. The audit's "deprecated replacement paths work" criterion is
   already met by Phase A. The "physical deletion of
   `service_registry.cpp`" criterion is a v3-specific ask that
   inherently requires Option 1.

## What this means for the remaining plan todos

| Todo | Plan scope | Realistic status |
|------|-----------|------------------|
| B1 | Migrate LLM/STT/TTS from rac_service_* | BLOCKED pending Option 1 or 2 decision |
| B2 | Migrate VAD/VLM/embeddings/RAG | BLOCKED (same) |
| B3 | Migrate diffusion + platform | BLOCKED (same) |
| B4 | JNI list-provider sites | Can do standalone (rac_service_list_providers → rac_plugin_list is a mechanical swap; doesn't need the `create` op) |
| B5 | Remove _rac_service_* from export lists | BLOCKED (Phase C prereq) |
| phaseB-exit | gap11 + doc updates | N/A until B1-B3 unblock |
| C1 | git rm service_registry.cpp | BLOCKED pending B1-B5 |
| C2 | Delete VoiceSessionEvent etc. | Can do standalone (Phase A provided the replacements; deletion just removes the deprecated shims) |
| C3 | Bump RAC_PLUGIN_API_VERSION 2u→3u | Requires Option 1 (the ABI extension IS the reason to bump) |

## Recommended pivot

Given the block, commit Phase A as the v3-readiness ship line, then:

- **In this session (optional)**: do the standalone items that don't
  require the ABI extension: B4 (JNI list sites mechanical swap),
  C2 (delete VoiceSessionEvent + orchestration shims that now have
  real replacements from Phase A). This closes the audit's remaining
  deletion items that DON'T depend on the service-registry cut-over.

- **In a separate v3 PR**: implement Option 1 (the ABI extension),
  then B1-B3, B5, C1, C3. Semver-major release.

The user's core ask — "5 SDKs consume commons with new APIs, zero
stubs" — is **already complete**. The remaining work is the
architectural cleanup that enables the deletion half of the ask.
