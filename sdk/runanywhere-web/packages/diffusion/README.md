# @runanywhere/web-diffusion

This is the Web diffusion API and registration scaffold. It does not include a
diffusion WASM or WebGPU engine yet, because RACommons currently provides
diffusion only through the Apple/CoreML implementation.

`Diffusion.register()` is safe to call and installs an honest unavailable-state
provider for `RunAnywhere.diffusion.availability()`. It does not register a
`diffusion` WASM capability or claim that image generation works.

The package is intentionally excluded from `package-sdk.sh` until a real,
validated WASM artifact is available. Once the engine lands, its loader must
call `registerWasmModule(['diffusion'], module, ...)` only after that module
has loaded successfully.
