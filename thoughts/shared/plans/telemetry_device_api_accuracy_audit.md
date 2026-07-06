# Telemetry Device API Accuracy Audit

Prepared: 2026-07-06
Scope: C++ commons telemetry/device registration, SDK init/auth metadata, CLI, and the five SDK/example app surfaces: Swift/iOS, Kotlin/Android, Flutter, React Native, and Web.
Mode: audit plus implementation follow-up. The original audit was read-only; the implementation addendum at the end records the fixes applied after approval.

## Executive Summary

The biggest issue is not isolated to a single app: the canonical wire contracts do not contain application identity fields. `SdkInitPhase1Request` sends only environment/API/base URL/device/platform/SDK version, and telemetry events/device registration send SDK/device/model/runtime metadata, but not package name, bundle id, application id, app display name, app version, build number, locale, timezone, browser origin, or raw user agent.

The highest concrete correctness bugs are:

1. Flutter device registration is ABI-mismatched and writes values into the wrong C struct fields.
2. Flutter and Web have hardcoded SDK version paths that can drift from the native commons version.
3. React Native telemetry initializes the C++ telemetry manager with `platform = "react-native"` even though init/device registration usually carry OS-family platform values like `ios` or `android`.
4. Production/staging device registration JSON does not emit an explicit top-level `device_id`; it sends nested `device_info` and relies on `device_fingerprint` fallback.
5. Secure-storage failures are treated like "not found", so device identity can churn if persistent storage fails.

Swift/iOS is the closest source-of-truth implementation. Kotlin/Android is schema-aligned but best-effort unless a real `deviceInfoProvider` is set. React Native and Web have richer public/device capability APIs than what is actually wired into telemetry/device registration. CLI currently does not participate in SDK auth/device registration/telemetry, so it only exposes local CLI/version/info surfaces.

## Canonical Wire Contract Inventory

`idl/sdk_init.proto:86` defines `SdkInitPhase1Request` with:
- `environment`
- `api_key`
- `base_url`
- `device_id`
- `platform`
- `sdk_version`

Missing from init: app package/bundle/application id, app display name, app version, app build number, locale, timezone, origin, browser name/version, raw user agent, manufacturer, install id.

`sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:38` defines telemetry payload base fields including:
- `device_id`
- `session_id`
- `model_id`
- `model_name`
- `framework`
- `device`
- `os_version`
- `platform`
- `sdk_version`

`sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:229` defines device registration info including:
- `device_id`
- `device_model`
- `device_name`
- `platform`
- `os_version`
- `form_factor`
- `architecture`
- `chip_name`
- memory totals/available
- neural engine/GPU/battery/CPU-core fields
- `device_fingerprint`
- `sdk_version`
- `build_token`

Missing from telemetry/device registration: app identity/version/build, locale/timezone, manufacturer as serialized field, platform extras, browser-origin/browser-capability details, and a distinct install id.

## High Severity Findings

### F-001: Flutter Device Registration ABI Is Mismatched

Evidence:
- `sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_device.dart:689`
- `sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_device.dart:493`
- `sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:229`

Flutter defines `RacDeviceRegistrationInfoStruct` as `deviceType`, `osName`, `osVersion`, `sdkVersion`, `appVersion`, `appIdentifier`, `platform`. The C++ ABI expects `device_id`, `device_model`, `device_name`, `platform`, `os_version`, `form_factor`, `architecture`, and the rest of `rac_device_registration_info_t`.

Impact:
- `Platform.operatingSystem` is written into C++ `device_model`.
- hardcoded `0.19.13` is written into C++ `platform`.
- hardcoded `1.0.0` is written into C++ `os_version`.
- `com.runanywhere.flutter` is written into C++ `form_factor`.

This is the most direct "incorrect values sent" issue in the audit.

Recommended fix:
- Regenerate or manually realign the Dart FFI struct to exactly match `rac_device_registration_info_t`.
- Remove app placeholder fields from that struct unless the C ABI/IDL is intentionally extended first.
- Use iOS `CppBridge+Device.swift` and Kotlin `CppBridgeDevice.kt` as behavioral references.

### F-002: App Identity And App Version Are Not In The Canonical Contract

Evidence:
- `idl/sdk_init.proto:86`
- `sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:38`
- `sdk/runanywhere-commons/include/rac/infrastructure/telemetry/rac_telemetry_types.h:229`
- `sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:220`
- `sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:421`

