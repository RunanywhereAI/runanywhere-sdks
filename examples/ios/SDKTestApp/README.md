# SDK Test App

Minimal iOS/macOS app to verify RunAnywhere SDK integration. It is **not** the full RunAnywhereAI demo—it only initializes the SDK, registers sample models, and shows SDK status and registered frameworks.

## What it does

- Initializes the RunAnywhere SDK (development mode).
- Registers LlamaCPP and ONNX backends and a few sample models (e.g. Qwen 0.5B, Whisper Tiny).
- Shows **SDK Status** (Active/Inactive).
- Lists **Registered frameworks** (e.g. LlamaCpp, ONNX) with pull-to-refresh.

## Requirements

- Xcode 15+
- iOS 17+ / macOS 14+
- Same repo setup as RunAnywhereAI: SDK is consumed via local package path (`../../..`).

## Build and run

1. **First-time SDK setup** (if using local binaries):

   ```bash
   cd ../../sdk/runanywhere-swift
   ./scripts/build-swift.sh --setup
   ```

2. Open the project in Xcode:

   ```bash
   open SDKTestApp.xcodeproj
   ```

3. Select the **SDKTestApp** scheme and an iOS Simulator or Mac destination, then run (⌘R).

## Project layout

- `Package.swift` – SPM dependency on the repo root package (RunAnywhere, RunAnywhereONNX, RunAnywhereLlamaCPP).
- `SDKTestApp.xcodeproj` – App target only (no unit/UI tests).
- `SDKTestApp/` – App source: `App/SDKTestAppApp.swift`, `App/ContentView.swift`, assets, entitlements.

Use this app to confirm the SDK resolves, builds, and runs in a minimal app before trying the full RunAnywhereAI sample.
