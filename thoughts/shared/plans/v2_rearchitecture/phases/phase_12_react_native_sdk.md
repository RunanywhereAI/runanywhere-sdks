# Phase 12 — React Native SDK migration + RN example app

> Goal: rewire `sdk/runanywhere-react-native/` onto the new commons C
> ABI. Use React Native's new architecture (TurboModules +
> JSI) for zero-bridge calls. Delegate to the Swift SDK on iOS and to
> the Kotlin SDK on Android — RN doesn't reach the C ABI directly;
> it reuses the already-migrated native SDKs.

---

## Prerequisites

- Phase 9 (Swift SDK) complete — RN iOS depends on it.
- Phase 10 (Kotlin SDK) complete — RN Android depends on it.
- A working React Native 0.76+ environment locally for development.

---

## What this phase delivers

1. **TypeScript-proto3 codegen** from commons `idl/` via
   `@bufbuild/protoc-gen-es` into
   `packages/core/src/proto/`. Identical generated types are shared
   with the web SDK (Phase 13).

2. **TurboModule + JSI bridge** — `RARuntime` TurboModule with a
   JSI-based stream pump. No MessageQueue / JSON strings for hot
   paths.

3. **iOS native module delegating to Swift SDK** — a thin Obj-C++
   shim that calls into `RunAnywhere` Swift actors.

4. **Android native module delegating to Kotlin SDK** — a thin
   Kotlin bridge that calls the KMP `LLMSession` etc.

5. **Public TypeScript API** — async iterables
   (`for await (const ev of session.generate(prompt))`) for streams,
   `async` for one-shots.

6. **Rewritten RN example app** at `examples/react-native/` on the
   new architecture, using the new API.

7. **npm publishing pipeline** per package (lerna-managed monorepo).

---

## Exact file-level deliverables

### Package structure (lerna)

```text
sdk/runanywhere-react-native/
├── lerna.json                              UPDATED
├── package.json                            UPDATED — workspaces config
├── tsconfig.base.json
├── packages/
│   ├── core/
│   │   ├── package.json                    core SDK — no native code, pure TS
│   │   ├── src/
│   │   │   ├── index.ts                    public re-exports
│   │   │   ├── runAnywhere.ts              bootstrap()
│   │   │   ├── llm/
│   │   │   │   ├── LLMSession.ts
│   │   │   │   └── LLMEvent.ts             discriminated union
│   │   │   ├── stt/, tts/, vad/, vlm/, rag/, voiceAgent/, wakeWord/, download/
│   │   │   ├── proto/                      protoc-gen-es output (gitignored)
│   │   │   │   └── ra/idl/*.ts
│   │   │   ├── bridge/
│   │   │   │   ├── NativeRARuntime.ts      TurboModule spec
│   │   │   │   ├── jsiDispatch.ts          JSI adapter — polls via requestAnimationFrame+async
│   │   │   │   └── codec.ts                proto encode/decode helper
│   │   │   └── errors/
│   │   │       └── RAError.ts              union type
│   │   └── tsconfig.json
│   └── native/
│       ├── package.json                    native module — installed by apps
│       ├── ios/
│       │   ├── RARuntime.podspec
│       │   ├── RARuntime/
│       │   │   ├── RARuntime.mm            Obj-C++ TurboModule impl — calls Swift SDK
│       │   │   ├── RARuntimeJSI.mm         JSI pump
│       │   │   └── RARuntime-Bridging-Header.h
│       │   └── BUILD_NOTES.md
│       ├── android/
│       │   ├── build.gradle                depends on sdk/runanywhere-kotlin
│       │   └── src/main/
│       │       ├── java/com/runanywhere/rn/
│       │       │   ├── RARuntimeModule.kt  TurboModule impl — calls KMP LLMSession etc
│       │       │   ├── RARuntimePackage.kt registration
│       │       │   └── RARuntimeJSI.kt     JSI pump
│       │       └── cpp/                    only if we need a C++ JSI helper
│       └── src/                            TypeScript type stubs for the TurboModule
├── scripts/
│   ├── codegen-proto.sh                    uses @bufbuild/protoc-gen-es
│   └── release.sh
└── README.md
```

### Public TS API shape

```ts
export interface LLMSession {
  generate(prompt: Prompt): AsyncIterable<LLMEvent>;
  cancel(): void;
  close(): Promise<void>;
}

export namespace RunAnywhere {
  export async function bootstrap(config?: BootstrapConfig): Promise<void>;
  export async function createLLMSession(cfg: LLMConfig): Promise<LLMSession>;
  export async function createVoiceAgent(cfg: VoiceAgentConfig): Promise<VoiceAgent>;
  // ...
}
```