The user-requested fields such as package name, bundle id, application id, version name, version code, CFBundle version/build, app display name, locale, and timezone are not represented in the shared init, telemetry, or device-registration schemas.

Platform status:
- Swift/iOS: does not send bundle id/version/build in init, telemetry manager creation, or registration.
- Kotlin/Android: does not send application id/versionCode/versionName in init, telemetry manager creation, or registration.
- Flutter: attempts hardcoded `appVersion = "1.0.0"` and `appIdentifier = "com.runanywhere.flutter"`, but those are not real C fields and currently corrupt the ABI.
- React Native: example metadata exists in native manifests, but SDK init sends only credentials/environment plus platform-side metadata.
- Web: package metadata exists in `package.json`, but SDK init sends only device id, `platform = "web"`, and SDK version.
- CLI: not an app container; only CLI version and commons version are locally available.

Recommended fix:
- Extend IDL first with a structured `ApplicationInfo` or `ClientInfo` message, not loose strings.
- Carry it through C++ commons and all SDKs.
- Populate per platform from canonical APIs:
  - iOS/macOS: `Bundle.main.bundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, display name.
  - Android: application id/package name, `versionName`, `versionCode`.
  - Flutter: platform package info via plugin/channel, not hardcoded fallback values.
  - React Native: native platform modules for iOS/Android app id/version/build.
  - Web: package/app name and version if bundled, plus origin and browser capability info if approved by privacy policy.
  - CLI: `RCLI_VERSION`, executable/client id, and commons version as CLI-specific client info.

### F-003: Production/Staging Device Registration Omits Top-Level `device_id`

Evidence:
- `sdk/runanywhere-commons/src/infrastructure/device/rac_device_manager.cpp:140`
- `sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:437`
- `sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_json.cpp:481`

`rac_device_manager_register_if_needed()` forces `device_info.device_id = device_id`, but `rac_device_registration_to_json()` only emits top-level `device_id` in development mode. Production/staging serialize nested `device_info` and use `device_id` only as a fallback for `device_fingerprint`.

Impact:
- Backend device upsert behavior may depend on fingerprint/auth context instead of an explicit device id field.
- Dev and prod/staging payload shapes differ materially.

Recommended fix:
- Confirm backend contract.
- If backend expects durable `device_id`, emit it consistently for all environments.
- Keep `device_fingerprint` separate from the SDK-generated device id unless backend intentionally aliases them.

### F-004: React Native Telemetry Platform Is Hardcoded To Binding Name

Evidence:
- `sdk/runanywhere-react-native/packages/core/cpp/bridges/TelemetryBridge.cpp:65`
- `sdk/runanywhere-react-native/packages/core/src/Foundation/Constants/SDKConstants.ts:10`
- `sdk/runanywhere-react-native/packages/core/src/Public/RunAnywhere.ts:181`
- `sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:1696`

React Native init uses OS-family platform from JS (`Platform.OS` -> `ios`/`android`) and native config can carry compile-time OS family. The telemetry manager path instead initializes with `platform = "react-native"`.

Impact:
- Auth/init/device registration and telemetry can disagree on platform for the same install.
- Backend aggregation by platform can misclassify RN telemetry.

Recommended fix:
- Use OS-family platform for telemetry (`ios`/`android`) and add a separate structured SDK binding/client field for `react-native`.
- Avoid fallback `react_native`/`ios` divergence in native init.

### F-005: Flutter And Web SDK Version Paths Can Drift

Evidence:
- `sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_telemetry.dart:102`
- `sdk/runanywhere-web/packages/core/src/Public/RunAnywhere.ts:296`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift:10`
- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/constants/SDKConstants.kt:25`

Flutter telemetry hardcodes `0.19.13` when creating `rac_telemetry_manager`. Web Phase 1 sends hardcoded `0.19.13`. Swift reads `rac_sdk_get_version()`, and Kotlin prefers the native version with a literal fallback.

Impact:
- After version bumps, telemetry/auth/device data can report stale SDK versions in Flutter/Web even when native commons is a different version.

Recommended fix:
- Use generated/package constants only if they are release-synchronized.
- Prefer `rac_sdk_get_version()` wherever a native/WASM export is available.
- Add a release drift check for SDK constants across Swift, Kotlin, Flutter, RN, Web, CLI, and commons.

### F-006: Device Identity Treats All Secure-Storage Failures As Cache Misses

Evidence:
- `sdk/runanywhere-commons/include/rac/core/rac_platform_adapter.h:223`
- `sdk/runanywhere-commons/src/infrastructure/device/device_identity.cpp:74`
- `sdk/runanywhere-commons/src/infrastructure/device/device_identity.cpp:171`

The platform adapter contract distinguishes not-found from failures, but `try_secure_get()` returns empty for any non-success. The identity resolver then falls back to vendor id or a newly generated UUID.

Impact:
- Secure-storage failures can churn durable device identity.
- Apple can often recover via vendor id when wired; Android/Web/desktop generally synthesize and persist UUIDs, so they are more vulnerable.

Recommended fix:
- Preserve error category through the identity resolver.
- Treat storage failure differently from key-not-found.
- Avoid generating a new UUID on transient secure-storage failure unless explicitly allowed by policy.

## Medium Severity Findings

### F-007: Kotlin Android Device Metadata Is Schema-Aligned But Best-Effort

Evidence:
- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeDevice.kt:223`
- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeDevice.kt:255`
- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeTelemetry.kt:74`
- `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp:1512`

