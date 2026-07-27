# RunAnywhere AI — Android Example

<p align="center">
  <img src="../../../examples/logo.svg" alt="RunAnywhere Logo" width="120"/>
</p>

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai">
    <img src="https://img.shields.io/badge/Google%20Play-Download-414141?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20API%2024%2B-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android API 24+" />
  <img src="https://img.shields.io/badge/Kotlin-2.4%2B-7F52FF?style=flat-square&logo=kotlin&logoColor=white" alt="Kotlin 2.4+" />
  <img src="https://img.shields.io/badge/UI-Jetpack%20Compose-4285F4?style=flat-square&logo=jetpackcompose&logoColor=white" alt="Jetpack Compose" />
  <img src="https://img.shields.io/badge/License-RunAnywhere-blue?style=flat-square" alt="RunAnywhere License" />
</p>

**A production-ready reference app for the [RunAnywhere Kotlin SDK](../../../sdk/runanywhere-kotlin/).** Chat, speech, vision, voice agents, RAG, and model management—all running on-device with privacy-first, offline-capable inference.

---

## Requirements

| Item | Minimum |
|------|---------|
| **Android Studio** | Latest stable (Ladybug or newer recommended) |
| **Android SDK** | API 24+ (Android 7.0); compile/target SDK 37 |
| **JDK** | 17 |
| **NDK & CMake** | As required by the repo root native build scripts |
| **Disk space** | Several GB for native builds and downloaded AI models |
| **Device** | ARM64 physical device recommended; emulator supported for most features |

Export `ANDROID_HOME` and `ANDROID_NDK_HOME` before building native libraries.

---

## Setup

> **Important:** This sample consumes four local AARs from `libs/` (core, LlamaCPP, ONNX, QHexRT). A clean clone must build native libraries and stage SDK artifacts before the app will compile.

### 1. Clone and open the example

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/android/RunAnywhereAI
```

### 2. Build native libraries (repo root)

From the example directory, build the Android native core for your target ABI:

```bash
../../../scripts/build/build-core-android.sh arm64-v8a
```

This produces the JNI libraries the Kotlin SDK packages expect. Re-run this step after any change to the C++ layer in `runanywhere-commons`.

### 3. Stage SDK AARs into `libs/`

```bash
./scripts/stage-sdk-aars.sh debug
```

This builds the four Kotlin SDK modules (core, LlamaCPP, ONNX, QHexRT) against the staged natives and copies deterministic AAR names into `libs/`. Run again after SDK or native changes.

### 4. Verify and run

```bash
./scripts/verify.sh
```

Or open the project in Android Studio and run the **app** configuration, or install from the command line:

```bash
./gradlew :app:installDebug
```

### After modifying the SDK

| Change | Action |
|--------|--------|
| C++ / commons | Re-run `build-core-android.sh`, then `stage-sdk-aars.sh` |
| Kotlin SDK | Re-run `stage-sdk-aars.sh` |
| App UI only | Rebuild in Android Studio or `./gradlew :app:assembleDebug` |

---

## Features

| Feature | Description |
|---------|-------------|
| **AI Chat** | Streaming LLM conversations with analytics and thinking-mode support |
| **Speech-to-Text** | Batch and live transcription via Sherpa-ONNX / Whisper |
| **Text-to-Speech** | Neural Piper voices and system TTS fallback |
| **Voice Assistant** | Full STT → LLM → TTS pipeline |
| **Vision (VLM)** | Camera and image understanding |
| **RAG** | Document ingestion and on-device Q&A |
| **Model Management** | Download, load, unload, and delete models |
| **Storage** | Usage overview and cache cleanup |
| **Solutions** | YAML pipeline demos synced from shared catalog |
| **Offline** | Inference runs locally after models are downloaded |

---

## NPU / QHexRT (Snapdragon devices)

On supported Qualcomm Hexagon NPU hardware, the app can register the QHexRT backend for accelerated inference. The QHexRT AAR is included in the standard four-AAR staging flow.

To test private `runanywhere/*_HNPU` model bundles:

1. Open **Settings → Downloads**.
2. Enter a Hugging Face token and tap **Save token**.
3. Download and load an HNPU model from the model picker. The SDK resolves the correct Hexagon architecture natively.
4. Tap **Clear** to return to public, no-auth downloads.

The token is passed through the SDK at runtime; it is not stored in source, assets, or logs. Private QHexRT release and device-suite workflows live in a separate checkout—see your internal QHexRT documentation if you maintain that stack.

---

## Project structure

```
RunAnywhereAI/
├── app/src/main/java/com/runanywhere/runanywhereai/
│   ├── RunAnywhereApplication.kt    # SDK init and backend registration
│   ├── ui/screens/                  # Feature screens (chat, voice, vision, …)
│   ├── ui/navigation/               # Compose navigation
│   ├── ui/theme/                    # Material 3 theming (#FF6900 brand)
│   └── data/                        # Model catalog, settings repositories
├── libs/                            # Staged SDK AARs (not committed on clean clone)
├── scripts/
│   ├── stage-sdk-aars.sh            # Build and copy AARs into libs/
│   ├── verify.sh                    # Strict debug APK build gate
│   └── smoke.sh                     # Fast SDK API coverage check
└── README.md
```

The app depends on local AARs rather than Maven coordinates so SDK changes in the monorepo are immediately testable.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Missing `libs/*.aar` | Run `./scripts/stage-sdk-aars.sh debug` |
| Native link errors after commons changes | Re-run `../../../scripts/build/build-core-android.sh arm64-v8a`, then restage AARs |
| Gradle dependency verification failures | Ensure all four AARs are present; run `./scripts/verify.sh` for the exact gate |
| QHexRT / NPU models unavailable | Confirm device support and that the QHexRT AAR was staged; HNPU bundles require a saved HF token |
| Out of memory during native build | Close other Gradle daemons; the repo recommends limited workers for SDK builds |

For a quick static check without a full compile:

```bash
./scripts/smoke.sh
```

---

## Related links

| Resource | Link |
|----------|------|
| **Kotlin SDK** | [sdk/runanywhere-kotlin/README.md](../../../sdk/runanywhere-kotlin/README.md) |
| **iOS example** | [examples/ios/RunAnywhereAI](../../ios/RunAnywhereAI/README.md) |
| **React Native example** | [examples/react-native/RunAnywhereAI](../../react-native/RunAnywhereAI/README.md) |
| **Flutter example** | [examples/flutter/RunAnywhereAI](../../flutter/RunAnywhereAI/README.md) |
| **Play Store** | [com.runanywhere.runanywhereai](https://play.google.com/store/apps/details?id=com.runanywhere.runanywhereai) |
| **Discord** | [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd) |
| **Issues** | [GitHub Issues](https://github.com/RunanywhereAI/runanywhere-sdks/issues) |
| **Email** | founders@runanywhere.ai |

---

## License

This project is licensed under the RunAnywhere License (Apache 2.0 based, with additional commercial-use terms). See [LICENSE](../../../LICENSE) for details.
