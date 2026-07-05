# iOS Example App (RunAnywhereAI)

## Info

SwiftUI reference app for the RunAnywhere SDK. 5-tab `TabView` (`ContentView.swift`): Chat (LLM + tools + LoRA), Vision (VLM camera), Voice Assistant (STT→LLM→TTS), More hub (RAG/STT/TTS/VAD/Storage/Voice Keyboard), Settings. Plus two extensions: `RunAnywhereKeyboard/` (dictation keyboard, App Group + Darwin notification IPC) and `RunAnywhereActivityExtension/` (Live Activity).

Example apps are UI-only: every modality is driven by one `RunAnywhere.*` entry point; no model/engine constants, prompt post-processing, or multi-step bootstrap here — fix such needs in the SDK. Global rules: see repo-root AGENTS.md.

- Pattern: MVVM with Swift Observation — views are pure SwiftUI; `@MainActor @Observable` ViewModels own state and SDK calls; singleton services (`ConversationStore`, `KeychainService`, `SettingsViewModel`, `ModelListViewModel`).
- SDK dependency: `Package.swift` → `.package(path: "../../..")`, products `RunAnywhere`, `RunAnywhereLlamaCPP`, `RunAnywhereONNX`.
- Boot sequence (`RunAnywhereAIApp.swift`): register backends synchronously BEFORE any `await` (`LlamaCPP.register()`, `ONNX.register()`) → `RunAnywhere.initialize()` → `registerModulesAndModels()` → `discoverDownloadedModels()`.
- App-local shims live only in `Extensions/RunAnywhere+ExampleShims.swift`; anything needing net-new C bridge code belongs in the SDK.
- Design tokens centralized: `AppColors` / `AppSpacing` / `AppTypography` / `AdaptiveLayout` — no inline magic numbers.

## Build Info

```bash
cd examples/ios/RunAnywhereAI/

# Build + run (handles SDK + XCFramework deps; scripts live at repo-root scripts/)
../../../scripts/examples/ios/build-and-run.sh simulator "iPhone 16 Pro" --build-sdk
../../../scripts/examples/ios/build-and-run.sh device
../../../scripts/examples/ios/build-and-run.sh mac

# Verification
../../../scripts/examples/ios/verify.sh    # XCFrameworks exist + package resolve + xcodebuild
../../../scripts/examples/ios/smoke.sh     # greps source for SDK API calls, no compilation

# From repo root
./run example ios build        # xcodebuild -scheme RunAnywhereAI (macOS only)
./run example ios clean
./run sdk commons build-ios    # scripts/build/ios-xcframework.sh — rebuild XCFrameworks after C++ changes

# SDK logs while running
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

Requires the XCFrameworks in `sdk/runanywhere-swift/Binaries/` (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`). App Store release: see `docs/RELEASE_INSTRUCTIONS.md`; run `scripts/examples/ios/patch-framework-plist.sh` post-build to fix `MinimumOSVersion` before archiving. Targets iOS 17.5+ / macOS 14.5+.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: Backends must register before any `await` in app boot, or `loadModel()` can race an empty provider registry.
- 2026-07-05: MetalRT and Diffusion backends are deliberately excluded from the v1 build (`RunAnywhereAIApp.swift`); don't reintroduce their registration or `generateImage` UI.
- 2026-07-05: Read typed payloads on `RASDKEvent` (`event.model.kind`, `event.generation.*`); do not read `event.properties[String]`.
