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

> **Default:** the app resolves SDK packages from **Maven Central** (`io.github.sanchitmonga22:runanywhere-*:0.20.11`). No local native build is required for a clean clone.

### 1. Clone and open the example

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/examples/android/RunAnywhereAI
```

### 2. Configure Android SDK

Copy `local.properties.example` → `local.properties` and set `sdk.dir`, or export `ANDROID_HOME`.

Optional: set `runanywhere.baseUrl` / `runanywhere.apiKey` for production control-plane features. HNPU model downloads need a Hugging Face token entered in **Settings → Downloads** (private `runanywhere/*_HNPU` repos).

### 3. Verify and run

```bash
./scripts/verify.sh
# or
./gradlew :app:installDebug
```

Open the project in Android Studio and run the **app** configuration on an arm64 device (Snapdragon with Hexagon V75/V79/V81 for QHexRT).

### Optional: build against local monorepo AARs

Use this when iterating on unreleased SDK / native changes:

```bash
../../../scripts/build/build-core-android.sh arm64-v8a
./scripts/stage-sdk-aars.sh debug
./gradlew -Prunanywhere.useLocalSdkAars=true :app:assembleDebug
```

| Change | Action |
|--------|--------|
| Published SDK only | Bump `runanywhere` in `gradle/libs.versions.toml`, refresh locks |
| Local C++ / commons | `build-core-android.sh`, then `stage-sdk-aars.sh` + `-Prunanywhere.useLocalSdkAars=true` |
| App UI only | `./gradlew :app:assembleDebug` |

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

On supported Qualcomm Hexagon NPU hardware, the app registers the QHexRT backend from Maven Central (`runanywhere-qhexrt-android`). That AAR is **binary-only** (engine `.so` + QAIRT host libs + DSP skels + a thin Kotlin registration API). Engine C++ source is not published.

To test private `runanywhere/*_HNPU` model bundles:

1. Open **Settings → Downloads**.
2. Enter a Hugging Face token and tap **Save token**.
3. Download and load an HNPU model from the model picker. The SDK resolves the correct Hexagon architecture natively.
4. Tap **Clear** to return to public, no-auth downloads.

The token is passed through the SDK at runtime; it is not stored in source, assets, or logs.

Device acceptance (catalog sweep) lives in the sibling QHexRT checkout:

```bash
# From the neurun/QHexRT tree — uses Maven Central by default when the app is not
# forced onto local AARs:
QHexRT/device_suites/run_android_e2e.sh --serial <adb> --token "$HF_TOKEN" --arch v75 --build \
  lfm2_5_230m
```

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
├── libs/                            # Optional local AARs (gitignored; monorepo override)
├── scripts/
│   ├── stage-sdk-aars.sh            # Optional: build/copy local AARs into libs/
│   ├── verify.sh                    # Strict debug APK build gate (Maven by default)
│   └── smoke.sh                     # Fast SDK API coverage check
└── README.md
```

Default dependency path is Maven Central. Pass `-Prunanywhere.useLocalSdkAars=true` after `stage-sdk-aars.sh` to test unreleased SDK changes from the monorepo.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Cannot resolve `io.github.sanchitmonga22:runanywhere-*` | Check network / Maven Central; confirm version in `gradle/libs.versions.toml` |
| Missing `libs/*.aar` with local override | Run `./scripts/stage-sdk-aars.sh debug` and keep `-Prunanywhere.useLocalSdkAars=true` |
| Native link errors after local commons changes | Re-run `build-core-android.sh`, restage AARs, build with the local override |
| QHexRT / NPU models unavailable | Need Hexagon V75/V79/V81 hardware; HNPU bundles require a saved HF token |
| Out of memory during local native build | Close other Gradle daemons; limit workers for SDK builds |

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