Kotlin mirrors iOS in init and telemetry shape, but default Android device info is approximate unless `deviceInfoProvider` is set. Defaults include empty OS build id, `is_simulator = false`, `form_factor = "phone"`, available memory estimated as total/2, `has_neural_engine = false`, and unknown battery/GPU fallbacks.

Impact:
- Values are structurally correct but not necessarily accurate to the physical device.
- Android manufacturer is parsed in JNI but not serialized by the current C registration struct.

Recommended fix:
- Wire a real Android device info provider during SDK initialization.
- Add manufacturer/platform extras only through structured schema changes.
- Avoid false precision for memory/NPU/battery when real data is unavailable.

### F-008: Swift/iOS Is Best Aligned But Still Uses Heuristics

Evidence:
- `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+SdkInit.swift:49`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift:95`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Device.swift:112`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Models/Domain/DeviceInfo.swift:42`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Device/Models/Domain/DeviceInfo.swift:199`

Swift sends persistent device id, platform, and native SDK version correctly. Device registration fills the C struct correctly. Remaining concerns are static/stale mappings and heuristics:
- chip/model maps can become stale.
- broad assumptions like future `iPhone18,*` mapping to `A19 Pro` may be wrong.
- tvOS/watchOS/visionOS device factory paths map platform to `ios`.
- Neural Engine availability/core count is inferred rather than detected.
- available memory is approximate.

Recommended fix:
- Keep iOS as source of truth for struct shape, but replace stale-prone mappings with runtime APIs where possible.
- Keep SDK platform (`ios`, `macos`, etc.) and device platform consistent across Apple targets.

### F-009: React Native Device Registration Uses Placeholders And Public Metadata Is Richer Than Sent Metadata

Evidence:
- `sdk/runanywhere-react-native/packages/core/cpp/bridges/InitBridge.cpp:1819`
- `sdk/runanywhere-react-native/packages/core/src/specs/RunAnywhereDeviceInfo.nitro.ts:7`
- `sdk/runanywhere-react-native/packages/core/ios/PlatformAdapterBridge.m:459`
- `sdk/runanywhere-react-native/packages/core/android/src/main/java/com/margelo/nitro/runanywhere/PlatformAdapterBridge.kt:301`
- `sdk/runanywhere-react-native/packages/core/android/src/main/java/com/margelo/nitro/runanywhere/SecureStorageManager.kt:126`

React Native exposes rich public device metadata through Nitro, but registration sends a narrower callback payload. Android registration uses placeholders such as `hasNeuralEngine = false`, `deviceName = deviceModel`, `batteryLevel = -1`, empty battery state, and `isLowPowerMode = false`. Android GPU/memory are heuristic, and encrypted prefs do not generally survive uninstall despite comments suggesting otherwise.

Impact:
- Public device metadata and telemetry/device-registration metadata can disagree.
- Android capability values can under-report NPU/battery/power state.

Recommended fix:
- Drive registration from the same structured provider used by the public device-info API.
- Avoid placeholder values where unknown/null/omitted would be more accurate.

### F-010: Web Capabilities Are Detected But Not Wired Into Init/Registration

