# Electron SDK — Development

Contributor guide for building and testing `@runanywhere/electron` from source on Windows.

## Prerequisites

- Windows x64 (the package is `private: true`, `os: win32` only)
- MSVC and the RunAnywhere commons + engines built with the `windows-release` preset
- Node.js dev headers (installed via `npm install`)

## Build steps

From `sdk/runanywhere-electron`:

```bash
npm install
npm run build          # TypeScript -> dist/
npm run bundle:native  # copy the built .node + DLLs into prebuilds/
npm test               # unit tests (hermetic, no native addon needed)
```

Integration tests need the addon and downloaded models:

```powershell
$env:RUNANYWHERE_NATIVE_PATH = '<path>/runanywhere_native.node'
npm run test:integration
```

See `native/CMakeLists.txt` and the commons build docs for compiling the native addon against `runanywhere-commons`.

## GPU build (CUDA / NVIDIA)

The default build is CPU-only. To offload inference to an NVIDIA GPU, build commons with `-DRAC_GPU_CUDA=ON` (CUDA toolkit **≥ 12.4** and MSVC). At load time, llama.cpp auto-offloads layers that fit VRAM.

```powershell
# From the repo root. Set CMAKE_CUDA_ARCHITECTURES to your GPU (86 = RTX 30-series).
$env:NVCC_PREPEND_FLAGS = '-allow-unsupported-compiler'   # only if MSVC is newer than the CUDA toolkit officially supports
cmake -S . -B build/windows-cuda -G "Visual Studio 17 2022" -A x64 `
  -T cuda="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.6" `
  -DRAC_GPU_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 `
  -DRAC_BUILD_ELECTRON_ADDON=ON -DRAC_BUILD_BACKENDS=ON -DRAC_STATIC_PLUGINS=ON -DRAC_BUILD_SHARED=OFF
cmake --build build/windows-cuda --config Release --target runanywhere_native --parallel
```

Place the built `runanywhere_native.node` in `prebuilds/win32-x64-cuda/` beside its DLLs: `cudart64_12.dll`, `cublas64_12.dll`, `cublasLt64_12.dll` (from the CUDA `bin/`) plus `onnxruntime.dll`, `onnxruntime_providers_shared.dll`, `sherpa-onnx-c-api.dll`.

Then run `npm run bundle:native` or copy manually. The demo's `examples/electron/RunAnywhereAI/run-demo-gpu.cmd` launches against that prebuild.

## Example demo

From the repo root:

```cmd
examples\electron\RunAnywhereAI\run-demo.cmd
```

Or manually:

```cmd
set RUNANYWHERE_NATIVE_PATH=sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node
npx electron examples/electron/RunAnywhereAI
```

When bundling into an Electron app, unpack native artifacts from the asar:

```jsonc
// electron-builder config
"asarUnpack": ["**/node_modules/@runanywhere/electron/prebuilds/**"]
```
