# AGENTS.md

## Cursor Cloud specific instructions

### Environment Overview

This is a cross-platform SDK monorepo. On a Linux cloud VM, the buildable services are:

| Component | Build | Test | Lint | Notes |
|-----------|-------|------|------|-------|
| Kotlin SDK (Android target) | `./gradlew :runanywhere-kotlin:compileDebugKotlinAndroid -Prunanywhere.testLocal=false` | Android unit tests require device/emulator | `./gradlew :runanywhere-kotlin:runKtlintCheckOverCommonMainSourceSet` | JVM target has a known issue: `RAGBridge.kt` in `jvmAndroidMain` imports `@Keep` from `androidx.annotation` which is unavailable for JVM compilation |
| Web SDK (TypeScript) | `npm run build -w packages/core` (from `sdk/runanywhere-web/`) | N/A | `npm run typecheck -w packages/core` | `llamacpp` package has a pre-existing duplicate index signature TS error |
| Web Example App | `npm run dev` (from `examples/web/RunAnywhereAI/`) | Manual browser testing at `localhost:5173` | N/A | Full Vite app, works in demo mode without WASM |
| C++ Commons (core) | `cmake -B build ... && cmake --build build` (from `sdk/runanywhere-commons/`) | `./build/tests/test_core --run-all` (13 tests, no models needed) | N/A | Must use `gcc`/`g++` via `CC=gcc CXX=g++` (clang lacks C++ stdlib headers). Pass `-DRAC_BUILD_PLATFORM=OFF` on Linux |
| C++ Commons (full backends) | `CC=gcc CXX=g++ bash scripts/build-linux.sh --shared` | Backend tests need downloaded models | N/A | Builds onnx+llamacpp. RAG backend has pre-existing zero-size array bug; use `-DRAC_BACKEND_RAG=OFF`. Sherpa-ONNX v1.12.23 URL changed: use `sherpa-onnx-v{VER}-linux-x64-shared.tar.bz2` (no `-cpu` suffix) |
| Linux Voice Assistant | `cmake -B build && cmake --build build` (from `Playground/linux-voice-assistant/`) | `./build/test-pipeline <audio.wav>` runs full VAD→STT→LLM→TTS pipeline | N/A | Requires: ALSA headers (`libasound2-dev`), built commons with backends, downloaded models (`./scripts/download-models.sh`). Audio capture needs real hardware; `test-pipeline` works headless |
| iOS/Swift SDK | Not buildable | Not buildable | Not available | Requires macOS + Xcode |
| Android emulator | Not runnable | Not runnable | N/A | No KVM support in cloud VM |

### Key Gotchas

- **Android SDK**: Installed at `/opt/android-sdk`. `ANDROID_HOME` and `JAVA_HOME` are set in `~/.bashrc`.
- **JDK 17**: Required by Gradle JVM toolchain. Both JDK 17 and JDK 21 are installed.
- **`testLocal` flag**: Set to `true` in `gradle.properties`. Pass `-Prunanywhere.testLocal=false` to Gradle to avoid needing Android NDK (downloads pre-built JNI libs from GitHub releases instead of building locally).
- **C++ compiler**: Default clang on this VM lacks `libc++` headers. Use `gcc`/`g++` via `-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`.
- **`local.properties`**: Auto-created at root, `sdk/runanywhere-kotlin/`, and `examples/android/RunAnywhereAI/` with `sdk.dir=/opt/android-sdk`.
- **pre-commit hooks**: Installed via `pre-commit install`. Requires `git config --unset-all core.hooksPath` first if `core.hooksPath` is set.

### Linux Voice Assistant Quick Start

```bash
# 1. Build commons with backends
cd sdk/runanywhere-commons
CC=gcc CXX=g++ cmake -B build-linux-x86_64 -DCMAKE_BUILD_TYPE=Release \
  -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_ONNX=ON -DRAC_BACKEND_LLAMACPP=ON \
  -DRAC_BACKEND_RAG=OFF -DRAC_BUILD_SHARED=ON -DRAC_BUILD_PLATFORM=OFF
cmake --build build-linux-x86_64 -j$(nproc)

# 2. Copy libs to dist
# (see build-linux.sh for full dist copy steps)

# 3. Build voice assistant
cd Playground/linux-voice-assistant
CC=gcc CXX=g++ cmake -B build && cmake --build build

# 4. Run test pipeline (headless, no mic needed)
export LD_LIBRARY_PATH="../../sdk/runanywhere-commons/dist/linux/x86_64:../../sdk/runanywhere-commons/third_party/sherpa-onnx-linux/lib"
./build/test-pipeline /path/to/audio.wav
```

### Standard commands

See `CLAUDE.md` for comprehensive build/test/lint commands for all SDK platforms. See `CONTRIBUTING.md` for contributor setup flow.
