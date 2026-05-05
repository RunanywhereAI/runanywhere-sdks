# Runtimes (L1 Adapters) — Current Inconsistencies

Updated: 2026-05-05 (RT-CPU-01 + RT-CPU-02 + RT-CPU-03 + RT-ONNX-01 + RT-ONNX-02 + RT-ONNX-03 + RT-ONNX-04 + RT-ONNX-06 + RT-ONNX-07 resolved; pruned — Iteration I scope, CoreML/Metal deferred)
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
registered provider implements the V2 op. ONNXRT has buffer ops, legacy
`run_session`, and (RT-ONNX-01 resolved) a V2-native `run_session_v2` that
honors caller capacity, returns runtime-owned tensor data/shape when no
caller storage is supplied, and returns `RAC_ERROR_OUTPUT_TRUNCATED` with
required byte counts published on truncation. Runtime metadata also drifts
from actual capabilities in multiple places (see per-runtime gaps below).

Shared runtime helpers exist in commons
(`sdk/runanywhere-commons/include/rac/runtime/rac_runtime_helpers.h`) for
`release_tensor` + `copy_buffer` boilerplate, but neither CPU nor ONNXRT is
wired to them yet — the helper file's own doc comment flags CPU + ONNXRT as
the intended consumers (DEC-01 deferred CoreML/Metal).

## Per-runtime gaps

### runtimes/onnxrt

#### RT-ONNX-04-EP-CUDA: CUDA execution provider linkage not wired

`rac_onnxrt_runtime_enable_execution_provider(RAC_ONNXRT_EP_CUDA)` currently
returns `RAC_ERROR_CAPABILITY_UNSUPPORTED` because the vendored ORT build is
compiled without `RAC_ONNXRT_EP_CUDA_ENABLED`. Follow-up: decide link-time
feature flag, declare the CUDA EP append path inside `apply_active_ep`, and
add a CI matrix entry that exercises `onnxrt-cuda` device id reporting.

#### RT-ONNX-04-EP-DIRECTML: DirectML execution provider linkage not wired

As above, for Windows DirectML. Needs `RAC_ONNXRT_EP_DIRECTML_ENABLED` guard
and a `dml_provider_factory.h`-powered `apply_active_ep` branch.

#### RT-ONNX-04-EP-NNAPI: NNAPI execution provider linkage not wired

Android NNAPI path. Needs `nnapi_provider_factory.h` wiring inside
`apply_active_ep`, plus `RAC_ONNXRT_EP_NNAPI_ENABLED` guarded on `ANDROID`.

#### RT-ONNX-04-EP-QNN: QNN execution provider linkage not wired

Qualcomm HTP / DSP / HMX path. Blocked on QNN SDK redistribution policy —
decide between vendoring the libs and documenting a consumer-provided path.

#### RT-ONNX-04-EP-WEBGPU: WebGPU execution provider linkage not wired

Emscripten WebGPU EP. Needs `webgpu_provider_factory.h` wiring inside
`apply_active_ep` when building with `-sUSE_WEBGPU=1`.

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

Today's ONNXRT manifest is inconsistent enough (RT-ONNX-05 open; RT-ONNX-04
resolved with CoreML EP fully wired and CUDA/DirectML/NNAPI/QNN/WebGPU
activation accepted but routed to CPU until linkage lands) that
any SDK that *did* try to infer a runtime from capabilities would get
ambiguous answers. This must be cleaned up in commons before we can enforce
"no SDK-side runtime pinning" as a rule. Concretely: the primitive / format /
device-class triples published by each runtime's `capabilities()` callback
must match the static metadata in the vtable, and the `run_session` +
`run_session_v2` NULL-slot status must be reflected in the manifest so the
router can rule out a runtime before it tries to create a session that will
fail.
