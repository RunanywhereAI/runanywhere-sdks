# RunAnywhere Kotlin SDK — Development Guide

This guide is for contributors building the Kotlin/Android SDK from source, running tests, and validating changes with the sample app. For integration instructions, see the [consumer README](../README.md).

**Related docs:**

- [ARCHITECTURE.md](ARCHITECTURE.md) — internal design, threading, module system
- [KOTLIN_MAVEN_CENTRAL_PUBLISHING.md](KOTLIN_MAVEN_CENTRAL_PUBLISHING.md) — Maven Central release process
- [Documentation.md](Documentation.md) — full public API reference

---

## Prerequisites

| Tool | Version |
|------|---------|
| Android Studio | Latest stable |
| Android NDK | 27.3.13750724 (via SDK Manager) |
| CMake | Via Android SDK Manager |
| JDK | 17 |
| Kotlin | 2.0+ |
| Bash | macOS or Linux terminal |

The NDK pin is canonical in `sdk/runanywhere-commons/VERSIONS` (`NDK_VERSION`) and mirrored in this module's `gradle.properties` as `racNdkVersion`. NDK 27 is the current LTS line and the first that ships the 16 KB page alignment Android 15+ requires.

---

## First-Time Setup

The SDK depends on native C++ libraries from `runanywhere-commons`. A Gradle task builds them locally so you can develop and test end-to-end.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-kotlin

# First-time setup (~10–15 minutes)
./gradlew setupLocalDevelopment
```

**What the task does:**

1. Runs `scripts/build/build-core-android.sh` from the repo root
2. Downloads native dependencies (Sherpa-ONNX, ~500 MB)
3. Builds `runanywhere-commons` for Android
4. Stages JNI libraries (`.so` files) into `src/main/jniLibs/` and each backend module's `jniLibs/`

`runanywhere.useLocalNatives` already defaults to `true` in `gradle.properties`, so no flag flip is needed after setup.

---

## Local vs Remote Native Binaries

Two modes are controlled by `runanywhere.useLocalNatives` in `gradle.properties`:

| Mode | Setting | Description |
|------|---------|-------------|
| **Local** | `runanywhere.useLocalNatives=true` | Uses JNI libs from `src/main/jniLibs/` (development) |
| **Remote** | `runanywhere.useLocalNatives=false` | Downloads JNI libs from GitHub releases (consumers) |

The checked-in default is `true`. CI overrides it per invocation with `-Prunanywhere.useLocalNatives=false` so it can pull pre-built `.so` files from GitHub Releases instead of needing an NDK.

---

## Project Structure

```
sdk/runanywhere-kotlin/
├── src/
│   ├── main/kotlin/          # Kotlin source
│   ├── main/jniLibs/         # Per-ABI native .so files
│   └── test/kotlin/          # Unit tests
├── modules/
│   ├── runanywhere-core-llamacpp/   # LLM backend (Maven: runanywhere-llamacpp)
│   ├── runanywhere-core-onnx/       # STT/TTS/VAD backend (Maven: runanywhere-onnx)
│   └── runanywhere-core-qhexrt/     # Qualcomm NPU backend (optional)
├── scripts/
│   └── package-sdk.sh        # CI packaging: local Maven repository ZIP
└── gradle.properties         # runanywhere.useLocalNatives, racNdkVersion
```

Published Maven coordinates use group `io.github.sanchitmonga22`. See [KOTLIN_MAVEN_CENTRAL_PUBLISHING.md](KOTLIN_MAVEN_CENTRAL_PUBLISHING.md) for release details.

---

## Testing with the Android Sample App

The recommended way to validate SDK changes is the sample app at `examples/android/RunAnywhereAI/`:

1. Complete setup (above)
2. Stage the SDK AARs into the sample app:

   ```bash
   cd ../../examples/android/RunAnywhereAI
   ./scripts/stage-sdk-aars.sh debug
   ```

3. Open Android Studio → **Open** → `examples/android/RunAnywhereAI`
4. Wait for Gradle sync
5. Connect an ARM64 device or emulator
6. Run the app

The sample app does not consume this module as a Gradle project. It depends on staged release AARs copied into `examples/android/RunAnywhereAI/libs/`, so SDK changes need a restage before the app sees them:

```
Sample App → libs/runanywhere-{sdk,llamacpp,onnx,qhexrt}.aar
                        ↑
          examples/android/RunAnywhereAI/scripts/stage-sdk-aars.sh debug
                        ↑
             src/main/jniLibs/  ←  ./gradlew setupLocalDevelopment
```

---

## Development Workflow

**After modifying Kotlin SDK code:**

```bash
./gradlew assembleDebug
```

Or rebuild in Android Studio.

**After modifying `runanywhere-commons` (C++):**

```bash
cd sdk/runanywhere-kotlin
./gradlew rebuildCommons
```

Then restage the AARs before testing with the sample app.

---

## Gradle Task Reference

| Task | Description |
|------|-------------|
| `setupLocalDevelopment` | First-time setup: build the C++ JNI libraries from source and stage them |
| `rebuildCommons` | Force a rebuild of `runanywhere-commons` after C++ changes |
| `downloadJniLibs` | Fetch pre-built `.so` files from GitHub Releases instead of building |
| `assembleDebug` / `assembleRelease` | Build the Android library AAR |
| `publishToMavenLocal` | Publish to `~/.m2/repository` |
| `clean` | Clean build directories |

Build outputs land in `build/outputs/aar/runanywhere-kotlin-{debug,release}.aar`, with the backend module AARs under `modules/runanywhere-core-{llamacpp,onnx,qhexrt}/build/outputs/aar/`.

`scripts/package-sdk.sh` is the CI packaging entry point. It accepts `--natives-from PATH` for pre-staged `.so` files and emits one deterministic local Maven repository ZIP.

---

## Code Quality

Run before submitting PRs:

```bash
./gradlew detekt        # Static analysis
./gradlew ktlintCheck   # Formatting check
./gradlew ktlintFormat  # Auto-fix formatting
```

---

## Testing

| Type | Command |
|------|---------|
| Unit tests (debug variant) | `./gradlew testDebugUnitTest` |
| Unit tests (all variants) | `./gradlew test` |
| Instrumented tests | Run from Android Studio on a connected device |
| Manual validation | Use the sample app on a real ARM64 device |

Tests live under `src/test/kotlin/`. Most exercise Kotlin-layer logic and run without the native library loaded; the ones that need JNI require `setupLocalDevelopment` to have run first.

This is a single-target Android library, not a Kotlin Multiplatform module, so there is no `jvmTest` task.

---

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes
4. Run `./gradlew detekt ktlintCheck`
5. Test with the sample app
6. Commit and push
7. Open a Pull Request

When reporting issues, include SDK version, Android API level, device model, reproduction steps, and relevant logcat output (with sensitive data redacted).

---

## Support

- **Discord:** https://discord.gg/N359FBbDVd
- **Email:** founders@runanywhere.ai
- **GitHub Issues:** https://github.com/RunanywhereAI/runanywhere-sdks/issues
