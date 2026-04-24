# MetalRT Engine (Stub)

This is a **stub engine**. The real MetalRT backend ships as a
closed-source binary via the `RABackendMetalRTBinary` xcframework.
See [`Package.swift`](../../Package.swift) for the binary drop details
(look for `RABackendMetalRTBinary`, `metalrtRemoteBinaryAvailable`,
and the `metalRTTargets()` / `metalRTProducts()` helpers).

## What this directory contains

The C++ sources here (`rac_llm_metalrt.*`, `rac_stt_metalrt.*`,
`rac_tts_metalrt.*`, `rac_vlm_metalrt.*`, `rac_backend_metalrt_register.cpp`,
`rac_plugin_entry_metalrt.cpp`) are thin adapters that translate the
commons service/plugin vtables into calls on the MetalRT engine
implementation provided by the closed-source binary.

When the binary is **not** linked (the default open-source build), the
engine is compiled with `RAC_METALRT_ENGINE_AVAILABLE=0` and every
primitive `create` adapter short-circuits with
`RAC_ERROR_BACKEND_UNAVAILABLE`. A single `RAC_LOG_WARNING` is emitted
at registration time so operators understand why
`loadModel(..., framework: .metalrt)` will surface
`BACKEND_NOT_FOUND` / `BACKEND_UNAVAILABLE` at runtime.

The `stubs/` subdirectory contains no-op C symbol definitions used
only to satisfy the linker when `RAC_METALRT_ENGINE_AVAILABLE=0`.

## Enabling the real MetalRT engine

1. Obtain `RABackendMetalRT.xcframework` (local path) or point
   `Package.swift` at a published release artifact.
2. Flip `useLocalNatives = true` (for local checked-out xcframework) or
   set `metalrtRemoteBinaryAvailable = true` and wire in a real
   checksum for the published `RABackendMetalRT-v<sdkVersion>.zip`.
3. Rebuild with `RAC_METALRT_ENGINE_AVAILABLE=1` so the adapters link
   against the binary-provided engine symbols.

Until then, treat this engine as intentionally unavailable: open-source
consumers should prefer `llamacpp`, `whispercpp`, `onnxruntime`, or
other first-class engines.