Evidence:
- `sdk/runanywhere-web/packages/core/src/Public/RunAnywhere.ts:296`
- `sdk/runanywhere-web/packages/core/src/Infrastructure/DeviceCapabilities.ts:41`
- `sdk/runanywhere-web/packages/core/src/runtime/PlatformAdapter.ts:267`

Web detects browser capabilities such as WebGPU, SharedArrayBuffer, cross-origin isolation, OPFS, browser name, OS family, memory, and cores. That helper is not wired into init/device registration, which sends only a sparse device id/platform/sdk version path.

Impact:
- Backend cannot distinguish important web runtime/device capability differences from telemetry/init payloads.
- Device info remains coarse (`deviceModel = "Browser"`, `formFactor = "desktop"`, `architecture = "wasm32"`, available memory often `0`, OS version is only OS family).

Recommended fix:
- Add a structured web capability/platform extras contract if backend needs these values.
- Make privacy decisions explicit for origin, user agent, language, timezone, and browser data.

### F-011: CLI Does Not Participate In SDK Telemetry/Auth/Device Registration

Evidence:
- `sdk/runanywhere-cli/src/bootstrap.cpp:51`
- `sdk/runanywhere-cli/src/bootstrap.cpp:74`
- `sdk/runanywhere-cli/src/bootstrap.cpp:84`
- `sdk/runanywhere-cli/src/commands/cmd_version.cpp:20`
- `sdk/runanywhere-cli/src/commands/cmd_info.cpp:31`
- `sdk/runanywhere-cli/src/commands/cmd_backends.cpp:46`

`rcli` initializes desktop adapter, model paths, logger, desktop HTTP transport, backend plugins, and catalog. It does not call SDK phase init, auth, device manager registration, telemetry manager creation, or telemetry sink registration.

Impact:
- If CLI analytics/device registration are expected, they are absent.
- If CLI is intended to be local-only, current behavior is probably intentional, but should be documented.

Recommended fix:
- Decide explicitly whether CLI should be a telemetry client.
- If yes, model CLI as a separate client/app identity (`client_kind = "cli"`, `client_version = RCLI_VERSION`, `commons_version = rac_sdk_get_version()`).

## Low Severity / Consistency Findings

### F-012: Logging Metadata Differs Across SDKs

Evidence:
- `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift:163`
- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/infrastructure/logging/SDKLogger.kt:422`
- `sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/logging/sdk_logger.dart:222`

Swift/Kotlin enrich logs with device metadata when enabled. Flutter has the config flag but forwards caller metadata without equivalent enrichment.

Recommended fix:
- Decide whether logging metadata should be aligned with telemetry metadata.
- If yes, use the same structured device/client info provider per SDK.

### F-013: Example App Device Info Is Mostly Local UI/Benchmark Data

Evidence:
- `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/DeviceInfoService.swift:153`
- `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/DeviceInfoService.swift:170`
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/models/DeviceInfo.kt:16`
- `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/benchmark/BenchmarkRunner.kt:46`
- `examples/flutter/RunAnywhereAI/lib/core/services/device_info_service.dart:35`
- `examples/flutter/RunAnywhereAI/lib/core/services/device_info_service.dart:59`
- `examples/react-native/RunAnywhereAI/App.tsx:206`
- `examples/web/RunAnywhereAI/src/main.ts:325`

The example apps display or benchmark device/app metadata locally, but that data is not the SDK telemetry source of truth. Some local values are deliberately approximate: iOS sample estimates available memory as half total, Flutter sample uses `0` memory and `hasNeuralEngine = false`, and Web/RN examples initialize SDK with only credentials/environment.

Recommended fix:
- Keep example apps thin.
- Do not patch example apps to send telemetry metadata directly.
- Fix telemetry and device registration in SDK/common layers.

## Platform-by-Platform Snapshot

