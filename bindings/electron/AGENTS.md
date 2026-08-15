# AGENTS.md

This package is the Electron/Node binding for RunAnywhere. `CLAUDE.md` is a symlink to
this file.

## Ownership

- **C++ commons owns AI truth** (inference, lifecycle, registry, RAG, cancel, error
  categories). The TypeScript facade and N-API addon are thin bridges.
- Align `native/addon.cpp` with the Python `module.cpp` when the surfaces intentionally
  mirror each other (handle maps, leases, secure store, streaming).
- Swift remains the cross-SDK product-semantics reference when behavior is ambiguous.

## TypeScript is the only authoring language

**Everything in this package is written in TypeScript — strictly typed, no exceptions.**
There is no JavaScript in authored source: not the build scripts, not the tests, not the native
smoke tests. The conventions match the Web SDK so an engineer moves between the
Web SDK, this SDK, and the consumer apps without changing habits.

### Non-negotiable rules

- **`strict: true`**, and never weakened per-file.
- **No `any`.** `@typescript-eslint/no-explicit-any` is an error. When a value genuinely is not
  known, use `unknown` and narrow it. The native N-API boundary is the one place raw shapes
  arrive — narrow them once, at the boundary, into a declared interface (`NativeAddon` in
  `src/bridge.ts` is the pattern), and never let an untyped value travel inward.
- **No `@ts-ignore` / `@ts-expect-error`** to silence a real type error. If a dependency's types
  are wrong, declare the correct shape locally and convert at that seam.
- **No non-null `!` to paper over a maybe.** Narrow, or throw a typed `SDKException`.
- **No raw JSON assumptions.** Anything crossing a process, socket, or file boundary is validated
  or decoded into a declared type before use.
- **`consistent-type-imports`** — `import type { … }` for type-only imports, so emitted CJS has no
  phantom requires.
- **`no-floating-promises` / `no-misused-promises`** — every promise is awaited, returned, or
  explicitly `void`ed with a comment saying why.
- **Unused vars are errors**, `^_` prefix to opt out.
- **Proto types are the source of truth.** Import generated types from `@runanywhere/proto-ts`;
  never hand-write an enum, union, or message shape that the IDL already defines. See "Typed
  contracts" below.
- **Discriminated unions over booleans-plus-optionals** for state. A stream event is
  `{ type: 'token'; … } | { type: 'completed'; … }`, never `{ token?, done? }`.
- **`readonly` on anything the caller must not mutate**; `as const` for literal tables.
- **Exhaustive `switch`** over proto enums and union discriminants, with a `never` fallthrough so
  adding a case is a compile error rather than a silent gap.

### Emit targets

Source language is uniform; **output format is not**, and that distinction matters here:

| Consumer | Output | Why |
|---|---|---|
| `dist/` (the package) | CommonJS | `"type": "commonjs"`, `module: node16`. Electron main and preload load as CJS. |
| Electron preload | CommonJS | Preload with `sandbox: false` is CJS-loaded. |
| Utility host catalog | CommonJS `.js` **on disk** | `host.ts` does a raw `require(RUNANYWHERE_CATALOG_PATH)`. |
| A renderer bundle | ESM | Bundler's job, not this package's. |

Tests and scripts compile to their own out-dirs (`dist-test/`, `dist-scripts/`) via dedicated
tsconfigs. `tsconfig.test.json` **must** set `rootDir: "test"` so `dist-test/unit/x.test.js`
resolves `../../dist` correctly — `rootDir: "."` silently breaks every test import.

### Verification gates

```bash
npm run build      # tsc -> dist/
npm run typecheck  # tsc --noEmit over all four projects (src, test, scripts, native smoke)
npm test           # node --test over dist-test/unit
```

All three must pass before handoff. `pr-build.yml` `electron-unit` runs them on Linux;
`electron-sdk-ci.yml` re-runs the TypeScript gates on Windows and adds the thin native
matrix (`electron-windows` / `electron-macos`). A green `build` with a red `typecheck`
means a test file is lying about a type.

**There is no `npm run lint` in this package yet** — no eslint config, no eslint dependency, no CI
step. The rules above are still the standard, but today they are enforced by `strict` + `noEmit`
type-checking and by review, not by a linter. The `eslint-disable-next-line` comments in the source
are forward-looking; do not read them as evidence of a gate. Wiring eslint up is a real task, not a
line in this file.

## Best practices (Electron)

Adapted from `thoughts/shared/plans/BEST_PRACTISES.md` for this package:

### Typed contracts

- Prefer typed `SDKException` / `ErrorCode` / `ErrorCategory` on every JS-facing path.
- Map native `rac_result_t` through structured errors — never collapse failures to a
  plain `Error` string if a typed path exists.
- Keep utility-process RPC **allowlisted** (`ALLOWED_RPC_METHODS`); do not proxy arbitrary
  addon methods.

### Honesty and readiness

