# AGENTS.md

## Cursor Cloud specific instructions

### Environment Overview

This is a cross-platform SDK monorepo. On a Linux cloud VM, the buildable services are:

| Component | Build | Test | Lint | Notes |
|-----------|-------|------|------|-------|
| Kotlin SDK (Android target) | `./gradlew :runanywhere-kotlin:compileDebugKotlinAndroid -Prunanywhere.testLocal=false` | Android unit tests require device/emulator | `./gradlew :runanywhere-kotlin:runKtlintCheckOverCommonMainSourceSet` | JVM target has a known issue: `RAGBridge.kt` in `jvmAndroidMain` imports `@Keep` from `androidx.annotation` which is unavailable for JVM compilation |
| Web SDK (TypeScript) | `npm run build -w packages/core` (from `sdk/runanywhere-web/`) | N/A | `npm run typecheck -w packages/core` | `llamacpp` package has a pre-existing duplicate index signature TS error |
| Web Example App | `npm run dev` (from `examples/web/RunAnywhereAI/`) | Manual browser testing at `localhost:5173` | N/A | Full Vite app, works in demo mode without WASM |
| C++ Commons | `cmake -B build ... && cmake --build build` (from `sdk/runanywhere-commons/`) | Tests require model files | N/A | Must use `gcc`/`g++` on this VM (clang lacks C++ stdlib headers). Pass `-DRAC_BUILD_PLATFORM=OFF` on Linux |
| iOS/Swift SDK | Not buildable | Not buildable | Not available | Requires macOS + Xcode |

### Key Gotchas

- **Android SDK**: Installed at `/opt/android-sdk`. `ANDROID_HOME` and `JAVA_HOME` are set in `~/.bashrc`.
- **JDK 17**: Required by Gradle JVM toolchain. Both JDK 17 and JDK 21 are installed.
- **`testLocal` flag**: Set to `true` in `gradle.properties`. Pass `-Prunanywhere.testLocal=false` to Gradle to avoid needing Android NDK (downloads pre-built JNI libs from GitHub releases instead of building locally).
- **C++ compiler**: Default clang on this VM lacks `libc++` headers. Use `gcc`/`g++` via `-DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++`.
- **`local.properties`**: Auto-created at root, `sdk/runanywhere-kotlin/`, and `examples/android/RunAnywhereAI/` with `sdk.dir=/opt/android-sdk`.
- **pre-commit hooks**: Installed via `pre-commit install`. Requires `git config --unset-all core.hooksPath` first if `core.hooksPath` is set.

### Standard commands

See `CLAUDE.md` for comprehensive build/test/lint commands for all SDK platforms. See `CONTRIBUTING.md` for contributor setup flow.