### TurboModule spec

`packages/core/src/bridge/NativeRARuntime.ts`:

```ts
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  // LLM
  llmCreate(cfgBytes: string /* base64 */): Promise<number /* handle */>;
  llmStart(handle: number, promptBytes: string): Promise<void>;
  llmNext(handle: number): Promise<string | null>;  // base64 event, or null on end
  llmCancel(handle: number): void;
  llmDestroy(handle: number): Promise<void>;
  // …similar for STT, TTS, VAD, VLM, RAG, VoiceAgent…

  // JSI install — gives the JS runtime access to a synchronous
  // ByteArray-returning `next()` that bypasses the bridge. Called
  // once at bootstrap.
  installJSI(): boolean;
}

export default TurboModuleRegistry.getEnforcing<Spec>('RARuntime');
```

### JSI pump

`RARuntimeJSI.mm` (iOS) installs a JSI host function
`global.__raLlmNext(handle)` that calls the Swift SDK's
`RABridge.llmNext` synchronously from the JS thread. Avoids the RN
bridge's JSON serialisation per event. The TurboModule wraps each
JSI call in a `Promise`; internally the JS side prefers the JSI path
when installed.

### Example app (examples/react-native/)

```text
examples/react-native/runanywhere_ai/
├── package.json                    depends on sdk/runanywhere-react-native workspaces
├── App.tsx
├── src/
│   ├── screens/
│   │   ├── ChatScreen.tsx          useLLMSession + for-await loop
│   │   ├── VoiceAgentScreen.tsx
│   │   └── SettingsScreen.tsx
│   ├── components/
│   ├── hooks/
│   │   ├── useLLMSession.ts
│   │   └── useVoiceAgent.ts
│   └── navigation/
├── ios/                            react-native-link installed; runanywhere cocoapod added
├── android/                        settings.gradle includes the runanywhere module
└── e2e/
    └── app.e2e.ts                  Detox
```

### Deletions

```text
sdk/runanywhere-react-native/packages/*/src/legacy/        DELETE
sdk/runanywhere-react-native/packages/*/ios/RACallback*    DELETE
sdk/runanywhere-react-native/packages/*/android/**/OldModule*.kt  DELETE
examples/react-native/**/old_*                             DELETE
```

### Tests

```text
packages/core/src/__tests__/
  ├── llmSession.spec.ts
  ├── voiceAgent.spec.ts
  ├── codec.spec.ts                — proto round-trip
  └── errorMapping.spec.ts

examples/react-native/runanywhere_ai/e2e/
  └── app.e2e.ts                   — Detox iOS + Android
```

---

## Implementation order

1. **Add react-native 0.76+ support**. New architecture on by default.

2. **Run `@bufbuild/protoc-gen-es`** once, inspect output, confirm
   shared with web SDK (same invocation).

3. **Write `NativeRARuntime.ts` TurboModule spec.** Codegen the C++
   type via react-native's codegen.

4. **iOS side**: write `RARuntime.mm` wrapping the Swift SDK.
   Consumed via the Swift interop layer. Verify a plain
   `llmCreate + llmDestroy` round-trips from TS.

5. **Android side**: write `RARuntimeModule.kt` wrapping the Kotlin
   SDK. Same smoke test from TS.

6. **Add JSI pump** on both platforms. Benchmark `llmNext` JSI vs
   TurboModule bridge; expect 2-3× speed-up on token streams.

7. **Write the TS public API** — async iterables on top of the
   TurboModule.

8. **Rewrite the RN example app.** Remove any v1 hooks. Use the new
   `useLLMSession` / `useVoiceAgent` hooks.

9. **CI**: add `.github/workflows/rn-sdk.yml` + `rn-app.yml` that
   build iOS + Android and run Detox on emulators.

10. **npm publish**. lerna handles the per-package versioning.

---

## API changes

### New public TS API

Per-module imports:

```ts
import { RunAnywhere, LLMSession, VoiceAgent, RagPipeline } from '@runanywhere/core';

const session = await RunAnywhere.createLLMSession({ modelId: 'qwen3-4b-q4_k_m' });
for await (const event of session.generate({ messages: [...] })) {
  if (event.type === 'token') console.log(event.text);
  if (event.type === 'end')   break;
}
await session.close();
```

### Removed

