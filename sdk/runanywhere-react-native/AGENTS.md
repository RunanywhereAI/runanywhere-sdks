# RunAnywhere React Native SDK

## Info

Yarn Berry 3.6.1 workspaces monorepo of three npm packages bridging the C++ core (`runanywhere-commons`) into React Native via NitroModules (JSI HybridObjects) — not the classic bridge or TurboModules. Global rules: see repo-root AGENTS.md; the Swift SDK (`sdk/runanywhere-swift/`) is the business-logic source of truth.

- `packages/core` — `@runanywhere/core`: `RunAnywhere` facade (`src/Public/RunAnywhere.ts`), extension modules per capability (`src/Public/Extensions/`), Nitro specs (`src/specs/*.nitro.ts`), C++ bridge (`cpp/HybridRunAnywhereCore*.cpp`), platform adapters (iOS `ios/`, Android `android/src/main/cpp/`)
- `packages/llamacpp` — `@runanywhere/llamacpp`: LlamaCPP backend registration (LLM + VLM)
- `packages/onnx` — `@runanywhere/onnx`: ONNX/Sherpa backend registration (STT/TTS/VAD)
- Extra workspace: `../shared/proto-ts` (`@runanywhere/proto-ts`) — generated protobuf TypeScript types; all modality DTOs come from here

Key patterns:
- Backend registration is explicit: apps call `LlamaCPP.register()` / `ONNX.register()` after `RunAnywhere.initialize()`.
- Streaming is proto-byte subscriptions (`subscribeProtoEvents`) decoded into generated messages; no JS-side event sinks.
- Hermes cannot use `for await...of` with Nitro async iterables — always manual `iterator.next()` loops.
- TypeScript-only distribution: `main`/`exports` point at `src/index.ts`; Metro resolves source, no bundler.

## Build Info

```bash
# From sdk/runanywhere-react-native/
yarn install                # required BEFORE the example app installs/typechecks
yarn typecheck              # primary verification gate (all workspaces)
yarn lint | yarn lint:fix
yarn build                  # tsc emit
yarn nitrogen:all           # regenerate Nitro bridge code after spec changes
yarn core:nitrogen          # core only (+ scripts/fix-nitrogen-output.js post-patch)

# From repo root (dev entry point)
./run sdk rn typecheck      # yarn install + core typecheck
./run sdk rn clean

# Native binaries (repo root; rebuild after C++ commons changes)
./run sdk commons build-android      # scripts/build/android.sh
./run sdk commons build-ios          # scripts/build/ios-xcframework.sh (macOS only)
scripts/release/package-rn.sh --natives-from PATH   # stage natives into packages, produce .tgz

# Proto codegen (repo root)
./run codegen ts            # scripts/codegen/generate_ts.sh → sdk/shared/proto-ts
```

Requirements: Node 18+, RN >= 0.83 peer (example runs 0.85.x), iOS 15.1+, Android minSdk 24, C++20. No unit tests currently exist.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: After nitrogen runs, `scripts/fix-nitrogen-output.js` must run for core (removes a `#include <NitroModules/Null.hpp>` that doesn't exist in the pinned nitro version); `yarn core:nitrogen` already chains it.
- 2026-07-05: Android bridge builds with 16 KB page alignment (`max-page-size=16384`) — required for Android 15+; don't drop the flag.
- 2026-07-05: HTTP transport must be registered before any native HTTP fires — iOS via `URLSessionHttpTransport`, Android via `RunAnywhereCorePackage` companion `init` (OkHttp over JNI).
