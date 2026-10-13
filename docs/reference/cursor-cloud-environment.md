# Cursor Cloud / Linux VM environment

Linked from `AGENTS.md`. Only relevant when you're actually running on a Linux cloud VM
(Cursor Cloud or similar) rather than a developer's macOS/Windows machine — most tasks
don't need this file.

## What's buildable

| Component | Build | Test | Lint | Notes |
|-----------|-------|------|------|-------|
| Kotlin SDK (Android target) | `cd bindings/kotlin && ./gradlew compileDebugKotlin -Prunanywhere.useLocalNatives=false` | Android unit tests require device/emulator | `cd bindings/kotlin && ./gradlew ktlintCheck` | Single-target Android library (no KMP). `androidx.annotation` is always available because the build only targets Android. |
| Web SDK (TypeScript) | `npm run build -w packages/core` (from `bindings/web/`) | N/A | Prefer workspace `npm run typecheck` (builds core `dist/` before backends). Isolated `npm run typecheck -w packages/{llamacpp,onnx}` needs a fresh `npm run build -w packages/core` first — backends resolve `@runanywhere/web/backend` through the gitignored `packages/core/dist` types |
| Web minimal example | `npm run dev` (from `bindings/web/example/`) | Manual browser testing at `localhost:3000` | N/A | Streams one completion; needs the WASM pairs built |
| C++ Commons (core) | `cmake -B build ... && cmake --build build` (from `core/`) | `./build/tests/test_core --run-all` (13 tests, no models needed) | N/A | Must use `gcc`/`g++` via `CC=gcc CXX=g++` (clang lacks C++ stdlib headers). Pass `-DRAC_BUILD_PLATFORM=OFF` on Linux |
| C++ Commons (full backends) | `CC=gcc CXX=g++ ./scripts/build-linux.sh` | Backend tests need downloaded models | N/A | Builds the canonical Linux release preset and packages the staged shared libraries and public headers |
| iOS/Swift SDK | Not buildable | Not buildable | Not available | Requires macOS + Xcode |
| Android emulator | Not runnable | Not runnable | N/A | No KVM support in cloud VM |

## Key gotchas

- **Android SDK**: installed at `/opt/android-sdk`. `ANDROID_HOME` and `JAVA_HOME` are set in `~/.bashrc`.
- **JDK 17**: required by the Gradle JVM toolchain. Both JDK 17 and JDK 21 are installed.
- **`useLocalNatives` flag**: `true` in `gradle.properties`. Pass `-Prunanywhere.useLocalNatives=false` to Gradle to avoid needing the Android NDK (downloads pre-built JNI libs from GitHub Releases instead of building locally).
- **C++ compiler**: the default clang on this VM lacks `libc++` headers. Use `gcc`/`g++` via `-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`.
- **`local.properties`**: auto-created at root, `bindings/kotlin/`, and `bindings/kotlin/example/` with `sdk.dir=/opt/android-sdk`.
- **pre-commit hooks**: installed via `pre-commit install`. Requires `git config --unset-all core.hooksPath` first if `core.hooksPath` is already set.