| Platform | Init Metadata | Telemetry Metadata | Device Registration Metadata | App Identity/Version Status | Main Risk |
| --- | --- | --- | --- | --- | --- |
| C++ commons | device id, platform, SDK version | device/model/framework/platform/SDK/session metrics | device model/name/platform/OS/arch/chip/memory/NPU/GPU/battery/fingerprint | no app fields | contract missing app/client info; prod registration omits top-level `device_id` |
| Swift/iOS | persistent id, `SDKConstants.platform`, `rac_sdk_get_version()` | same plus model/OS | C struct filled correctly | not sent | static device/chip heuristics and Apple target platform inconsistencies |
| Kotlin/Android | schema-aligned device/platform/version | schema-aligned manager setup | JSON schema aligned through JNI | not sent | provider not wired by default; many best-effort values |
| Flutter | partially schema-aligned init, but telemetry version hardcoded | hardcoded SDK version path | ABI-mismatched struct | hardcoded placeholders in wrong struct | corrupted registration values |
| React Native | JS/native platform can be `ios`/`android` | telemetry platform hardcoded `react-native` | narrower than public Nitro device info | not sent | platform disagreement and placeholder Android values |
| Web | device id, `web`, hardcoded SDK version | sparse web metadata | detected capabilities not wired | not sent | browser/runtime capability data absent from wire |
| CLI | no SDK phase init | no telemetry manager/sink | no device registration | CLI version only | unclear whether telemetry is intentionally absent |

## Suggested Remediation Order

1. Fix Flutter FFI struct alignment against `rac_device_registration_info_t`.
2. Decide and document the canonical backend contract for `device_id` in production/staging registration.
3. Add structured client/application metadata to IDL/C++ first, then plumb all SDKs.
4. Normalize `platform` semantics: OS family in `platform`; SDK binding/client type in a separate field.
5. Remove hardcoded SDK version telemetry paths by using `rac_sdk_get_version()` or generated release-synchronized constants.
6. Preserve secure-storage error semantics in device identity resolution.
7. Wire real Android/RN/Web device capability providers into registration/telemetry, avoiding placeholder values where unknown is more accurate.
8. Decide whether CLI should be a telemetry client and, if yes, add CLI-specific client metadata rather than pretending it is a mobile app.

## Verification To Run After Fixes

No tests were added or run in this audit. After implementation, recommended verification:

- Add a small C++ JSON serialization test for device registration in dev/staging/prod, including explicit `device_id`.
- Add SDK-level smoke tests or golden payload tests for init/device registration metadata per platform.
- Add a release drift check for SDK version constants across Swift/Kotlin/Flutter/RN/Web/CLI.
- For Flutter, add an FFI layout/size smoke check against the C struct.
- For RN/Web, add tests proving platform/client-kind separation.
- Manually inspect sample payloads from each SDK before accepting backend analytics as accurate.

## Implementation Checklist

Status legend: `[ ]` pending, `[~]` in progress, `[x]` complete.

- [x] Align the shared C++ telemetry/device registration contract with explicit client/application metadata and consistent device id serialization.
- [x] Fix Flutter FFI device registration layout and remove hardcoded placeholder app/version values from C struct positions.
- [x] Normalize SDK version sources in Flutter/Web to use the native commons version or a synchronized generated constant.
- [x] Normalize React Native platform telemetry so OS family and SDK binding/client kind are separate.
- [x] Improve secure-storage error semantics for device identity so storage failures do not silently generate new durable IDs.
- [x] Wire platform client/app metadata providers through Swift, Kotlin, Flutter, React Native, Web, and CLI where supported.
- [x] Run bounded verification commands only, with no unbounded native builds.

## Implementation Addendum

Completed: 2026-07-06.

Changes applied:
- C++ commons now owns a copied `rac_client_info_t` (`sdk_binding`, app identifier/name/version/build, locale, timezone) inside `rac_sdk_config_t`, exposes `rac_sdk_set_client_info()` / `rac_sdk_get_client_info()`, and includes this metadata in device registration JSON.
- Production/staging device registration now emits explicit top-level `device_id` in addition to nested `device_info`.
- Device identity no longer treats secure-storage errors as cache misses. Real storage failures reuse the in-process cached id for the same adapter when possible, otherwise return the storage error instead of generating a new durable id.
- Swift, Kotlin, Flutter, React Native, Web, and CLI now populate client/app metadata from platform-native sources where available. Kotlin/RN Android metadata code avoids direct deprecated package APIs and uses the modern API on Android 13+ with reflection below that API level.
- Flutter device-registration FFI now matches `rac_device_registration_info_t` field-for-field and uses real `package_info_plus` app metadata instead of placeholder strings.
- Flutter telemetry uses `SDKConstants.version`; Web Phase 1 prefers the native WASM `rac_wasm_get_version_*` exports and only falls back to the package constant.
- React Native telemetry now uses OS-family platform (`ios`/`android`) and reports `react_native` separately as `sdk_binding`.
- CLI bootstrap now initializes commons SDK metadata with persistent desktop device id, OS-family desktop platform, CLI version, locale, timezone, and CLI client identity.