- Any `EventEmitter` / `DeviceEventEmitter` subscription used for
  streams.
- v1 `NativeEventEmitter` bridges.
- Legacy TypeScript `class` bridges that only marshalled JSON.

---

## Acceptance criteria

- [ ] `yarn` + `yarn test` green across the lerna workspace.
- [ ] Detox iOS + Android e2e green on CI.
- [ ] `yarn typecheck` green with strict mode.
- [ ] Example app chat + voice agent flow works on:
  - iOS Simulator + physical iPhone
  - Android emulator + physical Pixel
- [ ] `.github/workflows/rn-sdk.yml` + `rn-app.yml` green.
- [ ] `grep -rn "DeviceEventEmitter\|RCTEventEmitter" sdk/runanywhere-react-native/`
      returns empty inside hot paths reachable from streams.
- [ ] JSI benchmark: `llmNext` mean round-trip ≤ 0.5 ms (vs ~2 ms
      via the RN bridge).

## Validation checkpoint — frontend major

See `testing_strategy.md`. Phase 12 runs:

- **Compilation.**
  ```bash
  cd sdk/runanywhere-react-native
  yarn && yarn build                                            # TS build
  yarn typecheck                                                # tsc --noEmit
  yarn lint                                                     # ESLint
  yarn test                                                     # jest
  (cd ../../examples/react-native/runanywhere_ai
    && yarn ios --no-install                                    # Xcode build
    && yarn android)                                            # Gradle build
  ```
  All exit 0 with **zero ESLint errors, zero TS errors, zero new
  warnings**. Fix anything that surfaces in-PR.
- **TurboModule codegen clean.** `npx react-native codegen` runs
  clean against the module spec; no manual patches to generated
  files.
- **JSI install verification.** `installJSI()` returns true on
  both iOS and Android; fallback path does not trigger when JSI
  is installed.
- **Example app on iOS + Android.** `yarn ios` + `yarn android`
  launch to first screen on simulator + emulator; chat + voice
  agent smoke. Physical-device run for at least one platform.
- **Detox e2e green.** Full suite on both platforms on CI.
- **Feature parity.** Every RN SDK feature pre-Phase-12 works
  post-Phase-12.
- **Metro resolver sanity.** After a fresh `yarn install`, metro
  resolves `@runanywhere/core` via the workspace symlink without
  errors.
- **Bundle size.** JS bundle ≤ 1 MB after minification
  (excluding the native module's binary payload which lives
  outside the JS bundle).
- **CI.** `.github/workflows/rn-sdk.yml` + `rn-app.yml` green.

---

## What this phase does NOT do

- No Expo-managed workflow support in the example app. Requires bare
  RN due to native module. Can be added later via a config plugin.
- No Windows / macOS RN. Primary targets iOS + Android.
- No react-native-web support. React Native Web users should consume
  the Web SDK directly from Phase 13.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| TurboModule codegen doesn't emit the right Obj-C signature for Promise-returning methods | Low | Follow the react-native docs boilerplate exactly. If codegen fails, fall back to the Promise variant with explicit resolve/reject block in Obj-C++ |
| JSI install happens before the Swift SDK module is loaded and throws a null pointer | Medium | `installJSI()` returns false if the underlying native SDK isn't ready; TS side falls back to the Promise-based bridge until a second `installJSI()` succeeds |
| Base64 encoding on every event adds overhead we can't afford for voice agent | Medium | JSI path returns an `ArrayBuffer` directly, zero-copy. Only the fallback Promise path uses base64 |
| Android's ReactContextBaseJavaModule threading conflicts with KMP coroutines | Medium | Dispatch the KMP call into `Dispatchers.Default` inside the TurboModule; RN's Promise is resolved on whatever thread finishes |
| Lerna monorepo + yarn workspaces + RN metro resolver get confused about symlinks | High | Use metro's `watchFolders` to include the workspace root and `extraNodeModules` to pin `@runanywhere/core` to the workspace package. Documented in the example's README |
| AsyncIterable polyfill issues on older Hermes versions | Low | Require Hermes ≥ what ships with RN 0.76 (supports for-await-of natively). Document minimum RN version |
| iOS example app's CocoaPods setup fights the Swift SDK's SPM-only distribution | High | The RN native module podspec installs the XCFramework via a script phase that downloads from the commons release URL. Proven pattern |
| Detox flake on slow CI runners | Medium | Retry-once semantics; cap suite at 15 min; escalate only if flake rate > 5 % over a week |
