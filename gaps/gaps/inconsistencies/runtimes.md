# Runtimes (L1 Adapters) — Current Inconsistencies

Updated: 2026-05-05 (RT-CPU-01 + RT-CPU-02 + RT-ONNX-02 + RT-ONNX-03 resolved; pruned — Iteration I scope, CoreML/Metal deferred)
Branch: feat/v2-architecture @ 6217d9e67

## Scope

This document tracks OPEN gaps for the **CPU** and **ONNXRT** runtime adapters
only. The **CoreML** and **Metal** adapters (and their cross-runtime dup
entries) are deferred to Iteration I per user direction and are not listed
here — see git history for the prior audit if reopening that scope.

## Current state summary

Two in-scope L1 runtime adapters: `cpu` (always-on OBJECT library folded into
rac_commons) and `onnxrt` (static library, default-on unless `RAC_BACKEND_ONNX=OFF`
or Emscripten). The top-level `runtimes/CMakeLists.txt:22-28` guards each
subdirectory by `CMakeLists.txt` existence. Both runtimes publish a
`rac_runtime_vtable_t` plus a `rac_runtime_vtable_v2_t` via `reserved_slot_0`,
and both expose an `rac_runtime_entry_<name>()` C entry point (onnxrt also
calls `RAC_STATIC_RUNTIME_REGISTER(onnxrt)` at `rac_runtime_onnxrt.cpp:594`;
CPU is bootstrapped explicitly by the commons registry and intentionally
omits the macro — comment at `runtimes/cpu/rac_runtime_cpu.cpp:617-627`).

Capability-wise, CPU is the complete runtime: it implements `run_session_v2`
with a V2-native fast path (providers that set `run_session_v2` on their
`rac_cpu_runtime_provider_t` see real V2 tensors and can return runtime-owned
outputs; V1-only providers still fall back to the legacy shim), all buffer
ops, and a provider registration surface (`rac_cpu_runtime_register_provider`)
that engines can call to plug in primitive-specific implementations.
`RAC_RUNTIME_CAP_OWNED_OUTPUTS` is now advertised only when at least one
registered provider implements the V2 op. ONNXRT has buffer ops + legacy
`run_session` but its V2 `run_session_v2` slot is NULL
(`rac_runtime_onnxrt.cpp:527`). Runtime metadata also drifts from actual
capabilities in multiple places (see per-runtime gaps below).

Shared runtime helpers exist in commons
(`sdk/runanywhere-commons/include/rac/runtime/rac_runtime_helpers.h`) for
`release_tensor` + `copy_buffer` boilerplate, but neither CPU nor ONNXRT is
wired to them yet — the helper file's own doc comment flags CPU + ONNXRT as
the intended consumers (DEC-01 deferred CoreML/Metal).

## Per-runtime gaps

### runtimes/cpu

#### RT-CPU-03: `rac_cpu_runtime_provider_t` API is effectively a parallel vtable

`rac_cpu_runtime_register_provider` / `rac_cpu_runtime_unregister_provider` /
`rac_cpu_runtime_get_provider_session` (`rac_runtime_cpu.cpp:564-615`) define
a separate plugin surface that only the CPU runtime uses. No other runtime
has an analogous provider registry, and the commons router layer has no
equivalent concept. This is a reasonable workaround for "engines own
primitive-specific tensor marshaling" (see `runtimes/CMakeLists.txt:11-12`)
but it means any cross-runtime provider feature (thermal hints,
memory-pressure callbacks, accelerator profile queries) would need to be
duplicated per runtime — or, better, the provider concept needs promoting
into the shared runtime vtable so onnxrt can benefit from the same escape
hatch.

### runtimes/onnxrt

#### RT-ONNX-01: V2 `run_session_v2` slot is NULL