Verification run:
- `git diff --check`
- `c++ -std=c++20 -fsyntax-only` on changed commons telemetry/device/environment files.
- `c++ -std=c++20 -fsyntax-only` on `sdk/runanywhere-cli/src/bootstrap.cpp` with protobuf include flags.
- `flutter pub get` in `sdk/runanywhere-flutter`.
- `flutter analyze packages/runanywhere/lib/native/dart_bridge_device.dart packages/runanywhere/lib/native/dart_bridge_telemetry.dart`.
- `npx tsc --noEmit --pretty false -p packages/core/tsconfig.json` in `sdk/runanywhere-web`.
- `ANDROID_HOME=/Users/sanchitmonga/Library/Android/sdk ANDROID_SDK_ROOT=/Users/sanchitmonga/Library/Android/sdk ./gradlew compileDebugKotlin -Prunanywhere.useLocalNatives=false --max-workers=2` in `sdk/runanywhere-kotlin`.
- `yarn typecheck` in `sdk/runanywhere-react-native`.
- `ANDROID_HOME=/Users/sanchitmonga/Library/Android/sdk ANDROID_SDK_ROOT=/Users/sanchitmonga/Library/Android/sdk ./gradlew :runanywhere_core:compileDebugKotlin --max-workers=2` in `examples/react-native/RunAnywhereAI/android`.

Notes:
- A full CMake `rcli` build was not completed because the configure path pulled backend dependency setup despite backend options being disabled; it was stopped before compilation and the partial build directory was removed.
- Kotlin compile still reports pre-existing unrelated deprecation warnings in security/generated/LLM code. No deprecation suppressions or direct deprecated Android package metadata calls remain in the telemetry/app-metadata files changed for this plan.

## Rebuild And Push Checklist

Started: 2026-07-06.

Status legend: `[ ]` pending, `[~]` running, `[x]` passed, `[!]` failed or blocked.

- [x] Native/CLI release build with bounded Ninja parallelism (`cmake --preset rcli-macos-release`, `cmake --build build/rcli-macos-release -j 2`, `rcli version` smoke).
- [x] Swift SDK build (`swift build --jobs 2`).
- [x] Kotlin SDK Android assemble (`./gradlew assembleDebug -Prunanywhere.useLocalNatives=false --max-workers=2`).
- [!] Flutter SDK analysis/build gate: targeted changed files passed earlier; `melos run analyze` is blocked by local stale Dart 2.17 global tooling, and direct package analysis for `packages/runanywhere` fails on pre-existing unrelated analyzer infos in LLM/tool-calling files. Backend packages `runanywhere_llamacpp`, `runanywhere_onnx`, and `runanywhere_qhexrt` pass.
- [x] React Native SDK type/native gate (`yarn typecheck`; RN Android native Kotlin compile passed earlier in this plan).
- [x] Web SDK build (`npm run build`).
- [x] Android example build (`./gradlew :app:assembleDebug --max-workers=2`).
- [x] iOS example verification (`xcodebuild ... -jobs 2 build`).
- [!] Flutter example verification/build: generated solutions YAML was refreshed and debug APK build passed; `flutter analyze` remains blocked by pre-existing unrelated analyzer infos in `vlm_view_model.dart` and `voice_assistant_view.dart`.
- [x] React Native example verification/build (`yarn typecheck`, `./gradlew :app:assembleDebug --max-workers=2`).
- [x] Web example build (`npm run build` after installing missing local dependencies).
- [x] Commit verified changes and push to `origin/smonga/npu_support` (`565d50417`).

Additional rebuild notes:
- The initial iOS example link failed because the local `RACommons.xcframework` was stale and missing `rac_sdk_set_client_info`.
- Rebuilt Swift XCFrameworks with `RAC_BACKEND_ONNX=ON RAC_BACKEND_SHERPA=ON ./sdk/runanywhere-swift/scripts/build-core-xcframework.sh`.
- Verified the refreshed iOS simulator `librac_commons.a` exports `_rac_sdk_set_client_info` and `_rac_sdk_get_client_info`.
- Reran the iOS example build successfully after the XCFramework refresh.
