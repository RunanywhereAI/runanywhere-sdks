# Runtimes (L1 Adapters) — Current Inconsistencies

Updated: 2026-05-06
Branch: feat/v2-architecture @ bb63158d6

## Deferred runtime adapters (do not file bugs)

The following L1 runtime adapters are **deferred** and out of scope. Stub /
exclude / delete is acceptable. No bug rows should be filed against them:

- `runtimes/coreml` — deferred runtime adapter.
- `runtimes/metal`  — deferred runtime adapter.

Only two runtime adapters are in scope right now: **`cpu`** (always-on) and
**`onnxrt`**.

## Scope

Open gaps for the `cpu` and `onnxrt` runtime adapters only.

## Per-runtime gaps

### runtimes/onnxrt

All five `RT-ONNX-04-EP-*` rows remain open at HEAD. `rac_runtime_onnxrt.cpp:1195-1203`
gates `rac_onnxrt_runtime_enable_execution_provider` on `ep_is_compiled_in`
(`rac_runtime_onnxrt.cpp:111-142`), which only returns true for `CPU` and
(when `RAC_ONNXRT_EP_COREML_ENABLED`) `COREML`. CUDA/DirectML/NNAPI/QNN/WebGPU
return `RAC_ERROR_CAPABILITY_UNSUPPORTED`. These are real onnxrt execution
providers — not the deferred `coreml` / `metal` L1 runtime adapters.

#### RT-ONNX-04-EP-CUDA: CUDA execution provider linkage not wired

`rac_onnxrt_runtime_enable_execution_provider(RAC_ONNXRT_EP_CUDA)` returns
`RAC_ERROR_CAPABILITY_UNSUPPORTED` because the vendored ORT build is compiled
without `RAC_ONNXRT_EP_CUDA`. Follow-up: decide link-time feature flag,
declare the CUDA EP append path inside `apply_active_ep`, add a CI matrix
entry that exercises `onnxrt-cuda` device id reporting.

#### RT-ONNX-04-EP-DIRECTML: DirectML execution provider linkage not wired

As above, for Windows DirectML. Needs `RAC_ONNXRT_EP_DIRECTML` guard and a
`dml_provider_factory.h`-powered `apply_active_ep` branch.

#### RT-ONNX-04-EP-NNAPI: NNAPI execution provider linkage not wired

Android NNAPI path. Needs `nnapi_provider_factory.h` wiring inside
`apply_active_ep`, plus `RAC_ONNXRT_EP_NNAPI` guarded on `ANDROID`.

#### RT-ONNX-04-EP-QNN: QNN execution provider linkage not wired

Qualcomm HTP / DSP / HMX path. Blocked on QNN SDK redistribution policy —
decide between vendoring the libs and documenting a consumer-provided path.

#### RT-ONNX-04-EP-WEBGPU: WebGPU execution provider linkage not wired

Emscripten WebGPU EP. Needs `webgpu_provider_factory.h` wiring inside
`apply_active_ep` when building with `-sUSE_WEBGPU=1`.
