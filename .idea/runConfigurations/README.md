# IntelliJ Run Configurations

**Simplified Development Workflow!**

- **Android App:** SDK builds automatically as a local module
- **IntelliJ Plugin:** SDK publishes to Maven Local automatically

## 🎯 Quick Reference

| #   | Task                  | Command                  | What It Does                        |
|-----|-----------------------|--------------------------|-------------------------------------|
| 1️⃣ | Build Android App     | `buildAndroidApp`        | Build Android APK (SDK auto-builds) |
| 2️⃣ | Run Android App       | `runAndroidApp`          | Build + Install + Launch on device  |
| 3️⃣ | Build IntelliJ Plugin | `buildIntellijPlugin`    | Publish SDK + Build plugin          |
| 4️⃣ | Run IntelliJ Plugin   | `runIntellijPlugin`      | Publish SDK + Run plugin in sandbox |
| 5️⃣ | Clean All             | `cleanAll`               | Clean all build artifacts           |
| 📦  | Publish SDK           | `publishSdkToMavenLocal` | Publish SDK for external projects   |

## 🎯 Quick Start

Just run what you need:

- **Android App?** → Use task #1 or #2 (SDK builds automatically)
- **IntelliJ Plugin?** → Use task #3 or #4 (SDK publishes automatically)
- **Build Issues?** → Use task #5 (Clean All)
- **External Projects?** → Use `publishSdkToMavenLocal`

---

## 📱 Android App Tasks

### 1️⃣ Build Android App
- **Task:** `buildAndroidApp`
- **What it does:** Builds the Android sample app (SDK builds automatically as a local module)
- **Output:** `examples/android/RunAnywhereAI/app/build/outputs/apk/debug/app-debug.apk`
- **Use when:** You want to build the APK only
- **Note:** SDK changes are immediately reflected (no publish needed!)

### 2️⃣ Run Android App
- **Task:** `runAndroidApp`
- **What it does:** Builds, installs, and launches the app on connected device
- **Requirements:** Android device or emulator must be connected (check with `adb devices`)
- **Use when:** You want to test the app on a device

---

## 💡 IntelliJ Plugin Tasks

### 3️⃣ Build IntelliJ Plugin
- **Task:** `buildIntellijPlugin`
- **What it does:** Publishes SDK to Maven Local, then builds the IntelliJ plugin
- **Output:** `examples/intellij-plugin-demo/plugin/build/distributions/runanywhere-voice-*.zip`
- **Use when:** You want to build the plugin distribution
- **Note:** SDK is automatically published to Maven Local first

### 4️⃣ Run IntelliJ Plugin
- **Task:** `runIntellijPlugin`
- **What it does:** Publishes SDK to Maven Local, then launches the plugin in a sandbox IDE window
- **Note:** A new IntelliJ IDEA window will open for testing
- **Use when:** You want to test the plugin functionality

---

## 🧹 Clean Task

### 5️⃣ Clean All
- **Task:** `cleanAll`
- **What it does:** Cleans all build artifacts (SDK, Android app, and IntelliJ plugin)
- **Use when:** Starting fresh or resolving build issues

---

## 🎁 SDK Publishing (Optional)

If you need to publish the SDK for use in external projects:

```bash
./gradlew publishSdkToMavenLocal
```

This publishes the SDK to `~/.m2/repository`. This is **automatically done** for IntelliJ plugin
tasks but **not needed** for Android app.

---

## 💡 How It Works

### Android App - Local Module ✅

The Android app includes the SDK as a **local Gradle module**:

```kotlin
// In examples/android/RunAnywhereAI/settings.gradle.kts
include(":sdk:runanywhere-kotlin")
project(":sdk:runanywhere-kotlin").projectDir = file("../../../sdk/runanywhere-kotlin")

// In app/build.gradle.kts
implementation(project(":sdk:runanywhere-kotlin"))
```

**Benefits:**
- ✅ SDK builds automatically when you build the app
- ✅ SDK changes are immediately reflected
- ✅ No publish/sync needed
- ✅ Fastest development workflow

### IntelliJ Plugin - Maven Local 📦

The IntelliJ plugin uses the SDK from **Maven Local** because:

- IntelliJ plugins are JVM-only and can't include KMP projects as local modules
- The build tasks automatically publish SDK to Maven Local first

```kotlin
// In examples/intellij-plugin-demo/plugin/build.gradle.kts
implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:0.1.0")
```

**No manual publishing needed** - the `buildIntellijPlugin` and `runIntellijPlugin` tasks handle
this automatically!

---

## 🚀 Typical Workflows

1. **First time setup:**
   ```bash
   ./gradlew cleanAll
   ./gradlew buildAndroidApp  # or buildIntellijPlugin
   ```

2. **Developing Android app:**
  - Just run task #2 (Run Android App)
  - SDK rebuilds automatically if changed
  - No publish step needed!

3. **Developing IntelliJ plugin:**
  - Just run task #4 (Run IntelliJ Plugin)
  - SDK publishes automatically before plugin builds
  - One command does everything!

4. **SDK changes:**
  - **For Android:** Just build/run the app (SDK rebuilds automatically)
  - **For Plugin:** Just build/run the plugin (SDK publishes automatically)

5. **Build issues:**
  - Run task #5 (Clean All)
  - Then build/run again
