# React Native Example App (RunAnywhereAI)

## Info

React Native 0.85 demo app for the RunAnywhere SDK: LLM chat (streaming, tools, thinking mode), STT, TTS, voice assistant, RAG, VLM camera, solutions runner, settings/model management, in a tab UI (React Navigation). State via Zustand (`src/stores/conversationStore.ts`, file-backed JSON persistence).

Example apps are UI-only: thin `RunAnywhere.*` calls, no business logic or SDK-internal knowledge. Global rules: see repo-root AGENTS.md.

- STANDALONE Yarn Berry 3.6.1 project (own `.yarnrc.yml`, `nodeLinker: node-modules`) — not a workspace of the SDK monorepo. `@runanywhere/{core,llamacpp,onnx,proto-ts}` resolve via `portal:` into `sdk/`, with a `resolutions` override for `@runanywhere/proto-ts` (and `react` pinned exactly — currently 19.2.7).
- All SDK bridging is NitroModules (JSI); several RN libs have autolinking disabled in `react-native.config.js`; Android SDK modules are included manually in Gradle.
- Register models through `RunAnywhere.registerModel()` / `registerMultiFileModel()` with generated proto enums from `@runanywhere/proto-ts` — never hand-written enums.

## Build Info

```bash
# PREREQUISITE: install the SDK workspace first, or portal: deps are broken
cd sdk/runanywhere-react-native && yarn install

cd examples/react-native/RunAnywhereAI/
yarn install                # runs postinstall: scripts/examples/react-native/postinstall.js
yarn typecheck              # primary verification gate (also syncs solutions YAMLs)
yarn start                  # Metro
yarn ios | yarn android
yarn lint | yarn lint:fix | yarn format | yarn unused
yarn pod-install            # scripts/examples/react-native/pod-install.sh
yarn clean                  # full clean rebuild (watchman + node_modules + Pods)

# Verification (scripts live under repo-root scripts/)
../../../scripts/examples/react-native/smoke.sh    # SDK API coverage grep + typecheck
../../../scripts/examples/react-native/verify.sh   # typecheck + optional builds
# verify.sh env: RUN_ANDROID / RUN_IOS / RUN_PODS / REFRESH_ANDROID_NATIVE / REFRESH_IOS_NATIVE

# After C++ changes (repo root)
./run sdk commons build-android                       # scripts/build/android.sh
./run sdk commons build-ios                           # scripts/build/ios-xcframework.sh (macOS)
scripts/release/package-rn.sh --natives-from PATH     # re-stage natives into RN packages
```

Postinstall applies `patches/` via patch-package and `scripts/examples/react-native/patch-agp-version.js`. iOS 15.1+, arm64-only pods; Android minSdk 24, NDK 27, 16 KB page alignment, `pickFirsts` for duplicate `.so`s. No test files exist — verification is typecheck + smoke.

Hermes cannot use `for await...of` with Nitro async iterables — always manual `iterator.next()` loops (see `ChatScreen.tsx`, `VLMService.ts`).

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: Metro (no watchman) ENOENT-crashes on stale `**/android/.cxx` dirs after native builds — delete them and kill ghost Metro processes before starting.
- 2026-07-05: `react` must exactly match the resolutions pin (19.2.7); a plain `yarn install` can re-break it → `getPaperRenderer` render crash.
- 2026-07-05: gorhom bottom-sheet v5 is incompatible with reanimated 4 (`present()` no-ops); use the custom sheet at `src/components/ui/BottomSheet.tsx`.
- 2026-07-05: UI/UX quality bar — screens must match and beat the iOS + Android example apps; reference both per screen.
