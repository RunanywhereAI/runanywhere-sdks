# YapRun

On-device voice dictation for iOS and macOS, powered by the RunAnywhere SDK. All speech recognition runs locally — your voice never leaves your device.

**[runanywhere.ai/yaprun](https://runanywhere.ai/yaprun)** | [TestFlight Beta](https://testflight.apple.com/join/6N7nBeG8) | Free on the App Store — no account required

<p align="center">
  <img src="screenshots/01_welcome.png" width="200" />
  <img src="screenshots/03_home.png" width="200" />
  <img src="screenshots/04_keyboard.png" width="200" />
  <img src="screenshots/05_playground.png" width="200" />
</p>

## Features

### iOS

- **Custom Keyboard Extension** — Tap "Yap" from any text field in any app to dictate with on-device Whisper
- **Live Activity** — Real-time transcription status on the Lock Screen and Dynamic Island
- **Model Hub** — Download and switch between multiple ASR models (WhisperKit Neural Engine, ONNX CPU)
- **ASR Playground** — Record and transcribe in-app to test speed and accuracy
- **Notepad** — Built-in scratchpad for quick voice drafts
- **Guided Onboarding** — Step-by-step setup for microphone, keyboard, and model download
- **Deep Links** — `yaprun://startFlow`, `yaprun://playground`, `yaprun://kill` for keyboard ↔ app communication

### macOS

- **Menu Bar Agent** — Runs as a background agent with a persistent menu bar icon
- **Global Hotkey** — System-wide keyboard shortcut to dictate and insert text at the cursor
- **Flow Bar** — Floating overlay showing dictation status
- **Hub Window** — Model management, playground, notepad, and settings in a single window

### Shared (iOS + macOS)

- **Multiple ASR Backends** — WhisperKit (Apple Neural Engine via Core ML) and ONNX (CPU via sherpa-onnx)
- **Model Registry** — Curated models with consumer-friendly names: Fast (70 MB), Accurate (134 MB), Compact CPU (118 MB), Whisper CPU (75 MB)
- **Offline-Ready** — Download once during setup, run without a network connection
- **Dictation History** — Recent transcriptions stored locally with timestamps

## Architecture

```
YapRun/
├── YapRunApp.swift              # App entry point (iOS WindowGroup + macOS agent)
├── ContentView.swift            # iOS home screen (status cards, model hub, history)
├── Core/
│   ├── AppColors.swift          # Design tokens (dark theme, orange CTA)
│   ├── AppTypes.swift           # Shared enums and type aliases
│   ├── ModelRegistry.swift      # ASR model definitions and SDK registration
│   ├── ClipboardService.swift   # Cross-platform pasteboard access
│   └── DictationHistory.swift   # Local history persistence
├── Features/
│   ├── Home/                    # Model cards, download progress, home VM
│   ├── Playground/              # Record → transcribe test bench
│   ├── Notepad/                 # Voice-first text editor
│   ├── Onboarding/              # Multi-step guided setup (mic, keyboard, model)
│   └── VoiceKeyboard/           # Flow session manager, Live Activity, deep links
├── Shared/
│   ├── SharedConstants.swift    # App group keys, Darwin notification names, URL scheme
│   └── SharedDataBridge.swift   # App ↔ keyboard extension shared state via UserDefaults suite
├── macOS/
│   ├── MacAppDelegate.swift     # Agent lifecycle, hub window, flow bar
│   ├── Features/                # macOS-specific views (hub, playground, settings, onboarding)
│   └── Services/                # Hotkey, text insertion, audio feedback, permissions
├── YapRunKeyboard/              # iOS keyboard extension (separate target)
└── YapRunActivity/              # Live Activity widget (separate target)
```

### Key Patterns

- **Flow Session (WisprFlow pattern)**: The keyboard extension triggers the main app via deep link (`yaprun://startFlow`). The app starts `AVAudioEngine` while foregrounded, keeps alive via Live Activity, then receives Darwin notifications (`startListening` / `stopListening`) from the keyboard to gate audio buffering and transcription.
- **Dual Runtime**: WhisperKit runs on Apple Neural Engine (Core ML) for speed; ONNX via sherpa-onnx runs on CPU as a fallback.
- **Shared Data Bridge**: App and keyboard extension communicate through a shared `UserDefaults` suite and Darwin notifications — no network calls.

## Requirements

| Platform | Minimum | Recommended |
|----------|---------|-------------|
| iOS      | 16.0    | 17.0+       |
| macOS    | 14.0    | 15.0+       |
| Xcode    | 15.0    | 16.0+       |

## Getting Started

1. Open the project in Xcode:

```bash
cd Playground/YapRun
open YapRun.xcodeproj
```

2. Select the **YapRun** scheme and your target device/simulator.

3. Build and run. The onboarding flow will guide you through microphone permission, keyboard setup, and model download.

> **Keyboard Extension**: To use the custom keyboard on iOS, go to **Settings → General → Keyboard → Keyboards → Add New Keyboard** and select **YapRun**. Enable **Full Access** when prompted.

## Models

All models are downloaded from GitHub Releases and cached on-device:

| Model | Backend | Size | Best For |
|-------|---------|------|----------|
| Fast (whisperkit-tiny.en) | WhisperKit / Neural Engine | 70 MB | Quick notes, low battery |
| Accurate (whisperkit-base.en) | WhisperKit / Neural Engine | 134 MB | Longer dictation, higher accuracy |
| Compact CPU (moonshine-tiny-en-int8) | ONNX / sherpa-onnx | 118 MB | When Neural Engine is busy |
| Whisper CPU (whisper-tiny.en) | ONNX / sherpa-onnx | 75 MB | Maximum device compatibility |

## Building the macOS .dmg

The `scripts/build_dmg.sh` script automates the full pipeline: archive, Developer ID signing, Apple notarization, and a professional .dmg installer with drag-to-Applications.

### One-time setup

```bash
# 1. Install create-dmg
brew install create-dmg

# 2. Store notarization credentials in your keychain
xcrun notarytool store-credentials "YapRun-Notarize" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

> Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com) under Sign-In and Security.

### Build

```bash
cd Playground/YapRun

# Full pipeline: archive → sign → notarize → .dmg
./scripts/build_dmg.sh

# Skip notarization (quick local test)
./scripts/build_dmg.sh --skip-notarize

# Re-package an existing export without rebuilding
./scripts/build_dmg.sh --skip-build
```

The final `.dmg` is written to `build/YapRun-<version>-mac.dmg`.

### Publishing

Upload the .dmg to a **GitHub Release** for direct download:

```bash
gh release create v1.0.0-mac "build/YapRun-1.0.0-mac.dmg" \
  --title "YapRun 1.0.0 for macOS" \
  --notes "Direct download for macOS 14.0+. Signed and notarized by Apple."
```

Then link to it from [runanywhere.ai/yaprun](https://runanywhere.ai/yaprun).