- Document what is true today. Do not claim encryption or remote Phase-2 auth unless
  packaging and runtime are wired end-to-end.
- **Windows ships at 0.20.21.** Prebuilds: `darwin-arm64` (llamacpp / ONNX / Sherpa),
  `win32-x64` (llamacpp / ONNX / Sherpa), `win32-arm64` (QHexRT / Hexagon NPU only).
  Linux still has no prebuild. `package.json` keeps `os`/`cpu` permissive on purpose,
  because the TypeScript facade genuinely is cross-platform and narrowing them would
  also block TS-only consumers and our own Linux CI; `resolveAddon()` in
  `src/bridge.ts` names remaining gaps against `PREBUILT_PLATFORMS`.
- **`@runanywhere/electron-qhexrt` ships a real `win32-arm64` plugin** (routable
  `qhexrt:engine-available`, QAIRT 2.48 flat runtime bundled beside it). A shell
  build still exports `rac_plugin_entry_qhexrt` and looks healthy by size, so gate
  on the `qhexrt:engine-available` marker via `check_plugin_natives.py` — `g_qhexrt_llm_ops`
  is internal on PE and is not evidence.
- llama.cpp, ONNX and Sherpa do not build for win-arm64 (ggml rejects MSVC for ARM;
  `FetchONNXRuntime.cmake` has no win-arm64 URL), so the NPU is the only engine on
  that host with no CPU fallback to hide behind.
- Win32 secure store is DPAPI; do not label it "plaintext M0" in headers/docs.
- Phase-2 `completeServicesInitialization` is a local lifecycle seam unless real auth
  lands.

### Native safety

- Unload paths use `take_handle_when_idle`; in-flight generate/embed/transcribe paths take
  `begin_op` leases so unload-during-generate cannot UAF.
- Win32 file/secure paths use wide UTF-16 (`_wfopen`); validate secure keys against
  traversal (`secure_key_ok`).
- Dual packaging path for backends:
  - **FAT (default today):** optional backends link via the CMake `foreach` /
    `RAC_HAVE_BACKEND_*` loop — no hard-coded "always link QHexRT" claims on desktop.
  - **THIN (`-DRAC_ELECTRON_THIN_ADDON=ON` or `RAC_STATIC_PLUGINS=OFF`):** the `.node`
    links only `rac_commons`; engines load at runtime via N-API `loadPlugin` /
    `RUNANYWHERE_PLUGIN_PATHS` (`rac_registry_load_plugin`). Never expose
    `loadPlugin` / `registerBackendPlugin` on the renderer RPC allowlist.
- Backend packages (`packages/{llamacpp,onnx,sherpa,qhexrt}`) use
  `LlamaCPP|ONNX|Sherpa|QHexRT.register()` to record paths; main copies them into
  `RUNANYWHERE_PLUGIN_PATHS` at utility fork only (no RPC).
- **The plugin FILE NAME is a contract.** `rac_registry_load_plugin()` derives the
  symbol it resolves from the filename: `entry_symbol_from_path()` in
  `core/src/plugin/plugin_loader.cpp` strips `lib` /
  `runanywhere_` and the extension, then prepends **`rac_plugin_entry_`**. (Do not
  confuse it with `rac_runtime_entry_`, which the separate *runtime* registry in
  `rac_runtime_registry.cpp` derives the same way for `rac_runtime_*` plugins.)
  A plugin shipped under its CMake target name therefore resolves a symbol that
  does not exist. Two shapes satisfy the contract:
  - llamacpp / onnx / sherpa ship a thin `runanywhere_<id>` **carrier** that links
    `rac_backend_<id>`.
  - QHexRT has **no carrier**: the engine is the plugin, and
    `engines/qhexrt/CMakeLists.txt` renames only its `OUTPUT_NAME` to
    `runanywhere_qhexrt` on shared non-Android builds. The target stays
    `rac_backend_qhexrt`, which is what Android's Kotlin module and JNI bridge
    load by name. A carrier cannot work there: the entry's vtable references the
    op tables as DATA, and MSVC resolves imported data only through
    `__declspec(dllimport)` on declarations shared with the ELF/Mach-O builds.
- **HTTP downloads (D4):** keep `platform_adapter.http_download` NULL. With
  `RAC_DESKTOP_ADAPTER=ON`, `initialize()` registers the libcurl transport via
  `rac_desktop_http_transport_register()` — do not fill the adapter download slot.

### Testing and CI

- Unit tests (`npm test`) are the primary gate for this package today.
- Prefer hermetic fakes over real models for unit coverage.
- Do not add mock public APIs for unfinished capabilities — document and defer.

### Anti-patterns

- Bare `throw new Error(String(racCode))` on the native→JS path.
- Unallowlisted RPC `api[method](...args)`.
- Hardcoded chat templates that ignore model chat formats (Llama-3 / Qwen) when a
  commons/chat-template path exists.
- Claiming parity with Python/Swift for features that are still host-side stubs.
