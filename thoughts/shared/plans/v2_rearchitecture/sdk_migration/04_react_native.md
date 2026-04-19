# React Native SDK — migration plan

> `sdk/runanywhere-react-native/` uses TurboModule + JSI bridges. On
> iOS it delegates to the Swift SDK; on Android it delegates to the
> Kotlin SDK. As the two native SDKs migrate to the new core, RN
> inherits the migration automatically.
>
> **Goal of this migration:** TurboModule native impl is updated to
> link against the new Swift/Kotlin SDK targets; JSI install stays
> the same.

## Step 1 — Current interop layer

- iOS: `sdk/runanywhere-react-native/packages/native/ios/RARuntime.mm`
  calls Swift methods on the RunAnywhere Swift SDK.
- Android: `sdk/runanywhere-react-native/packages/native/android/src/main/cpp/ra_jni_bridge.cpp`
  calls into the Kotlin JNI bridge.
- TS side: `frontends/ts/` provides the TurboModule spec.

## Step 2 — Blocking dependencies

Cannot proceed until:
1. Swift SDK migration (01_swift.md) lands.
2. Kotlin SDK migration (02_kotlin.md) lands.

## Step 3 — Changes needed after those blockers

- iOS `RARuntime.mm`: update Objective-C++ imports to the new Swift
  module name (`import RunAnywhere`) — but if the Swift SDK keeps the
  same module name, ZERO changes.
- Android `ra_jni_bridge.cpp`: same — if Kotlin SDK keeps its package
  name, no changes needed.
- TurboModule spec: unchanged.
- TypeScript public API: unchanged.

## Step 4 — Verification

```
cd sdk/runanywhere-react-native
yarn
yarn build
```

Example app smoke:
```
cd examples/react-native/RunAnywhereAI
yarn ios --no-install
yarn android
```

## Known risks

- **JSI binding stability** — TurboModules have changed shape across
  RN 0.73/0.74/0.75; we target RN 0.76+.
- **Metro symlink resolution** — lerna workspaces can confuse metro;
  same `metro.config.js` as today works.
