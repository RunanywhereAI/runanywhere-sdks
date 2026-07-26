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
| Android NDK | v27+ (via SDK Manager) |
| CMake | Via Android SDK Manager |
| Kotlin | 2.0+ |
| Bash | macOS or Linux terminal |

---

## First-Time Setup

The SDK depends on native C++ libraries from `runanywhere-commons`. The setup script builds these locally so you can develop and test end-to-end.

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-kotlin

# First-time setup (~10–15 minutes)
./scripts/build-kotlin.sh --setup
```

**What the setup script does:**

1. Downloads dependencies (Sherpa-ONNX, ~500 MB)
2. Builds `runanywhere-commons` for Android (arm64-v8a by default)
3. Copies JNI libraries (`.so` files) to module `jniLibs/` directories
4. Sets `runanywhere.useLocalNatives=true` in `gradle.properties`

---

## Local vs Remote Native Binaries

Two modes are controlled by `runanywhere.useLocalNatives` in `gradle.properties`:

| Mode | Setting | Description |
|------|---------|-------------|
| **Local** | `runanywhere.useLocalNatives=true` | Uses JNI libs from `src/main/jniLibs/` (development) |
| **Remote** | `runanywhere.useLocalNatives=false` | Downloads JNI libs from GitHub releases (consumers) |

The `--setup` flag sets `runanywhere.useLocalNatives=true` automatically.

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
│   └── build-kotlin.sh       # Build automation
└── gradle.properties         # runanywhere.useLocalNatives flag
```

Published Maven coordinates use group `io.github.sanchitmonga22`. See [KOTLIN_MAVEN_CENTRAL_PUBLISHING.md](KOTLIN_MAVEN_CENTRAL_PUBLISHING.md) for release details.

---

## Testing with the Android Sample App

The recommended way to validate SDK changes is the sample app at `examples/android/RunAnywhereAI/`:

1. Complete setup (above)
2. Open Android Studio → **Open** → `examples/android/RunAnywhereAI`
3. Wait for Gradle sync
4. Connect an ARM64 device or emulator
5. Run the app

Local development loop:

```
Sample App → Local Kotlin SDK (includeBuild) → Local JNI libs (jniLibs/)
                                                      ↑
                                         build-kotlin.sh --setup
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
./scripts/build-kotlin.sh --local --rebuild-commons
```

---

## Build Script Reference

| Command | Description |
|---------|-------------|
| `--setup` | First-time setup: download deps, build libs, enable local natives |
| `--local` | Use locally built libs from `jniLibs/` |
| `--remote` | Use remote libs from GitHub releases |
| `--rebuild-commons` | Force rebuild of runanywhere-commons |
| `--clean` | Clean build directories before building |
| `--abis=ABIS` | ABIs to build (default: `arm64-v8a`; use `arm64-v8a,armeabi-v7a` for broader coverage) |
| `--skip-build` | Skip Gradle build (native setup only) |

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
| Unit tests | `./gradlew jvmTest` |
| Instrumented tests | Run from Android Studio on a connected device |
| Manual validation | Use the sample app on a real ARM64 device |

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