`runtimes/onnxrt/rac_runtime_onnxrt.cpp:527` leaves `run_session_v2 = nullptr`
even though buffer V2 ops (`alloc_buffer`, `buffer_info`, `map_buffer`,
`unmap_buffer`, `copy_buffer`, `release_tensor`) are all filled in at
`rac_runtime_onnxrt.cpp:528-533`. Any caller that picked this runtime via the
V2 entry point will get a NULL-deref if the commons router calls
`run_session_v2` — the router has to fall back to the V1 `run_session` slot,
which means no V2-only feature (tensor-backed buffers, capacity-aware outputs)
is reachable through onnxrt.

#### RT-ONNX-04: Advertises CPU-only `RAC_DEVICE_CLASS_CPU` while ORT supports EPs

`rac_runtime_onnxrt.cpp:82` pins `k_supported_devices = {CPU}` and
`onnxrt_device_info` returns `device_id = "onnxrt-cpu"`
(`rac_runtime_onnxrt.cpp:501`). ORT's execution-provider model (CoreML EP,
CUDA EP, DirectML EP, NNAPI EP, QNN EP…) is entirely hidden — there is no
way for the router to pick onnxrt for an NPU-class or GPU-class model even
though on Android / macOS / Windows the underlying ORT build could run it
that way. Also, `SessionOptions` at `rac_runtime_onnxrt.h:35-39` has no knobs
for selecting an EP — `Session::create` hard-codes CPU-only behavior by never
calling `SessionOptionsAppendExecutionProvider_*`.

#### RT-ONNX-06: No provider-registration surface

Unlike CPU, onnxrt has no `rac_onnxrt_runtime_register_provider` equivalent.
Every engine that wants to use onnxrt has to call into the runtime's public
`Session::create` / `Session::run` via the `runtime_vtable()` accessor at
`rac_runtime_onnxrt.h:67` or by re-discovering the singleton through
`rac_runtime_get_by_id(RAC_RUNTIME_ONNXRT)`. This asymmetry means engines can
plug into CPU primitive-by-primitive but have to treat onnxrt monolithically.

#### RT-ONNX-07: `SharedOrt::mutex` serializes session creation globally

`SharedOrt` (`rac_runtime_onnxrt.cpp:21-54`) guards `CreateSession` with a
global mutex at `rac_runtime_onnxrt.cpp:150-158`. This is fine for correctness
but means concurrent model loads — e.g. Whisper + embedding warm-up at the
same time during engine bring-up — serialize across the whole process, even
for independent models. Comparable runtimes load in parallel.

## Cross-runtime duplication (CPU + ONNXRT scope)

Shared helpers already live in
`sdk/runanywhere-commons/include/rac/runtime/rac_runtime_helpers.h`.
DUP-RT-01 (release_tensor), DUP-RT-02 (copy_buffer), and DUP-RT-03
(onnxrt_alloc_buffer shim) have been migrated; no remaining duplication in
this scope.

## Cross-SDK alignment expectations

Runtime selection must be commons-driven. The router takes an engine's
declared runtime preference plus the session's format + primitive + device
class and picks a runtime via `rac_runtime_registry`'s priority ordering.

**No SDK should ever hardcode a runtime ID.** There is no Swift/Kotlin/Dart/TS
code that should need `RAC_RUNTIME_CPU` or `RAC_RUNTIME_ONNXRT` as a string
or enum value — engines declare the runtime they were built against, and
commons picks among registered runtimes.

Today's ONNXRT manifest is inconsistent enough (RT-ONNX-04, RT-ONNX-05) that
any SDK that *did* try to infer a runtime from capabilities would get
ambiguous answers. This must be cleaned up in commons before we can enforce
"no SDK-side runtime pinning" as a rule. Concretely: the primitive / format /
device-class triples published by each runtime's `capabilities()` callback
must match the static metadata in the vtable, and the `run_session` +
`run_session_v2` NULL-slot status must be reflected in the manifest so the
router can rule out a runtime before it tries to create a session that will
fail.
